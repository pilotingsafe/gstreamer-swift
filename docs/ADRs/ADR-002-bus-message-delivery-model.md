# ADR-002: Bus Message Delivery Model

**Status:** Accepted, Implemented
**Date:** 2026-05-08
**Accepted:** 2026-05-11
**Implemented:** 2026-05-11
**Related work:** `GStreamerBridgeSafetyandReliabilityFixes`
**Decision owner:** TBD
**Scope:** `Bus.messages`, bus control-plane events, AsyncSequence design

## Decision Needed

Should bus messages gain a pull-based sequence API to make delivery and backpressure semantics clearer than the current stream-based convenience path?

## Current Behavior

`Bus.messages(filter:)` returns `AsyncStream<BusMessage>` and internally uses a detached task to poll GStreamer bus messages. The current implementation polls with `swift_gst_bus_timed_pop_filtered`, delivers parsed messages through the stream continuation, and finishes the stream after EOS or cancellation.

The safety branch intentionally does **not** introduce a dropping bounded policy for bus messages, because bus messages are control-plane events. Errors, EOS, state changes, warnings, clock, and latency notifications may matter when callers choose to observe them, and should not be silently dropped by a realtime media buffering policy.

## Problem

The current `AsyncStream { ... }` initializer uses Swift's default unbounded buffering policy. That means the Swift stream buffering policy does **not** silently drop yielded bus messages by default.

The real risks are different:

- The detached producer can get ahead of a slow consumer, causing Swift-side buffering to grow without an explicit bound.
- The detached producer keeps draining the underlying `GstBus` even when no caller is currently awaiting `next()`, which can steal messages from other potential bus consumers.
- Cancellation is only observed between polling iterations, so worst-case cancellation latency is bounded by the active pop timeout plus scheduling delay.

Keeping the current `AsyncStream` avoids source-breaking return type changes, but it leaves backpressure and ownership semantics less precise than a pull-based sequence.

There is a separate filter semantics issue. `GstBus` itself can be drained without a C-side filter via `gst_bus_pop` / `gst_bus_timed_pop`. However, an implementation that chooses `gst_bus_timed_pop_filtered` trades simplicity for a sharper behavior: GStreamer discards messages that do not match the mask while searching for a matching message. A pull-based Swift sequence can remove the Swift-side producer buffer, but it does not by itself change that filtered-pop behavior.

## Goals

- Avoid introducing a Swift-side dropping policy for bus control-plane messages.
- Preserve source compatibility in the current release.
- Provide a future pull-based API (`Bus.messageSequence(filter:)`) with clearer backpressure and ownership semantics than the default `AsyncStream` path alone.
- Document filter and single-consumer semantics accurately.
- Keep current convenience APIs usable.

## Non-Goals

- Do not change the current safety branch.
- Do not add a dropping bounded policy to `Bus.messages`.
- Do not replace `Bus.messages()` immediately.
- Do not require a GLib main loop as part of this decision.
- Do not fix existing multi-consumer bus competition in this ADR.
- Do not add or standardize a new public filter convenience such as `.controlPlaneCritical` in this ADR.

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

- Backpressure semantics remain ambiguous.
- Detached producer can still get ahead of slow consumers.
- Detached producer drains the bus independently of consumer demand.
- Hard to claim precise control-plane delivery semantics.

### Option B: Add bounded dropping to `Bus.messages()`

```swift
AsyncStream(bufferingPolicy: .bufferingNewest(64)) { ... }
```

**Pros**

- Bounds memory.
- Easy implementation.

**Cons**

- Can drop bus events callers may rely on.
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
public func messageSequence(filter: Filter = ...) -> Bus.Messages
```

**Pros**

- Source-compatible.
- Lets users opt into clearer semantics.
- Allows deprecation of old API later if desired.
- Aligns with pull-based APIs such as `AppSink.Frames`.

**Cons**

- Adds API surface.
- Two bus APIs must be documented.
- Naming and default filter semantics must be chosen carefully.

## Recommendation

Choose **Option D**.

Keep existing `Bus.messages()` for source compatibility. Add a new pull-based bus sequence API in a future implementation (proposed as `Bus.messageSequence(filter:)` -> `Bus.Messages`).

Recommended API name:

```swift
public func messageSequence(filter: Filter = ...) -> Bus.Messages
```

Alternative names:

```swift
public func messagesPulling(filter: Filter = ...) -> Bus.Messages
public func events(filter: Filter = ...) -> Bus.Messages
```

`messageSequence` is the clearest because it avoids overloading the existing `messages()` name.

This ADR does not decide a new named default filter set. The default filter for `messageSequence(filter:)`, and whether to introduce any public convenience such as `.controlPlaneCritical`, should be decided in the implementation PR or a follow-up ADR.

## Decision

**Accepted and implemented.**

The package adopts **Option D**: keep `Bus.messages(filter:)` returning `AsyncStream<BusMessage>` for source compatibility, and add a parallel pull-based `Bus.messageSequence(filter:)` returning `Bus.Messages`.

Locked-in behavior for `Bus.messageSequence(filter:)` / `Bus.Messages`:

- **No Swift `AsyncStream` producer buffer.** The pull-based path should not use a detached Swift producer that drains the bus ahead of consumer demand.
- **Errors remain values.** Bus ERROR posts continue to surface as `BusMessage.error(message:debug:)` rather than throwing from `AsyncIteratorProtocol.next()`.
- **No automatic termination on `.eos`.** Unlike `Bus.messages(filter:)`, which finishes the `AsyncStream` after delivering EOS, the pull-based iterator should keep polling until the consuming task is cancelled or the caller breaks out of iteration.
- **Convenience APIs unchanged by this ADR.** `Bus.errors()`, `Bus.warnings()`, and `Bus.stateChanges()` remain implemented on top of `Bus.messages(filter:)` unless a later change explicitly rewrites them.

Deferred by this ADR:

- The exact default filter for `messageSequence(filter:)`.
- Whether to introduce a named public filter set.
- Whether the implementation should use C-side filtered pop or unfiltered pop plus Swift-side filtering.
- Whether existing convenience APIs should be rewritten around a single bus owner or fan-out dispatcher.

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
        filter: Filter = ...
    ) -> Messages
}
```

One possible iterator implementation is to poll with `swift_gst_bus_timed_pop_filtered` when the consumer calls `next()`:

```swift
public mutating func next() async -> BusMessage? {
    while !Task.isCancelled {
        if let msg = swift_gst_bus_timed_pop_filtered(
            bus._bus,
            100_000_000,
            filter.gstMessageType
        ) {
            defer { swift_gst_message_unref(msg) }
            if let parsed = bus.parseMessage(msg) {
                return parsed
            }
            continue
        }
        await Task.yield()
    }
    return nil
}
```

This is not the only viable implementation. If stronger retention or fan-out semantics are needed, the implementation should consider unfiltered `gst_bus_timed_pop` plus Swift-side filtering and distribution.

## Delivery Semantics

The new pull-based sequence should document:

- It does not use a Swift `AsyncStream` producer buffer.
- It polls the GStreamer bus when the consumer requests `next()`.
- It stops on cancellation; if timed polling is used, worst-case exit latency is bounded by the timed-pop interval plus scheduling delay.
- A `Bus` should be treated as having a single draining consumer unless a future fan-out mechanism owns the bus.
- Multiple concurrent draining consumers compete for the same underlying `GstBus`.
- Filter behavior depends on implementation choice: C-side filtered pop discards non-matching messages, while unfiltered pop plus Swift-side filtering can support stronger retention and fan-out semantics at higher complexity.
- It may still be affected by GStreamer bus behavior and message filters.
- It should not claim to preserve messages that GStreamer itself discards or expires.

Known existing behavior:

- `Bus.messages(filter:)`, `Bus.errors()`, `Bus.warnings()`, and `Bus.stateChanges()` each create their own draining path.
- Concurrently using those APIs on the same `Bus` can route messages to whichever consumer pops them first.
- This ADR records that limitation but does not fix it.

## Compatibility Plan

1. Keep `Bus.messages()` unchanged, including its current default filter.
2. Add `Bus.messageSequence()` in a future implementation.
3. Update docs to recommend `messageSequence()` when callers need pull-based ownership and clearer backpressure semantics.
4. Keep convenience APIs such as `errors()`, `warnings()`, and `stateChanges()` initially.
5. If `messageSequence(filter:)` gets a different default filter than `messages(filter:)`, document that migration can expose different message sets.
6. Later decide whether convenience APIs should be rewritten on top of a single bus owner, fan-out dispatcher, or `messageSequence()`.
7. Consider deprecating `messages()` only in a future major release if needed.

## Tests Required

- Pull-based sequence receives EOS from a finite pipeline.
- Pull-based sequence receives deterministic error from an invalid pipeline.
- Pull-based sequence receives state changes.
- Cancellation stops polling.
- No Swift `AsyncStream` buffering is used in the pull-based path.
- Existing `Bus.messages()` tests continue to pass.
- Convenience APIs remain source-compatible.
- If the implementation uses C-side filtered pop, tests or documentation must cover that filter choice and its consequences.

## Consequences

### Positive

- Clearer bus delivery and backpressure semantics.
- No source-breaking change in the short term.
- Better alignment with pull-based media sequence design.
- More honest documentation of filter and consumer ownership behavior.

### Negative

- More API surface.
- Users need guidance on which bus API to use.
- Existing `Bus.messages()` ambiguity remains until users migrate.
- Existing multi-consumer bus competition remains until a separate fan-out or bus-owner design is implemented.
- Default filter semantics remain a separate decision for implementation.

## Resolved Questions

- **ADR status.** Accepted and implemented.
- **Preferred public name.** Use `Bus.messageSequence(filter:)` (parallel to `Bus.messages(filter:)` without overloading the return type).
- **Throwing vs values for `.error`.** Keep **values** (`BusMessage.error(message:debug:)`); throwing would prematurely exit iteration and hide subsequent control-plane messages.
- **Automatic EOS termination for the new API.** **No** - the iterator does not stop solely because EOS was observed; callers opt out with `break` or by cancelling the task.
- **Named critical filter set.** Do not decide or add one in this ADR.

## Deferred Questions

- The exact default filter for `Bus.messageSequence(filter:)`.
- Whether a future named filter set is useful, and which messages it should include.
- Whether the implementation should use `gst_bus_timed_pop_filtered` or unfiltered `gst_bus_timed_pop` plus Swift-side filtering.
- Whether to add a fan-out dispatcher or unified bus owner to support multiple observers without competing drains.
- Whether `Bus.errors()`, `Bus.warnings()`, and `Bus.stateChanges()` should be reimplemented to avoid nested detached tasks and competing bus consumers.
- Whether `Bus.messages(filter:)` should be deprecated in a future major release once adoption guidance stabilizes.
- Whether to add an event-driven delivery path (for example using `gst_bus_set_sync_handler`) as a future option that avoids timed polling while still **not** requiring a GLib main loop.
