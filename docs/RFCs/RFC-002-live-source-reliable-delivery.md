# RFC-002: Live-Source Reliable Packet Delivery Contract

**Status:** Accepted
**Date:** 2026-05-08
**Accepted:** 2026-05-10
**Related work:** `RFC-001-realtime-vs-archival-packet-delivery`, `tasks/prd-live-source-reliable-delivery.md`
**Decision owner:** TBD
**Scope:** Encoded live audio reliable delivery, upstream queue policy, discontinuity reporting, EOS finalization

## Question

How should live sources (`is-live=true`) expose reliable packet delivery semantics without over-promising no-drop behavior that cannot be guaranteed by wall-clock-driven producers?

## Current Behavior

Current encoded live-source pipelines already drop at the GStreamer boundary before Swift queueing:

- `AudioSource` pipeline appends:

```swift
appsink name=<sink> sync=false drop=true max-buffers=1 emit-signals=true
```

- `VideoSource` pipeline appends the same realtime appsink policy.

This means:

- Loss can occur in GStreamer before Swift queueing.
- `packets()` remains appropriate for realtime best-effort monitoring.
- There is no explicit public contract for archival-style live capture.

## Problem

`RFC-001` correctly identifies that live sources cannot be backpressured like finite file/decode sources. For a slow consumer on a live source, the system is forced into one of three behaviors:

1. **Leaky queue/drop mode:** preserves latency, loses data.
2. **Bounded non-leaky/blocking mode:** can stall streaming threads and surface xruns.
3. **Unbounded buffering mode:** risks unbounded memory growth.

Additionally, live sources do not naturally produce EOS without explicit stop/finalize control, so termination semantics differ from finite sources.

## Goals

- Define an explicit, honest contract for reliable-style delivery on encoded live audio sources.
- Reuse existing queue vocabulary (`QueueLeaky`) instead of introducing parallel Swift policy terms.
- Keep current realtime `packets()` and raw `buffers()` semantics unchanged.
- Make queue/backpressure trade-offs visible at source build time.
- Surface live-source discontinuities with structured metadata.
- Define deterministic EOS finalization for live reliable capture.
- Keep alignment with `RFC-001` generic `ReliablePackets<Element>` direction.

## Non-Goals

- Do not guarantee indefinite zero-loss live capture under arbitrary consumer slowness.
- Do not change realtime `packets()` defaults.
- Do not add raw reliable live buffers in this phase.
- Do not add public `VideoSource` reliable delivery API in this phase.
- Do not define fan-out/multi-consumer delivery in this RFC.
- Do not implement muxing, file finalization UX, or a full recording convenience API.
- Do not expose public unbounded reliable live queue configuration.

## Accepted Decision

Live reliable delivery is accepted for encoded `AudioSource` pipelines only, with required builder opt-in:

```swift
let source = try AudioSource.microphone()
  .withOpusEncoding(bitrate: 128_000)
  .withReliableDelivery(leaky: .none, maxTime: .seconds(2))
  .build()
```

The accepted design is:

- `withReliableDelivery(...)` configures a GStreamer `queue` directly with `QueueLeaky` and explicit `max-size-*` bounds.
- The default `leaky: .none` favors no silent queue drops when the consumer keeps up; callers that prefer low latency over completeness must explicitly choose `.downstream`.
- `reliablePackets()` is available on `AudioSource` but throws if reliable delivery was not configured before build.
- Reliable live packets use `ReliablePacket<Buffer>`, carrying timing and a structured `Discontinuity`.
- Live finalization is explicit through `finalize(timeout:)`, which sends EOS, waits for Bus EOS/ERROR with a timeout, then stops the pipeline.
- `VideoSource` reliable delivery, raw reliable buffers, branch/fan-out policies, and recording convenience APIs are deferred.

This keeps the Swift API thin over GStreamer primitives and avoids a parallel policy vocabulary.

## Public API Contract

### Builder Opt-In

```swift
extension AudioSourceBuilder {
  public func withReliableDelivery(
    leaky: QueueLeaky = .none,
    maxBuffers: UInt? = 256,
    maxBytes: UInt? = nil,
    maxTime: Duration? = .seconds(2)
  ) -> AudioSourceBuilder
}
```

Validation rules:

- Reliable delivery with `.raw` encoding is rejected at `build()` time:

```swift
AudioSource.AudioSourceError.invalidConfiguration(
  "Reliable live packet delivery requires encoded audio output; configure Opus or AAC encoding before build"
)
```

- Negative `maxTime` is rejected at `build()` time:

```swift
AudioSource.AudioSourceError.invalidConfiguration(
  "Reliable delivery maxTime must be non-negative"
)
```

- Effectively unbounded public reliable configuration is rejected at `build()` time:

```swift
AudioSource.AudioSourceError.invalidConfiguration(
  "Reliable delivery requires at least one finite non-zero queue bound"
)
```

Effectively unbounded means:

- `maxBuffers` is `nil` or `0`
- `maxBytes` is `nil` or `0`
- `maxTime` is `nil` or `.zero`

### Reliable Packets

```swift
extension AudioSource {
  public func reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>>
}
```

If reliable delivery was not configured before build, `reliablePackets()` throws:

```swift
GStreamerError.invalidArgument(
  parameter: "AudioSource.reliablePackets",
  reason: "Reliable delivery is not configured; call withReliableDelivery(...) before build()."
)
```

The sequence remains single-consumer, matching `RFC-001` and the existing `ReliablePackets<Element>` contract.

### Finalization

```swift
extension AudioSource {
  public func finalize(timeout: Duration = .seconds(5)) async throws
}
```

`finalize(timeout:)` performs:

1. Send EOS with `pipeline.sendEOS()`.
2. Wait for Bus EOS or ERROR with the provided timeout.
3. Wait until the reliable iterator has consumed to `nil` or has been cancelled.
4. Stop the pipeline after clean EOS or after reporting a terminal error.

If `sendEOS()` returns false, throw:

```swift
GStreamerError.busError(
  "Failed to send EOS event",
  source: "AudioSource.finalize",
  debug: nil
)
```

If Bus ERROR arrives before EOS, throw the parsed `GStreamerError.busError`.

If timeout expires before EOS or ERROR, throw:

```swift
GStreamerError.busError(
  "Timed out waiting for EOS during live reliable finalization",
  source: "AudioSource.finalize",
  debug: "timeout=<nanoseconds>"
)
```

Relationship to `stop()`:

- `stop()` keeps its current immediate-stop behavior. It does not send EOS and does not guarantee encoder tail-packet drain.
- `finalize(timeout:)` is the graceful shutdown path for reliable users.
- `stop()` and `finalize(timeout:)` are idempotent. Calling `stop()` after successful `finalize()` is a no-op beyond existing stop semantics.
- If `stop()` is called before `finalize()`, `finalize()` must not restart the pipeline and must return or throw according to the stopped terminal state.
- After `finalize(timeout:)` completes successfully, further iteration over the active reliable sequence must immediately return `nil`; no unconsumed encoder tail packet may remain hidden in appsink.

## Queue And AppSink Contract

Realtime mode remains unchanged:

```swift
appsink name=<sink> sync=false drop=true max-buffers=1 emit-signals=true
```

Reliable mode inserts a named queue after live source normalization and before the encoder:

```text
<live source> ! audioconvert ! audioresample ! <caps>
  ! queue name=<queue>
      leaky=<QueueLeaky.rawValue>
      max-size-buffers=<maxBuffers or 0>
      max-size-bytes=<maxBytes or 0>
      max-size-time=<maxTime nanoseconds or 0>
  ! <encoder>
  ! appsink name=<sink>
      drop=false
      sync=false
      emit-signals=true
      enable-last-sample=false
      wait-on-eos=true
      max-buffers=1
```

Rules:

- `nil` and zero bounds serialize to GStreamer's disabled-limit value `0`.
- The upstream queue is the public policy and budget boundary.
- The appsink is bounded to one sample so it cannot hide unbounded post-encoder backlog.
- Reliable mode does not set appsink `max-bytes`, `max-time`, or `buffer-list` in this phase.
- `enable-last-sample=false` avoids retaining an extra sample outside the reliable iterator.
- `wait-on-eos=true` ensures appsink cooperates with EOS drain while a reliable consumer is active.

`QueueLeaky` semantics are:

- `.none` (`leaky=0`): non-leaky, blocks upstream when full.
- `.upstream` (`leaky=1`): drops newest incoming buffers when full, keeping older queued data.
- `.downstream` (`leaky=2`): drops oldest queued buffers when full, keeping newest data.

## Element Type

Live reliable delivery wraps each payload:

```swift
public struct ReliablePacket<Payload: Sendable>: Sendable {
  public let payload: Payload
  public let pts: UInt64?
  public let duration: UInt64?
  public let priorDiscontinuity: Discontinuity?
}

public struct Discontinuity: Sendable {
  public enum Kind: Sendable {
    case formatChange
    case discont
    case gap
    case dropped
  }

  public let kind: Kind
  public let priorPTS: UInt64?
  public let priorDuration: UInt64?
  public let nextPTS: UInt64?
  public var duration: UInt64? { get }
  public let droppedCount: Int?
}
```

Timestamps are public `UInt64?` nanoseconds to match existing `Buffer.pts` and `Buffer.duration`. This RFC does not introduce a public `ClockTime` wrapper.

## Discontinuity Detection

The implementation must inspect both GStreamer buffer metadata and packet timing:

- `.formatChange`: current sample caps and previous sample caps are not equal according to `gst_caps_is_equal`.
- `.discont`: current buffer has `GST_BUFFER_FLAG_DISCONT`.
- `.gap`: current buffer has `GST_BUFFER_FLAG_GAP`.
- `.dropped`: `priorPTS + priorDuration < currentPTS` and no higher-precedence signal applies.

Caps string comparison is not acceptable for `.formatChange` detection because string ordering can produce false positives.

If multiple signals are observed for one packet, v1 surfaces one `priorDiscontinuity` using this precedence:

1. `.formatChange`
2. `.discont`
3. `.gap`
4. `.dropped`

`Discontinuity.duration` is the gap duration, derived from `nextPTS - (priorPTS + priorDuration)` only when `priorPTS`, `priorDuration`, and `nextPTS` are available and `nextPTS >= priorPTS + priorDuration`. Otherwise it is `nil`.

`droppedCount` is reserved for future inference. v1 must always return `nil` to avoid incorrect estimates for encoder-dependent packet durations.

## Implementation Notes

- Reuse `RFC-001` continuation/cancellation bridge strategy for pull-based iteration.
- Do not call blocking `gst_app_sink_pull_sample` from async context.
- Use `new-sample`/EOS callbacks and Bus ERROR observation to resume pending continuations.
- Add shim support for `gst_buffer_get_flags` and Swift helpers for GAP/DISCONT checks.
- Add a Bus EOS/ERROR timeout helper, public or internal, for `finalize(timeout:)`; implement it by consuming `Bus.messages(filter: [.eos, .error])` with timeout cancellation rather than blocking a Swift executor thread.
- Negative `Duration` validation must happen before nanosecond conversion. Prefer reusing or lifting the existing reliable-packet duration conversion pattern rather than duplicating unchecked conversions.
- Deterministic tests should use synthetic live pipelines or test hooks; required CI tests must not depend on physical microphone or webcam hardware.
- Codec-specific tests should skip only when the required encoder plugin is unavailable and should report the skipped plugin explicitly.

## Tests Required

- Static API tests verify no parallel public queue-policy enum is added.
- Builder validation rejects raw reliable mode, negative `maxTime`, and effectively unbounded reliable bounds.
- Pipeline string tests verify queue `leaky` and `max-size-*` mapping plus reliable appsink `max-buffers=1`.
- Synthetic live nominal flow yields packets with `priorDiscontinuity == nil`.
- Synthetic GAP, DISCONT, caps-change, and PTS-delta cases produce the expected `Discontinuity.Kind`.
- Caps-change tests use structured caps equality semantics, not string equality.
- Discontinuity duration tests verify gap duration, not prior-packet-plus-gap duration.
- `droppedCount` tests verify v1 returns `nil`.
- Slow-consumer tests cover `.downstream` and `.none` policies without asserting exact drop counts.
- `finalize(timeout:)` tests cover clean EOS, Bus ERROR, timeout, and sendEOS failure.
- `finalize(timeout:)` tests cover duplicate finalize calls, `stop()` before `finalize()`, `finalize()` before `stop()`, and iterator tail-drain coordination.
- Cancellation tests verify callback detachment and no leaked continuations.
- Realtime `packets()` and file/decode `AudioFileSource.reliablePackets()` behavior remain unchanged.

## Documentation Required

- `withReliableDelivery(...)` docs must describe wall-clock consequences of each `QueueLeaky` policy.
- `withReliableDelivery(...)` docs must explain why `.none` is the default and warn that slow consumers can cause xruns or device-level loss outside GStreamer queue observability.
- `reliablePackets()` docs for live sources must state the encoded-audio-only scope and the builder opt-in requirement.
- `finalize(timeout:)` docs must explain why archival live callers should prefer it over immediate `stop()`, and must define how `stop()` and `finalize()` interact.
- Documentation must state that raw reliable live buffers, VideoSource reliable delivery, fan-out, and recording convenience APIs are future work.
- Realtime monitoring examples must continue to prefer `packets()`.

## Migration Plan

1. Update this RFC to accepted GStreamer-aligned terminology and contracts.
2. Implement the encoded AudioSource reliable delivery PRD.
3. Keep realtime `packets()` and raw `buffers()` unchanged.
4. Add higher-level recording, VideoSource reliable delivery, raw reliable buffers, and tee/fan-out policies in later RFCs/PRDs.

## Resolved Decisions

- Live reliable delivery exists in v1 for encoded AudioSource pipelines only.
- Queue policy uses `QueueLeaky` directly with explicit queue bounds.
- Public unbounded reliable live configuration is rejected.
- Reliable live appsink is bounded to `max-buffers=1`.
- Reliable live packets use `ReliablePacket<Buffer>` and `Discontinuity`.
- `Discontinuity.duration` is gap duration: `nextPTS - (priorPTS + priorDuration)` when all values are available and non-underflowing.
- `droppedCount` is reserved for future inference and always `nil` in v1.
- Caps changes are detected with `gst_caps_is_equal`, not caps string equality.
- `reliablePackets()` throws a typed error when reliable delivery was not configured.
- Live finalization uses EOS send plus Bus EOS/ERROR wait, iterator drain-or-cancel coordination, and timeout before stop.
- `stop()` remains immediate; `finalize(timeout:)` is the reliable graceful shutdown path.
- Realtime `packets()` and raw `buffers()` defaults remain unchanged.
- No public VideoSource reliable API is added in this phase.

## Deferred Questions

- What exact public API should VideoSource reliable delivery use?
- Should tee/fan-out policies be configured per branch through a future branch builder?
- Should raw reliable live buffers use `ReliablePackets<ReliablePacket<AudioBuffer>>`, `ReliablePackets<ReliablePacket<Buffer>>`, or a separate API?
- Should a higher-level `record(to:for:)` API be layered on top of live reliable packets?
- Should appsink `buffer-list=true` be supported as a throughput optimization after v1?
- Should the QueueLeaky behavior fix, ADR-001 taxonomy work, RFC-002 PRD, and live reliable implementation be announced together in one release-note section?
