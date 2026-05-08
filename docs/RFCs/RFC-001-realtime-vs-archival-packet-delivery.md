# RFC-001: Realtime vs Reliable Archival Encoded Packet Delivery

**Status:** Proposed
**Date:** 2026-05-08
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
- The default queue is a small bounded newest-buffer policy, currently represented as `MediaStreamBackpressure.encodedPacketsNewest = 8`.
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
- May backpressure the pipeline.
- Ends on EOS.
- Cancels cleanly.
- Documents that it is intended for recording, upload, archival, or offline processing, not lowest-latency monitoring.

## Proposed API Sketch

```swift
extension AudioSource {
    public struct ReliablePackets: AsyncSequence {
        public typealias Element = Buffer

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> Buffer?
        }

        public func makeAsyncIterator() -> AsyncIterator
    }

    public func reliablePackets() -> ReliablePackets
}
```

If throwing is not needed:

```swift
public mutating func next() async -> Buffer?
```

If bus errors or pipeline errors should terminate the sequence with failure, use `AsyncThrowingSequence`-style behavior.

## Delivery Semantics

| API | Delivery type | Backpressure | Drop behavior | Intended use |
|---|---|---|---|---|
| `packets()` | Realtime best-effort | Bounded Swift buffer | May drop older packets | Low latency |
| `reliablePackets()` | Reliable archival | Consumer-driven / pipeline backpressure | No Swift-level dropping | Recording, upload, offline |

## Interaction with GStreamer

A reliable API should avoid a detached producer that continuously pulls from `appsink` and queues into Swift memory.

Instead, it should prefer a pull-based iterator:

```swift
public mutating func next() async -> Buffer? {
    // wait/poll appsink
    // return exactly one packet
}
```

This keeps Swift memory bounded by design. Any upstream buffering should be explicit through GStreamer/appsink settings.

## Tests Required

- Finite encoded source produces the expected number of packets with `reliablePackets()`.
- Slow consumer does not lose packets for finite test input.
- Packet order is preserved.
- EOS ends the sequence.
- Cancellation stops polling.
- Realtime `packets()` remains bounded and documented as best-effort.
- Tests verify `packets()` and `reliablePackets()` have distinct semantics.

## Documentation Required

- `packets()` docs must state it is best-effort realtime.
- `reliablePackets()` docs must state it is for no-drop delivery and may backpressure.
- Examples should not use `packets()` for recording without an explicit caveat.
- Recording examples should use `reliablePackets()` or a file-oriented API.

## Migration Plan

1. Keep current `packets()` unchanged.
2. Add `reliablePackets()` as a new API.
3. Update README examples to choose API by use case.
4. Optionally add a convenience recording API in a later RFC.
5. If users continue to misuse `packets()` for archival, consider renaming or deprecating in a major release.

## Open Questions

- Should the reliable API be audio-only first, or generic for future video packets?
- Should reliable packet delivery be throwing?
- Should reliable delivery expose backpressure configuration?
- Should the library eventually provide a file recording API instead of requiring users to consume packets manually?
