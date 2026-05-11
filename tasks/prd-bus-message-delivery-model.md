# PRD: Bus Message Delivery Model (ADR-002)

## Introduction/Overview

This PRD implements `ADR-002: Bus Message Delivery Model`. The feature adds a source-compatible, pull-based bus message API so callers can consume GStreamer bus messages without the Swift-side detached producer and unbounded `AsyncStream` buffer used by `Bus.messages(filter:)`.

The v1 implementation is intentionally close to the existing GStreamer C API behavior: `Bus.messageSequence(filter:)` destructively drains the underlying `GstBus` with C-side filtered pop semantics. It does not introduce fan-out, message replay, a dispatcher, or multi-observer ownership.

ADR-002 is accepted and pending implementation. This PRD resolves ADR-002's deferred v1 implementation decisions: default filter is existing `Bus.Filter.all`, polling uses `swift_gst_bus_timed_pop_filtered`, the poll timeout is 100 ms, and parsing remains non-public.

## Status

Last updated: 2026-05-11.

- PRD: draft for ADR-002 implementation.
- ADR: accepted, pending implementation.
- Implementation: not started by this PRD.
- Related work: `docs/ADRs/ADR-002-bus-message-delivery-model.md`.

## Goals

- Add `Bus.messageSequence(filter:)` as a pull-based `AsyncSequence` API alongside existing `Bus.messages(filter:)`.
- Remove Swift-side producer buffering from the new path: no `AsyncStream` and no detached producer draining ahead of consumer demand.
- Preserve source compatibility for `Bus.messages(filter:)`, `Bus.errors()`, `Bus.warnings()`, `Bus.stateChanges()`, and `Bus.waitForEOS()`.
- Keep bus ERROR messages as `BusMessage.error(message:debug:)` values rather than thrown errors.
- Deliver EOS as `BusMessage.eos` without automatically terminating the pull-based iterator.
- Align v1 filtering with C-side `gst_bus_timed_pop_filtered` semantics and document the destructive queue behavior.
- Cover the API with runtime tests, static surface checks, DocC, README examples, and CHANGELOG notes.

## Resolved ADR-002 v1 Decisions

- **Default filter:** `Bus.messageSequence(filter:)` defaults to existing `Bus.Filter.all`.
- **Meaning of `.all`:** `.all` is the broadest existing Swift `Bus.Filter` set for representable `BusMessage` cases. It is not `GST_MESSAGE_ANY`, and it is not equivalent to unfiltered `gst_bus_timed_pop`.
- **Filtering implementation:** v1 uses `swift_gst_bus_timed_pop_filtered` with the requested filter.
- **Polling interval:** v1 uses a 100 ms timed pop, matching the current `Bus.messages(filter:)` poll interval and ADR sketch.
- **Parsing:** reuse the existing message parsing logic without adding public parser API. If access control must change, use the narrowest non-public access level that works.
- **Fan-out:** bus fan-out, unfiltered retention, observer registries, and unified bus owners remain future work.

## User Stories

### US-001: Add Pull-Based Bus Message Sequence

**Description:** As a library user, I want `Bus.messageSequence(filter:)` so that I can consume bus messages on demand without a Swift-side producer draining ahead of me.

**Acceptance Criteria:**
- [ ] Add `public struct Bus.Messages: AsyncSequence, Sendable`.
- [ ] `Bus.Messages.Element` is `BusMessage`.
- [ ] Add nested `Bus.Messages.AsyncIterator: AsyncIteratorProtocol`.
- [ ] Add `public func messageSequence(filter: Filter = .all) -> Messages` on `Bus`.
- [ ] `Bus.messages(filter:)` remains public and still returns `AsyncStream<BusMessage>`.
- [ ] Typecheck passes.

### US-002: Implement Pull Iterator With C-Side Filtered Pop

**Description:** As an implementer, I need the new iterator to align with GStreamer filtered-pop behavior so that it behaves like a low-level destructive bus consumer.

**Acceptance Criteria:**
- [ ] `AsyncIterator.next()` polls with `swift_gst_bus_timed_pop_filtered`.
- [ ] The poll timeout is exactly `100_000_000` nanoseconds (100 ms).
- [ ] The iterator uses the caller-provided `filter.gstMessageType`.
- [ ] Each returned `GstMessage` is unreferenced exactly once after parsing.
- [ ] If parsing returns `nil`, iteration continues rather than terminating.
- [ ] The `messageSequence` implementation path does not construct `AsyncStream`.
- [ ] Typecheck passes.

### US-003: Preserve Error-As-Value and EOS Semantics

**Description:** As a library user, I want bus ERROR and EOS messages to follow the ADR-002 value semantics so that the iterator does not hide later bus control-plane messages.

**Acceptance Criteria:**
- [ ] `GST_MESSAGE_ERROR` is returned as `BusMessage.error(message:debug:)`.
- [ ] `AsyncIterator.next()` is not throwing.
- [ ] `GST_MESSAGE_EOS` is returned as `BusMessage.eos`.
- [ ] Receiving `.eos` does not automatically make later `next()` calls return `nil`.
- [ ] Documentation tells callers to `break` after EOS when EOS should end their loop.
- [ ] Typecheck passes.

### US-004: Handle Cancellation Predictably

**Description:** As an implementer, I need cancelled iteration to stop polling within a bounded time so that tasks can shut down cleanly.

**Acceptance Criteria:**
- [ ] `next()` checks `Task.isCancelled` between timed pop attempts.
- [ ] After cancellation, `next()` returns `nil`.
- [ ] Cancellation latency is bounded by one 100 ms poll interval plus scheduling delay.
- [ ] Tests use a concrete upper bound of 500 ms unless the existing test harness requires a different bound.
- [ ] No continuation or detached producer exists on the `messageSequence` path.
- [ ] Typecheck passes.

### US-005: Reuse Message Parsing Without Public Parser API

**Description:** As an implementer, I need both `messages(filter:)` and `messageSequence(filter:)` to decode `GstMessage` values consistently without exposing parser internals as public API.

**Acceptance Criteria:**
- [ ] The new sequence reuses the same parsing logic as `Bus.messages(filter:)`.
- [ ] No public `parseMessage` API is added.
- [ ] If `parseMessage(_:)` access changes, it remains non-public.
- [ ] Existing parsed cases such as `.error`, `.warning`, `.stateChanged`, `.latency`, and `.clockLost` keep their current meanings.
- [ ] Existing `BusMessageTests` continue to pass.
- [ ] Typecheck passes.

### US-006: Preserve Existing Bus APIs

**Description:** As an existing caller, I need current bus stream and convenience APIs to keep compiling and behaving as before.

**Acceptance Criteria:**
- [ ] `Bus.messages(filter:)` signature remains `public func messages(filter: Filter = [.error, .eos, .stateChanged]) -> AsyncStream<BusMessage>`.
- [ ] `Bus.messages(filter:)` still finishes after delivering EOS.
- [ ] `Bus.errors()` signature and return type remain unchanged.
- [ ] `Bus.warnings()` signature and return type remain unchanged.
- [ ] `Bus.stateChanges()` signature and return type remain unchanged.
- [ ] `Bus.waitForEOS()` behavior remains unchanged.
- [ ] Existing tests for stream-based bus APIs continue to pass.

### US-007: Document C-Side Filter Semantics and `.all` Limits

**Description:** As a library user, I need docs to explain that `messageSequence(filter:)` is a destructive bus consumer and that `.all` is not raw unfiltered `GstBus` access.

**Acceptance Criteria:**
- [ ] DocC for `messageSequence(filter:)` states that C-side filtered pop can discard messages outside the requested filter while searching.
- [ ] DocC states that `.all` means the broadest Swift-modeled `Bus.Filter` set, not `GST_MESSAGE_ANY`.
- [ ] DocC states that multiple bus consumers on the same `Bus` can compete for messages.
- [ ] DocC explains EOS non-termination and ERROR-as-value semantics.
- [ ] DocC states that callers should use one bus drainer at a time unless a future fan-out API owns the bus.
- [ ] DocC generation succeeds if tooling is available.

### US-008: Add README and CHANGELOG Guidance

**Description:** As a downstream caller, I need release notes and examples that show when to use the new pull-based API and what behavior changes to expect.

**Acceptance Criteria:**
- [ ] README includes an example using `for await message in pipeline.bus.messageSequence(...)`.
- [ ] README example breaks explicitly after `.eos` or `.error`.
- [ ] README or adjacent docs explain when to choose `messageSequence(filter:)` instead of `messages(filter:)`.
- [ ] CHANGELOG adds an entry for `Bus.messageSequence(filter:)`.
- [ ] CHANGELOG states that existing `Bus.messages(filter:)` and convenience APIs are unchanged.
- [ ] CHANGELOG notes that `messageSequence(filter:)` defaults to `.all`, which can expose more Swift-modeled messages than `messages()` default.

### US-009: Add Runtime Tests

**Description:** As an implementer, I need integration tests that prove the pull-based API receives key bus messages and handles cancellation safely.

**Acceptance Criteria:**
- [ ] A finite pipeline test receives `.eos` through `messageSequence(filter: [.eos, .error])`.
- [ ] A deterministic invalid pipeline or injected error test receives `.error` as a value.
- [ ] A state-change test receives at least one `.stateChanged` message.
- [ ] An EOS non-termination test receives `.eos`, requests another `next()` in a cancellable task, cancels it, and observes `nil` within the timeout.
- [ ] A cancellation-before-message test cancels an active iterator and observes `nil` within the timeout.
- [ ] Tests run under the suite's existing time limits.

### US-010: Add Static API Safety Tests

**Description:** As a maintainer, I need static checks that pin the public API and prevent accidentally reintroducing stream buffering into the pull path.

**Acceptance Criteria:**
- [ ] Static tests verify `public struct Messages: AsyncSequence` exists under `Bus`.
- [ ] Static tests verify `Messages` conforms to `Sendable`.
- [ ] Static tests verify `public func messageSequence(filter: Filter = .all) -> Messages`.
- [ ] Static tests verify the `messageSequence` implementation path does not construct `AsyncStream`.
- [ ] Static tests verify no new public parser API is added.
- [ ] Static tests verify `Bus.messages(filter:)` default and return type remain unchanged.

## Functional Requirements

- **FR-1:** The system must expose `Bus.Messages` as a public nested `AsyncSequence` whose element is `BusMessage`.
- **FR-2:** The system must expose `Bus.messageSequence(filter: Filter = .all) -> Bus.Messages`.
- **FR-3:** `Bus.Messages.AsyncIterator.next()` must be `async -> BusMessage?`, not throwing.
- **FR-4:** `messageSequence(filter:)` must not use `AsyncStream` or a detached Swift producer.
- **FR-5:** Each `next()` call must poll the underlying `GstBus` only on consumer demand.
- **FR-6:** v1 must use `swift_gst_bus_timed_pop_filtered` with a 100 ms timeout.
- **FR-7:** Returned C `GstMessage` objects must be unreferenced exactly once.
- **FR-8:** `.error` bus messages must remain values.
- **FR-9:** `.eos` must be delivered as a value and must not automatically terminate the sequence.
- **FR-10:** Cancellation must cause `next()` to return `nil` after at most one poll interval plus scheduling delay.
- **FR-11:** The default `.all` filter must be documented as Swift-modeled `Bus.Filter.all`, not raw unfiltered `GstBus` access.
- **FR-12:** `Bus.messages(filter:)`, `Bus.errors()`, `Bus.warnings()`, `Bus.stateChanges()`, and `Bus.waitForEOS()` must remain source compatible and behavior compatible.
- **FR-13:** The implementation must not add `.controlPlaneCritical`, `.controlPlane`, or any other new public filter convenience in this PRD.
- **FR-14:** The implementation must not add fan-out, replay, dispatcher, or observer-registry semantics.

## Non-Goals (Out of Scope)

- **NG-1:** No fan-out dispatcher, unified bus owner, observer registry, message replay, or multi-subscriber delivery.
- **NG-2:** No rewrite of `Bus.errors()`, `Bus.warnings()`, `Bus.stateChanges()`, or `Bus.waitForEOS()`.
- **NG-3:** No deprecation or replacement of `Bus.messages(filter:)`.
- **NG-4:** No bounded dropping policy for bus messages.
- **NG-5:** No GLib main-loop requirement.
- **NG-6:** No public parser API.
- **NG-7:** No new named control-plane filter constant.
- **NG-8:** No promise to preserve messages outside the requested filter when C-side filtered pop is used.
- **NG-9:** No claim that `.all` is equivalent to `GST_MESSAGE_ANY` or unfiltered `gst_bus_timed_pop`.

## Design Considerations

- **C API alignment:** `messageSequence(filter:)` is a low-level destructive consumer, like GStreamer bus pop APIs. It is not a Swift pub/sub abstraction.
- **Default behavior:** `.all` is chosen for the new pull API because it is the broadest existing Swift-modeled filter set. It can expose more messages than `messages()` default.
- **Source compatibility:** `messages()` keeps its existing default of `[.error, .eos, .stateChanged]` and keeps finishing after EOS.
- **Single-drainer guidance:** Documentation should recommend one active bus drainer per `Bus` unless a future fan-out API owns the bus.
- **Future direction:** If callers need multi-observer delivery or stronger retention semantics, a later design should consider unfiltered pop plus Swift-side filtering and fan-out.

## Technical Considerations

- Primary source changes are expected in `Sources/GStreamer/Bus.swift`.
- Static API surface checks are expected in `Tests/SwiftGStreamerTests/APISafetyStaticTests.swift`.
- Runtime tests are expected in a new or existing bus-focused test file under `Tests/SwiftGStreamerTests/`.
- The iterator should be reviewed under Swift 6 concurrency rules. If `@concurrent` is needed to match existing sequence patterns, use the same style as other pull-based iterators in the package.
- `parseMessage(_:)` currently lives inside `Bus`. Reuse it without making it public.
- C-side filtered pop may discard non-matching messages while searching. This must be treated as intended v1 behavior, not a test failure.
- Verification commands:
  - `swift build`
  - `swift test --filter BusMessage`
  - `swift test`
  - `swift package generate-documentation --target GStreamer` if DocC tooling is available
- If local GStreamer system dependencies or DocC tooling are unavailable, report skipped verification with the exact reason.

## Success Metrics

- Public API checks confirm `Bus.messageSequence(filter: .all)` and `Bus.Messages` are present.
- Runtime tests prove EOS, ERROR-as-value, state changes, EOS non-termination, and cancellation behavior.
- Static tests prove the new pull path does not use `AsyncStream`.
- Existing `Bus.messages()` tests continue to pass without source changes.
- Documentation clearly distinguishes `messageSequence(filter:)` from `messages(filter:)`.
- `swift build` and relevant bus tests pass in an environment with required GStreamer dependencies.

## Open Questions

- Should a future API provide fan-out or unified bus ownership for multiple observers?
- Should a future API expose unfiltered raw `GstMessage` access or `GST_MESSAGE_ANY` semantics?
- Should a future named filter set such as `.controlPlane` be introduced, and which messages should it include?
- Should `Bus.messages(filter:)` eventually be deprecated in a major release after `messageSequence(filter:)` adoption stabilizes?
