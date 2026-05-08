# ADR-002: Bus Message Delivery Model

**Status:** Proposed
**Date:** 2026-05-08
**Related work:** `GStreamerBridgeSafetyandReliabilityFixes`
**Decision owner:** TBD
**Scope:** `Bus.messages`, bus control-plane events, AsyncSequence design

## Decision Needed

Should bus messages later migrate to a pull-based sequence to avoid control-plane buffering ambiguity?

## Current Behavior

`Bus.messages(filter:)` returns `AsyncStream<BusMessage>` and internally uses a detached task to poll GStreamer bus messages.

The safety branch intentionally does **not** introduce a dropping bounded policy for bus messages, because bus messages are control-plane events. Errors, EOS, and state changes should not be silently dropped by a realtime media buffering policy.

## Problem

`AsyncStream` has buffering semantics that are easy to misunderstand. For media frames, bounded dropping can be acceptable. For bus messages, dropping can lose critical control-plane information such as:

- `.error`
- `.eos`
- `.stateChanged`
- `.clockLost`
- `.latency`

Keeping the current `AsyncStream` avoids source-breaking return type changes, but it leaves delivery semantics less precise than a pull-based sequence.

## Goals

- Avoid silent loss of critical bus messages.
- Preserve source compatibility in the current release.
- Provide a future API that has clearer delivery/backpressure semantics.
- Keep current convenience APIs usable.

## Non-Goals

- Do not change the current safety branch.
- Do not add a dropping bounded policy to `Bus.messages`.
- Do not replace `Bus.messages()` immediately.
- Do not require a GLib main loop as part of this decision.

## Options

### Option A: Keep current `Bus.messages()` only

```swift
public func messages(filter: Filter = [.error, .eos, .stateChanged]) -> AsyncStream<BusMessage>
```

**Pros**

- No public API change.
- Existing users unaffected.
- Current tests remain valid.

**Cons**

- Buffering semantics remain ambiguous.
- Detached producer can still get ahead of slow consumers.
- Hard to claim reliable control-plane delivery.

### Option B: Add bounded dropping to `Bus.messages()`

```swift
AsyncStream(bufferingPolicy: .bufferingNewest(64)) { ... }
```

**Pros**

- Bounds memory.
- Easy implementation.

**Cons**

- Can drop critical control-plane events.
- Requires complex prioritization to avoid losing `.error` or `.eos`.
- Semantics are dangerous for a bus.

This option should be rejected for default bus delivery.

### Option C: Replace `messages()` with pull-based sequence

```swift
public func messages(filter: Filter = ...) -> Bus.Messages
```

**Pros**

- Cleanest semantics.
- Consumer pulls one event at a time.
- Avoids Swift-side buffering ambiguity.

**Cons**

- Source-breaking return type change.
- Existing callers may need code updates.
- Larger migration burden.

### Option D: Add a new pull-based API in parallel

```swift
public func messageSequence(filter: Filter = [.error, .eos, .stateChanged]) -> Bus.Messages
```

**Pros**

- Source-compatible.
- Lets users opt into clearer semantics.
- Allows deprecation of old API later if desired.
- Aligns with pull-based APIs such as `AppSink.Frames`.

**Cons**

- Adds API surface.
- Two bus APIs must be documented.
- Naming must be chosen carefully.

## Recommendation

Choose **Option D**.

Keep existing `Bus.messages()` for source compatibility. Add a new pull-based bus sequence API in a future release.

Recommended API name:

```swift
public func messageSequence(filter: Filter = [.error, .eos, .stateChanged]) -> Bus.Messages
```

Alternative names:

```swift
public func messagesPulling(filter: Filter = ...) -> Bus.Messages
public func events(filter: Filter = ...) -> Bus.Messages
```

`messageSequence` is the clearest because it avoids overloading the existing `messages()` name.

## Proposed API Sketch

```swift
extension Bus {
    public struct Messages: AsyncSequence {
        public typealias Element = BusMessage

        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async -> BusMessage?
        }

        public func makeAsyncIterator() -> AsyncIterator
    }

    public func messageSequence(
        filter: Filter = [.error, .eos, .stateChanged]
    ) -> Messages
}
```

Possible iterator behavior:

```swift
public mutating func next() async -> BusMessage? {
    while !Task.isCancelled {
        if let msg = swift_gst_bus_timed_pop_filtered(...) {
            defer { swift_gst_message_unref(msg) }
            if let parsed = bus.parseMessage(msg) {
                return parsed
            }
        }

        await Task.yield()
    }

    return nil
}
```

## Delivery Semantics

The new pull-based sequence should document:

- It does not use a Swift `AsyncStream` producer buffer.
- It polls the GStreamer bus when the consumer requests `next()`.
- It stops on cancellation.
- It may still be affected by GStreamer bus behavior and message filters.
- It should not claim to preserve messages that GStreamer itself discards or expires.

## Compatibility Plan

1. Keep `Bus.messages()` unchanged.
2. Add `Bus.messageSequence()`.
3. Update docs to recommend `messageSequence()` for control-plane correctness.
4. Keep convenience APIs such as `errors()`, `warnings()`, and `stateChanges()` initially.
5. Later decide whether convenience APIs should be rewritten on top of `messageSequence()`.
6. Consider deprecating `messages()` only in a future major release if needed.

## Tests Required

- Pull-based sequence receives EOS from a finite pipeline.
- Pull-based sequence receives deterministic error from an invalid pipeline.
- Pull-based sequence receives state changes.
- Cancellation stops polling.
- No Swift `AsyncStream` buffering is used in the pull-based path.
- Existing `Bus.messages()` tests continue to pass.
- Convenience APIs remain source-compatible.

## Consequences

### Positive

- Clearer bus delivery semantics.
- No source-breaking change in the short term.
- Better alignment with pull-based media sequence design.

### Negative

- More API surface.
- Users need guidance on which bus API to use.
- Existing `Bus.messages()` ambiguity remains until users migrate.

## Open Questions

- Should `messageSequence()` be the preferred name?
- Should the sequence be throwing if bus `.error` is received, or should errors remain values?
- Should convenience APIs eventually return pull-based sequences too?
- Should the old `messages()` API be deprecated in a major release?
