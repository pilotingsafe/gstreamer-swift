# RFC-002: Live-Source Reliable Packet Delivery Contract

**Status:** Proposed
**Date:** 2026-05-08
**Related work:** `RFC-001-realtime-vs-archival-packet-delivery`
**Decision owner:** TBD
**Scope:** Live-source reliable delivery, upstream queue policy, gap reporting

## Question

How should live sources (`is-live=true`) expose reliable packet delivery semantics without over-promising no-drop behavior that cannot be guaranteed by wall-clock-driven producers?

## Current Behavior

Current encoded live-source pipelines already drop at the GStreamer boundary before Swift queueing:

- `AudioSource` pipeline appends:

```swift
appsink name=<sink> sync=false drop=true max-buffers=1 emit-signals=true
```

- `VideoSource` pipeline appends the same appsink policy.

This means:

- Loss can occur in GStreamer even before `AsyncStream` bounded buffering.
- `packets()` remains appropriate for realtime best-effort monitoring.
- There is no explicit public contract for archival-style live capture.

## Problem

`RFC-001` correctly identifies that live sources cannot be backpressured like finite file/decode sources. For a slow consumer on a live source, the system is forced into one of three behaviors:

1. **Leaky queue/drop mode:** preserves latency, loses data.
2. **Bounded non-leaky/blocking mode:** can stall streaming threads and surface xruns.
3. **Unbounded buffering mode:** risks unbounded memory growth.

Additionally, live sources do not naturally produce EOS without explicit stop/finalize control, so termination semantics differ from finite sources.

## Goals

- Define an explicit, honest contract for reliable-style delivery on live sources.
- Reuse existing queue vocabulary (`QueueLeaky`) instead of introducing parallel terms.
- Keep current `packets()` semantics unchanged.
- Provide API affordances that force call-site acknowledgement of queue/backpressure trade-offs.
- Keep alignment with `RFC-001` generic `ReliablePackets<Element>` direction.

## Non-Goals

- Do not implement muxing, file finalization UX, or a full recording convenience API in this RFC.
- Do not guarantee indefinite zero-loss live capture under arbitrary consumer slowness.
- Do not change realtime `packets()` defaults.
- Do not define fan-out/multi-consumer delivery in this RFC.

## User Scenarios

### Scenario A: Time-boxed microphone recording

The user records 30 seconds of encoded audio and expects a complete output or an explicit failure.

### Scenario B: Time-boxed webcam capture

The user records encoded video from a webcam and needs deterministic finalization when stopping.

### Scenario C: Long-running live archival

The user records for long durations and accepts that gaps may occur, but requires gap observability.

### Scenario D: Realtime + archival dual-consumer pipeline

The user wants low-latency preview plus archival capture. This RFC only defines single-consumer semantics; fan-out is deferred.

## Options

### Option A: Keep live sources excluded from `reliablePackets()`

```swift
// No live-source reliable API surface.
```

**Pros**

- No semantic risk from over-promising reliability.
- No immediate API surface growth.

**Cons**

- No first-class archival path for microphone/webcam.
- Pushes complexity to each user.
- Leaves `RFC-001` live-source follow-up unresolved.

### Option B: Expose live reliable API with required builder opt-in

```swift
let source = try AudioSource.microphone()
  .withReliableDelivery(policy: .blockOnFull(maxBuffers: 256))
  .withOpusEncoding(bitrate: 128_000)
  .build()
```

**Pros**

- Makes trade-off explicit at construction time.
- Keeps default realtime path untouched.
- Provides a migration path for both audio and video builders.

**Cons**

- Adds configuration complexity.
- Users can still choose unsafe policy if documented poorly.

### Option C: Only offer duration-bounded reliable variants

```swift
try await source.record(for: .seconds(30))
```

or

```swift
source.reliablePackets(for: .seconds(30))
```

**Pros**

- Better UX for common recording tasks.
- Naturally frames stop/finalize boundaries.

**Cons**

- Higher-level API scope (recording workflow) beyond packet primitive.
- Still needs policy semantics underneath.

### Option D: Always expose reliable API, make gap first-class

```swift
public struct ReliablePacket<Payload: Sendable>: Sendable {
  public let payload: Payload
  public let gapsSinceLast: Int
}
```

**Pros**

- Honest about live-source discontinuities.
- Gives downstream logic control over retry/repair policy.

**Cons**

- More complex element type.
- Requires consistent gap detection semantics across sources.

### Option E: Hard-blocking only (`QueueLeaky.none`)

```swift
.withReliableDelivery(policy: .blockOnFull(maxBuffers: 256))
```

and fail on overrun/xrun.

**Pros**

- Strong "no silent drop" posture.
- Easier reasoning for strict archival callers.

**Cons**

- More runtime failures under pressure.
- Not suitable for all devices/platforms.

## Recommendation

Adopt **Option B + Option D**:

- `reliablePackets()` is exposed for live sources only when builder-level reliable delivery is explicitly configured.
- Reliable live packets carry gap metadata (`ReliablePacket`) so discontinuities are observable rather than silent.
- `record(for:)`-style APIs remain a future convenience layer (follow-up RFC), built on this contract.

This combination keeps the API honest while preserving existing realtime ergonomics.

## Queue Policy Contract

Introduce a live-source policy enum (final naming deferred):

```swift
public enum LiveSourceDeliveryPolicy: Sendable {
  case dropOldestPreservingLatency(maxBuffers: UInt)
  case blockOnFull(maxBuffers: UInt)
  case unboundedQueue
}
```

Policy mapping to existing queue vocabulary:

- `.dropOldestPreservingLatency(maxBuffers:)` -> `QueueLeaky.downstream` with bounded queue. This corresponds to GStreamer `leaky=2`, drops the oldest queued buffer when full, and keeps the consumer on the newest live frames.
- `.blockOnFull(maxBuffers:)` -> `QueueLeaky.none` with bounded queue; overflow/xrun surfaces as error.
- `.unboundedQueue` -> no practical cap; test/diagnostic only, documented as unsafe in production.

Behavioral contract:

- Policies are selected at source build time, not at iteration time.
- `reliablePackets()` semantics for live sources are defined by selected policy.
- Policy must be visible in doc comments and examples.

## AppSink Configuration

Realtime and reliable live modes must remain distinct.

Realtime (current behavior):

```swift
appsink name=<sink> sync=false drop=true max-buffers=1 emit-signals=true
```

Reliable mode baseline:

```swift
appsink name=<sink> sync=false drop=false max-buffers=<N> emit-signals=true
```

Where:

- `<N>` is derived from `LiveSourceDeliveryPolicy`.
- upstream `queue` is configured consistently with chosen `QueueLeaky` behavior.
- default realtime `packets()` path must not regress.

## Element Type

Use a wrapper for live reliable delivery:

```swift
public struct ReliablePacket<Payload: Sendable>: Sendable {
  public let payload: Payload
  public let gapsSinceLast: Int
}
```

Compatibility with `RFC-001`:

- Keep `ReliablePackets<Element>` generic unchanged.
- Live audio/video reliable entry points can specialize as `ReliablePackets<ReliablePacket<Buffer>>`.
- Non-live/file-style reliable entry points may continue returning `ReliablePackets<Buffer>` if gap metadata is not needed.

## API Sketch

```swift
public enum LiveSourceDeliveryPolicy: Sendable {
  case dropOldestPreservingLatency(maxBuffers: UInt)
  case blockOnFull(maxBuffers: UInt)
  case unboundedQueue
}

extension AudioSourceBuilder {
  public func withReliableDelivery(
    policy: LiveSourceDeliveryPolicy
  ) -> AudioSourceBuilder
}

extension VideoSourceBuilder {
  public func withReliableDelivery(
    policy: LiveSourceDeliveryPolicy
  ) -> VideoSourceBuilder
}

extension AudioSource {
  public func reliablePackets() -> ReliablePackets<ReliablePacket<Buffer>>
}

extension VideoSource {
  public func reliablePackets() -> ReliablePackets<ReliablePacket<Buffer>>
}
```

Runtime contract:

- Calling `reliablePackets()` without reliable builder opt-in is unsupported (trap or thrown configuration error; final mechanism deferred).
- Sequence remains single-consumer.

## Implementation Notes

- Reuse `RFC-001` continuation/cancellation bridge strategy for pull-based iteration; do not block Swift executor threads with direct blocking pulls.
- Detect discontinuities via GStreamer buffer flags (`GAP`, `DISCONT`) and/or monotonic packet sequence tracking; document the chosen signal as normative at implementation time.
- For live sources, termination is explicit: `stop()` initiates EOS/finalize-drain behavior to flush pending packets before sequence completion.
- Reliable live iteration must propagate pipeline/bus errors through throwing `next()`.

## Tests Required

- Time-boxed microphone capture with reliable policy yields expected packet count window and `gapsSinceLast == 0` under nominal load.
- Slow consumer + `.dropOldestPreservingLatency` yields `gapsSinceLast > 0` without silent termination.
- Slow consumer + `.blockOnFull` surfaces explicit overflow/xrun error (no silent truncation).
- Webcam stop/finalize path drains packets up to EOS boundary.
- Cancellation during iteration detaches sink handlers and leaks no resources/continuations.
- `packets()` and live `reliablePackets()` behavior remain distinct and documented.

## Documentation Required

- `withReliableDelivery(policy:)` docs must describe wall-clock consequences of each policy.
- `reliablePackets()` docs for live sources must clearly state policy-dependent behavior and gap semantics.
- README examples must show explicit builder opt-in for live reliable flows.
- Realtime monitoring examples must continue to prefer `packets()`.

## Migration Plan

1. Add builder-level live reliable policy surface for audio/video builders.
2. Keep `reliablePackets()` for live sources gated behind explicit reliable policy selection.
3. Land live-source implementation after `RFC-001` file/decode reliable path to reduce simultaneous semantic churn.
4. Add higher-level `record(to:for:)` convenience in a future RFC (tentative RFC-003).

## Resolved Decisions

- Live-source reliable exposure exists, but only with explicit builder opt-in.
- Queue policy terminology reuses `QueueLeaky` semantics.
- Gap metadata is first-class for live reliable packets via `ReliablePacket`.
- Realtime `packets()` defaults stay unchanged.

## Deferred Questions

- Final public name: `LiveSourceDeliveryPolicy` vs `LivePacketDeliveryPolicy`.
- Whether `.unboundedQueue` is public or test-only API.
- Final error model for unsupported `reliablePackets()` call without builder opt-in (trap vs thrown error).
- Multi-consumer/fan-out semantics and dedicated recording convenience API.
