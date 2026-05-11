# RFC-001: Realtime vs Reliable Archival Encoded Packet Delivery

**Status:** Accepted
**Date:** 2026-05-08
**Accepted:** 2026-05-08
**Related work:** `GStreamerBridgeSafetyandReliabilityFixes`
**Decision owner:** TBD
**Scope:** Encoded packet delivery, audio/video packet stream semantics, backpressure

## Question

Should encoded packet APIs eventually gain a reliable archival delivery alternative separate from the current best-effort realtime streams?

## Current Behavior

The safety branch preserves the existing `AsyncStream` return type for encoded packet APIs and adds a bounded buffering policy.

Current semantics:

- Encoded packet streams are **best-effort realtime delivery**.
- Slow consumers may cause older packets to be dropped.
- The default queue is a small bounded newest-buffer policy, currently represented as `MediaStreamBackpressure.encodedPacketsNewest = 8`. The constant is `internal` and currently lives next to its consumer in `Sources/GStreamer/AudioSource.swift`; the empty namespace in `Sources/GStreamer/MediaStreamBackpressure.swift` is reserved for future stream-type defaults to migrate into.
- This is appropriate for low-latency realtime consumers but not for reliable recording or archival use.

## Problem

A user can naturally interpret an API named `packets()` as suitable for saving all encoded packets to disk or forwarding every packet to another system.

That interpretation conflicts with the new bounded realtime behavior:

- Dropping packets is acceptable for realtime monitoring.
- Dropping packets is unacceptable for recording, archival, upload, offline processing, or transcoding.
- A single API cannot honestly promise both low-latency best-effort delivery and reliable no-drop delivery.

## Goals

- Preserve the current low-latency realtime packet API.
- Avoid unbounded memory growth for slow consumers.
- Provide a future path for reliable packet delivery without changing the semantics of the existing `packets()` API.
- Make delivery semantics explicit in public docs and API names.

## Non-Goals

- Do not change the current safety branch.
- Do not make `packets()` reliable by silently removing bounded buffering.
- Do not promise archival delivery from an `AsyncStream` with a dropping buffering policy.
- Do not implement file muxing or full recording pipelines in this RFC unless a later RFC expands scope.

## User Scenarios

### Scenario A: Realtime speech recognition

The user wants low latency and can tolerate occasional packet loss.

Recommended semantic: best-effort realtime.

### Scenario B: Voice assistant monitoring

The user processes recent audio and discards stale packets if the consumer is slow.

Recommended semantic: best-effort realtime.

### Scenario C: Recording encoded audio

The user needs every packet, in order, until EOS.

Recommended semantic: reliable archival.

### Scenario D: Uploading encoded packets

The user needs delivery completeness and explicit backpressure or failure behavior.

Recommended semantic: reliable archival.

### Scenario E: Offline transcoding

The user processes finite input and must not lose data.

Recommended semantic: reliable archival.

## Options

### Option A: Keep only current `packets()`

```swift
func packets() -> AsyncStream<Buffer>
```

**Pros**

- No new API.
- Current branch remains simple.
- Good for realtime use.

**Cons**

- No reliable delivery path.
- Users may misuse `packets()` for recording.
- Docs must repeatedly warn about packet drops.

### Option B: Add an enum-based delivery mode

```swift
public enum PacketDeliveryMode: Sendable {
    case realtimeNewest(Int)
    case reliable
}

public func packets(delivery: PacketDeliveryMode) -> some AsyncSequence<Buffer>
```

**Pros**

- One conceptual API.
- Delivery semantics are explicit at call site.

**Cons**

- Return type design is tricky because realtime and reliable modes may use different sequence types.
- `some AsyncSequence` in public APIs may complicate documentation and source compatibility.
- Overloading existing `packets()` semantics may confuse users.

### Option C: Add a separate reliable API

```swift
public func reliablePackets() -> AudioSource.ReliablePackets
```

or:

```swift
public func archivalPackets() -> AudioSource.ArchivalPackets
```

**Pros**

- Clear naming.
- Avoids changing existing `packets()` semantics.
- Lets the reliable API be pull-based without disturbing current `AsyncStream` callers.
- Easier migration story.

**Cons**

- Adds new API surface.
- Requires users to choose between two APIs.
- Needs careful documentation.

### Option D: Add a recording/file-oriented API instead of packet iteration

```swift
public func record(to url: URL) async throws
```

or pipeline-builder equivalent.

**Pros**

- Best user experience for recording.
- GStreamer can handle muxing and file finalization directly.

**Cons**

- Larger feature scope.
- Not a general packet delivery primitive.
- May require additional file/muxer capabilities and platform handling.

## Recommendation

Keep the current `packets()` API as realtime best-effort.

For reliable delivery, prefer **Option C**: add a separate pull-based API with an explicit archival/reliable name.

Recommended naming:

```swift
public func reliablePackets() -> AudioSource.ReliablePackets
```

Alternative naming if the library wants to emphasize storage/recording semantics:

```swift
public func archivalPackets() -> AudioSource.ArchivalPackets
```

Recommended semantics:

- Does not drop packets in Swift.
- Pulls from GStreamer only when the consumer requests the next packet.
- May backpressure the pipeline (subject to source type — see *Reliability Boundary* below).
- Ends on EOS.
- Cancels cleanly.
- Documents that it is intended for recording, upload, archival, or offline processing, not lowest-latency monitoring.

Option D (a `record(to:)`-style file API) is **additive, not exclusive**: `reliablePackets()` is the underlying primitive, and a higher-level recording API can be built on top of it in a later RFC without re-litigating delivery semantics.

## Reliability Boundary

`reliablePackets()` removes Swift-level dropping but cannot eliminate physical and pipeline-level constraints. Callers must understand which source they are reading from:

### File-like / pull-driven sources

For finite or pull-driven sources (e.g. `URIDecodeSource` over a file, `appsrc` fed at the consumer's pace), backpressure propagates end-to-end:

```
appsink full → upstream queue full → demux/decode slows → file read slows
```

In this regime `reliablePackets()` delivers on its name: every packet, in order, until EOS, with bounded memory.

### Live / wall-clock-driven sources

For live sources such as `AudioSource.microphone()`, the producer is driven by hardware time and **cannot be backpressured**. If the consumer is slower than realtime, one of three things happens, and the choice belongs to the *upstream queue policy*, not to Swift:

1. **`leaky=downstream`** on the upstream `queue`: GStreamer drops packets before they reach `appsink`. `reliablePackets()` will silently observe gaps. This breaks the no-drop promise.
2. **`leaky=no` with bounded `max-size-*`**: `appsink` / upstream queue fills, downstream chain blocks the streaming thread, which manifests as audio xruns at the source.
3. **`leaky=no` with unbounded queue**: memory grows without bound until the process is killed.

None of these are acceptable archival behavior for an indefinitely-running microphone. Therefore:

- For the initial implementation, `reliablePackets()` is **only exposed on sources that can be backpressured end-to-end**. On `AudioSource.microphone()` and other live sources, the method either is not offered or is offered with documentation that explicitly names the upstream queue policy the caller is responsible for configuring.
- The doc comment on `reliablePackets()` MUST say, in plain language: *"Reliable delivery requires a source that can be backpressured. For live capture sources, configure upstream queue policy explicitly; otherwise prefer a finite-duration recording API."*
- The Migration Plan calls for `reliablePackets()` to land first on file/decode sources, with live-source semantics deferred to `RFC-002`.

### Naming consequence

Because the term "reliable" can over-promise on live sources, both `reliablePackets()` and `archivalPackets()` remain acceptable. The implementation chooses one; whichever is chosen, the doc comment must lead with the boundary above.

## Implementation Notes

The pull-based iterator must avoid two failure modes: blocking a cooperative thread, and leaking GStreamer resources on cancellation.

Recommended sketch:

- Bridge `appsink`'s `new-sample` signal (or `try_pull_sample` polled from a callback) into Swift via `withCheckedContinuation` / `withTaskCancellationHandler`. Do **not** call `gst_app_sink_pull_sample` directly from an `async` context — it is blocking and will pin a Swift Concurrency executor thread.
- On cancellation, detach the signal handler, drain any in-flight continuation, and let the `appsink` resume its normal callback path so the rest of the pipeline (including `Bus`) keeps draining.
- Treat `reliablePackets()` as a **single-consumer** sequence. Concurrent iteration from two tasks is undefined; the doc comment must say so. If multi-consumer is needed later, build a fan-out on top rather than retrofitting it into the iterator.
- `gst_app_sink_pull_sample` returns `nil` on EOS; the iterator translates that to a clean termination. Bus errors received during iteration translate to a thrown error (see *Resolved Decisions*).
- On `@MainActor` callers: pulling must hop off the main actor before doing any blocking work; the helper should be `nonisolated` and `Sendable` so it composes naturally with existing `for try await` sites.

## Proposed API Sketch

The reliable sequence is **throwing** (see *Resolved Decisions*) and **generic in element type** so that future video packet sources can adopt the same primitive without API churn. The audio entry point is a thin convenience over the generic primitive:

```swift
public struct ReliablePackets<Element: Sendable>: AsyncSequence, Sendable {
    public struct AsyncIterator: AsyncIteratorProtocol {
        public mutating func next() async throws -> Element?
    }

    public func makeAsyncIterator() -> AsyncIterator
}

extension AudioSource {
    public func reliablePackets() -> ReliablePackets<Buffer>
}
```

`AsyncSequence` carries the failure through its associated `Failure` type; there is no separate `AsyncThrowingSequence` protocol, only the throwing convenience type `AsyncThrowingStream` in the standard library, which is **not** what this API returns. `ReliablePackets` is a custom `AsyncSequence` whose iterator's `next()` is `async throws`.

## Delivery Semantics

| API | Delivery type | Backpressure | Drop behavior | Intended use |
|---|---|---|---|---|
| `packets()` | Realtime best-effort | Bounded Swift buffer | May drop older packets | Low latency |
| `reliablePackets()` | Reliable archival | Consumer-driven / pipeline backpressure | No Swift-level dropping | Recording, upload, offline |

## Interaction with GStreamer

A reliable API must avoid a detached producer that continuously pulls from `appsink` and queues into Swift memory; that pattern just relocates the dropping problem from `AsyncStream` policy into a hand-rolled queue.

The contract is: pull from `appsink` only when the consumer's `next()` is awaiting, so Swift memory stays bounded by design. Any further upstream buffering is an explicit property of the GStreamer pipeline (queue sizes, `appsink` `max-buffers`, `drop` flag) and is the source builder's responsibility, not the iterator's.

Concrete implementation guidance lives in *Implementation Notes* above.

## Tests Required

- Finite encoded source produces the expected number of packets with `reliablePackets()`.
- Slow consumer does not lose packets for finite test input.
- Packet order is preserved.
- EOS ends the sequence cleanly (no thrown error).
- Cancellation mid-iteration stops polling, releases the `appsink` signal handler, and does not leak GStreamer mini-objects or Swift continuations.
- Pipeline `GST_MESSAGE_ERROR` during iteration causes `next()` to throw rather than silently terminating; the thrown error is the same taxonomy used elsewhere in the bridge.
- Concurrent iteration from two tasks is either rejected at runtime or documented as undefined; whichever is chosen, a test pins the behavior.
- Realtime `packets()` remains bounded and documented as best-effort.
- Tests verify `packets()` and `reliablePackets()` have distinct semantics, including a side-by-side test where a slow consumer loses packets on `packets()` but not on `reliablePackets()` for the same finite input.

## Documentation Required

- `packets()` docs must state it is best-effort realtime.
- `reliablePackets()` docs must state it is for no-drop delivery and may backpressure.
- Examples should not use `packets()` for recording without an explicit caveat.
- Recording examples should use `reliablePackets()` or a file-oriented API.

## Migration Plan

1. Keep current `packets()` unchanged.
2. Land the generic `ReliablePackets<Element>` type and expose `reliablePackets()` on **file/decode-style sources first** (e.g. `URIDecodeSource`-based pipelines). Live-source exposure is deferred until the *Reliability Boundary* concerns are resolved by `RFC-002`.
3. Update README examples to choose API by use case, leading with the boundary caveat for live sources.
4. Add a convenience recording API (Option D) in a later RFC, layered on top of `reliablePackets()`.
5. If users continue to misuse `packets()` for archival, consider renaming or deprecating in a major release.

## Resolved Decisions

These started as open questions and are resolved as part of accepting this RFC.

- **Generic vs. audio-only.** The primitive is generic (`ReliablePackets<Element>`) so video packet sources can adopt it later without a parallel type. The first concrete entry point is `AudioSource.reliablePackets() -> ReliablePackets<Buffer>`.
- **Throwing.** `next()` is `async throws`. A silent short read on an archival API is a worse failure mode than a thrown error, because partial output without an error indication can corrupt recordings or uploads. Bus / pipeline errors observed during iteration surface through the thrown error; clean EOS surfaces as `nil`.
- **Backpressure configuration.** Not exposed as a knob in the first cut. The reliable API is consumer-driven by construction; whatever upstream queue policy is needed for live sources is a property of the *source builder*, not of `reliablePackets()`. Re-evaluate when the live-source RFC lands.
- **Recording API.** A file-oriented API is desirable but out of scope for this RFC; it will be built on top of `reliablePackets()` rather than instead of it.

## Deferred Questions

- Naming: keep `reliablePackets()` or switch to `archivalPackets()`. Both are acceptable; the doc comment carries the load either way. To be picked at implementation time.
- Whether `packets()` should grow a `packets(buffer:)` overload exposing the realtime queue depth (currently fixed at `MediaStreamBackpressure.encodedPacketsNewest = 8`). Defer until a real caller asks for it.
- Live-source exposure of `reliablePackets()` and the upstream queue-policy contract. See `RFC-002`.
