# PRD: Bus Dispatcher

## Introduction/Overview

The current bus APIs intentionally preserve GStreamer's destructive bus queue
model. `Bus.messageSequence(filter:)`, `Bus.messages(filter:)`, `errors()`,
`warnings()`, `stateChanges()`, `waitForEOSOrError()`, and other convenience
APIs that wait on the bus can all compete for the same underlying `GstBus`
queue. This behavior is documented and is not a correctness bug in the current
wrapper.

This feature adds an explicit Swift-side bus owner, `BusDispatcher`, for
applications that need multiple observers without competing destructive bus
drains. A dispatcher drains the underlying `GstBus` through one internal
watch-backed path, parses each modeled message once into `BusMessage`, and fans
out Swift values to derived observers such as messages, errors, warnings, state
changes, and EOS/error waiters.

The dispatcher is the recommended multi-observer bus API. Existing direct `Bus`
APIs remain source-compatible low-level escape hatches; callers that bypass the
dispatcher can still intentionally create competing bus consumers.

## Goals

- Add an explicit public `BusDispatcher` owner for Swift-side bus fan-out.
- Make the recommended multi-observer path use one internal `GstBus` drain.
- Preserve current direct `Bus` API source compatibility.
- Define public signatures, sequence element types, lifecycle, terminal,
  cancellation, buffering, and late-subscriber semantics before implementation.
- Keep GStreamer ownership and borrowed-message lifetime rules explicit.
- Add runtime and static tests proving derived observers do not steal messages
  from each other and that dispatcher queues remain bounded.

## User Stories

### US-001: Create One Active Bus Dispatcher

**Description:** As a library user, I want to obtain one dispatcher from a bus so
that multi-observer code has a clear bus owner.

**Acceptance Criteria:**
- [ ] Add `public final class BusDispatcher: @unchecked Sendable` with no public
  initializer.
- [ ] Add `public func dispatcher() -> BusDispatcher` on `Bus`.
- [ ] Concurrent calls to `Bus.dispatcher()` for the same `Bus` return the same
  active open dispatcher instance.
- [ ] A dispatcher that has reached EOS, ERROR, or `close()` is no longer the
  active dispatcher for that `Bus`.
- [ ] After close or terminal state, a later `Bus.dispatcher()` call can return a
  fresh active dispatcher.
- [ ] Static API checks verify the public type, factory method, and absence of a
  public initializer.
- [ ] Typecheck passes under Swift 6.3.1.

### US-002: Expose Derived Observer Sequences

**Description:** As a library user, I want messages, errors, warnings, and state
changes to come from the dispatcher so that observers do not create independent
bus drainers.

**Acceptance Criteria:**
- [ ] Add `public func messages(filter: Bus.Filter = .all) -> BusDispatcher.Messages`,
  where `Messages.Element == BusMessage`.
- [ ] Add `public func errors() -> BusDispatcher.Errors`, where
  `Errors.Element == (message: String, debug: String?)`.
- [ ] Add `public func warnings() -> BusDispatcher.Warnings`, where
  `Warnings.Element == (message: String, debug: String?)`.
- [ ] Add `public func stateChanges() -> BusDispatcher.StateChanges`, where
  `StateChanges.Element == (old: Pipeline.State, new: Pipeline.State)`.
- [ ] `Messages`, `Errors`, `Warnings`, and `StateChanges` are public nested
  custom `AsyncSequence` types, not unbounded `AsyncStream` aliases.
- [ ] Derived observer APIs do not call `Bus.messages(filter:)`,
  `Bus.messageSequence(filter:)`, or otherwise create independent bus drainers.
- [ ] Static API checks verify public nested sequence types, element types, and
  default filters.

### US-003: Wait for EOS or Error Through the Dispatcher

**Description:** As a library user, I want to wait for EOS or ERROR through the
dispatcher so that completion waiting composes with other observers.

**Acceptance Criteria:**
- [ ] Add `public func waitForEOSOrError() async throws` on `BusDispatcher`.
- [ ] On EOS, active `waitForEOSOrError()` calls return successfully.
- [ ] On ERROR, active `waitForEOSOrError()` calls throw
  `GStreamerError.busError(message, source: nil, debug: debug)` using the parsed
  bus error payload.
- [ ] After memoized EOS, a late `waitForEOSOrError()` call returns immediately.
- [ ] After memoized ERROR, a late `waitForEOSOrError()` call throws the same
  bus error immediately.
- [ ] If `close()` happens before EOS or ERROR, active and future
  `waitForEOSOrError()` calls on that closed dispatcher throw `CancellationError`.
- [ ] Runtime tests cover active and late waiter behavior for EOS, ERROR, and
  explicit close.

### US-004: Define Dispatcher Lifecycle

**Description:** As an implementer, I need deterministic dispatcher lifecycle
rules so that the watch, observers, and waiters do not leak resources or hang.

**Acceptance Criteria:**
- [ ] Add `public func close()` on `BusDispatcher`.
- [ ] `close()` is idempotent.
- [ ] `BusDispatcher.deinit` calls `close()`.
- [ ] The dispatcher starts its private bus watch lazily when the first active
  observer or waiter is registered.
- [ ] An observer becomes active when its async iterator is created and remains
  active until cancellation, normal termination, or dispatcher finish.
- [ ] A waiter becomes active when `waitForEOSOrError()` starts and remains active
  until it returns, throws, or is cancelled.
- [ ] When there are zero active observers and waiters, the dispatcher stays open
  but stops the watch so it does not drain or drop bus messages.
- [ ] A later observer or waiter on the same open dispatcher restarts the watch.
- [ ] Cancelling one observer unregisters only that observer and does not close
  the dispatcher or finish other observers.
- [ ] Runtime tests cover observer cancellation, zero-observer idle behavior,
  watch restart, and idempotent close.

### US-005: Broadcast Terminal Messages and Finish Streams

**Description:** As a library user, I want EOS and ERROR to finish dispatcher
streams predictably so that observer tasks do not hang.

**Acceptance Criteria:**
- [ ] EOS and ERROR are terminal for the dispatcher.
- [ ] On EOS, the dispatcher broadcasts `.eos` to matching active observers,
  resumes active `waitForEOSOrError()` calls successfully, then finishes all
  derived streams and marks itself terminal/closed.
- [ ] On ERROR, the dispatcher broadcasts `.error` to matching active observers,
  resumes active `waitForEOSOrError()` calls by throwing, then finishes all
  derived streams and marks itself terminal/closed.
- [ ] Late observer streams after terminal state finish immediately and do not
  replay non-terminal history.
- [ ] Late observer streams after explicit close finish immediately.
- [ ] README and DocC examples await observer tasks only after terminal
  broadcast/finish or explicitly cancel them.
- [ ] Runtime tests prove EOS and ERROR are observable before streams finish.

### US-006: Fan Out Without Unbounded Buffers

**Description:** As a maintainer, I need bounded per-observer buffering so that
slow observers do not hide unbounded queues or block the dispatcher.

**Acceptance Criteria:**
- [ ] Each active observer has its own bounded queue of parsed `BusMessage`
  values.
- [ ] The default observer queue limit is 256 parsed values.
- [ ] Slow observers do not block the dispatcher.
- [ ] If a nonterminal observer queue is full and an incoming noncritical message
  arrives, the incoming noncritical message is dropped.
- [ ] If a nonterminal observer queue is full and incoming ERROR or EOS arrives,
  the dispatcher evicts the oldest noncritical queued value if present;
  otherwise it evicts the oldest critical queued value, then enqueues the
  terminal message so it remains observable before stream finish.
- [ ] Overflow behavior is documented as best effort, not replay or durable
  retention.
- [ ] Runtime tests verify queue bounds and terminal ERROR/EOS preservation under
  slow-observer overflow.

### US-007: Preserve C Ownership and Borrowing Rules

**Description:** As a wrapper maintainer, I need the dispatcher to preserve the
existing safe C ownership model.

**Acceptance Criteria:**
- [ ] The dispatcher uses one private watch-backed drain path per active
  dispatcher.
- [ ] Borrowed watch callback `GstMessage` values are parsed synchronously into
  Swift `BusMessage` values.
- [ ] Borrowed `GstMessage` pointers are never stored past the callback lifetime.
- [ ] Raw `GstMessage` pointers are not exposed in the public dispatcher API.
- [ ] If a future implementation queues raw `GstMessage` pointers internally, it
  must first retain each message and release exactly once; the initial
  implementation must avoid raw pointer queueing.
- [ ] Callback context lifetime is protected across C registration.
- [ ] Static safety tests verify borrowed pointers do not escape callback scope.

### US-008: Keep Direct Bus APIs Source-Compatible

**Description:** As an existing caller, I need current direct bus APIs to keep
working while docs explain when dispatcher ownership is preferred.

**Acceptance Criteria:**
- [ ] `Bus.messageSequence(filter:)` remains source-compatible.
- [ ] `Bus.messages(filter:)` remains source-compatible.
- [ ] `Bus.errors()`, `Bus.warnings()`, `Bus.stateChanges()`, and
  `Bus.waitForEOSOrError()` remain source-compatible.
- [ ] Documentation states that direct bus APIs bypass dispatcher ownership and
  can still compete with a dispatcher if used concurrently on the same `Bus`.
- [ ] README and DocC recommend `BusDispatcher` for multi-observer bus code.
- [ ] Static API checks prove current direct bus API signatures are unchanged.

### US-009: Document and Verify Safe Concurrency

**Description:** As a Swift 6 caller, I need dispatcher APIs to compose with
structured concurrency without requiring main-actor isolation.

**Acceptance Criteria:**
- [ ] `BusDispatcher` is not `@MainActor`.
- [ ] Dispatcher shared mutable state is protected by synchronized internal
  state, such as `Synchronization.Mutex` or an equivalent synchronous lock.
- [ ] The `@unchecked Sendable` safety invariant is documented: all mutable
  dispatcher state is synchronized, borrowed C pointers never escape callback
  scope, and public values crossing tasks are Swift value types or synchronized
  reference owners.
- [ ] A follow-up cleanup note records that `@unchecked Sendable` should be
  revisited if imported GStreamer handle sendability or Swift ownership support
  improves enough to remove it.
- [ ] Continuations are resumed exactly once and outside dispatcher locks.
- [ ] Runtime tests cover cancellation of one observer while other observers and
  waiters continue.

## Functional Requirements

- **FR-1:** The system must expose `public final class BusDispatcher:
  @unchecked Sendable` with no public initializer.
- **FR-2:** The system must expose `public func dispatcher() -> BusDispatcher`
  on `Bus`.
- **FR-3:** Concurrent calls to `Bus.dispatcher()` for the same `Bus` must return
  the same active open dispatcher instance.
- **FR-4:** A dispatcher that reaches EOS, ERROR, or explicit close must be
  removed from the active dispatcher slot for that `Bus`.
- **FR-5:** A later `Bus.dispatcher()` call after close or terminal state may
  create a fresh dispatcher.
- **FR-6:** `BusDispatcher.messages(filter:)` must return
  `BusDispatcher.Messages`, a custom `AsyncSequence` whose element is
  `BusMessage` and whose default filter is `Bus.Filter.all`.
- **FR-7:** `BusDispatcher.errors()` must return `BusDispatcher.Errors`, a
  custom `AsyncSequence` whose element is
  `(message: String, debug: String?)`.
- **FR-8:** `BusDispatcher.warnings()` must return `BusDispatcher.Warnings`, a
  custom `AsyncSequence` whose element is
  `(message: String, debug: String?)`.
- **FR-9:** `BusDispatcher.stateChanges()` must return
  `BusDispatcher.StateChanges`, a custom `AsyncSequence` whose element is
  `(old: Pipeline.State, new: Pipeline.State)`.
- **FR-10:** `BusDispatcher.waitForEOSOrError()` must return on EOS, throw
  `GStreamerError.busError(message, source: nil, debug: debug)` on ERROR, and
  throw `CancellationError` if the dispatcher is closed before terminal bus
  state.
- **FR-11:** `BusDispatcher.close()` must be public, synchronous, and idempotent.
- **FR-12:** The dispatcher must start its private watch lazily when the first
  observer or waiter becomes active.
- **FR-13:** The dispatcher must stop the watch when no observers or waiters are
  active, while keeping the dispatcher open for later reuse.
- **FR-14:** EOS and ERROR must be terminal for a dispatcher and must finish all
  derived streams after active observers and waiters observe terminal state.
- **FR-15:** Terminal EOS or ERROR state must be memoized for future
  `waitForEOSOrError()` calls on the same dispatcher object.
- **FR-16:** Late observer streams after terminal or explicit close must finish
  immediately without replaying non-terminal history.
- **FR-17:** The dispatcher must drain the underlying `GstBus` through exactly
  one internal watch-backed path while active.
- **FR-18:** The dispatcher must parse each borrowed `GstMessage` into
  `BusMessage` synchronously and fan out only Swift values.
- **FR-19:** The dispatcher must not store borrowed `GstMessage` pointers past
  the watch callback lifetime.
- **FR-20:** Each active observer must have a bounded queue capped at 256 parsed
  `BusMessage` values.
- **FR-21:** Slow observers must not block the dispatcher.
- **FR-22:** Noncritical incoming messages must be dropped when a nonterminal
  observer queue is full.
- **FR-23:** Incoming terminal ERROR/EOS messages must evict the oldest
  noncritical queued message when possible, otherwise the oldest critical queued
  message, before enqueueing terminal state for that observer.
- **FR-24:** Direct `Bus.messageSequence(filter:)`, `Bus.messages(filter:)`, and
  bus convenience APIs must remain source-compatible.
- **FR-25:** Derived dispatcher APIs must not call direct destructive `Bus` APIs
  behind the dispatcher's back.
- **FR-26:** The implementation must remain compatible with Swift 6.3.1 and the
  package's declared platform minimums.

## Non-Goals (Out of Scope)

- No source-breaking change to existing direct bus APIs.
- No immediate deprecation of `Bus.messages(filter:)`, `Bus.errors()`,
  `Bus.warnings()`, `Bus.stateChanges()`, or `Bus.waitForEOSOrError()`.
- No guarantee that direct bus APIs cannot bypass dispatcher ownership.
- No replay of non-terminal history to late observers.
- No durable persistence of bus messages.
- No lossless multi-subscriber guarantee under sustained slow observers.
- No public raw `GstMessage` pointer API.
- No requirement to expose a public parser API.
- No `@MainActor` isolation for dispatcher internals.
- No package product or module split.

## Design Considerations

### Resolved Decisions

- **Public owner name:** `BusDispatcher`.
- **Creation API:** `Bus.dispatcher()`.
- **Owner shape:** `public final class BusDispatcher: @unchecked Sendable` with
  synchronized internal state and no public initializer.
- **Observer shape:** public nested custom `AsyncSequence` types, not unbounded
  `AsyncStream` aliases.
- **Default message filter:** dispatcher `messages(filter:)` defaults to
  `Bus.Filter.all`.
- **Drain strategy:** one private watch-backed drain path per active dispatcher.
- **Filtering strategy:** parse modeled `BusMessage` values and apply
  Swift-side observer filtering.
- **Terminal policy:** EOS and ERROR broadcast to active observers and waiters,
  then finish all derived streams and close the dispatcher.
- **Late waiters:** late `waitForEOSOrError()` observes memoized terminal EOS or
  ERROR immediately.
- **Late observers:** late observer streams finish immediately after terminal
  state or explicit close and do not replay prior non-terminal messages.
- **Idle policy:** when no observers or waiters are active, stop the watch and
  keep the dispatcher open so it does not drain or drop bus messages.
- **Direct API policy:** direct bus APIs remain low-level, source-compatible, and
  documented as bypassing dispatcher ownership.

### Non-Hanging Example

```swift
let dispatcher = pipeline.bus.dispatcher()

async let errors: Void = {
    for await error in dispatcher.errors() {
        print(error.message)
    }
}()

async let states: Void = {
    for await stateChange in dispatcher.stateChanges() {
        print(stateChange.new)
    }
}()

try await dispatcher.waitForEOSOrError()

// EOS or ERROR finishes derived streams before the async-let values are awaited.
_ = await (errors, states)
```

## Technical Considerations

- Swift language and package compatibility remain Swift 6.3.1.
- The implementation should reuse the existing private bus watch approach used
  by `Bus.messageSequence(filter:)` where practical.
- The dispatcher must use synchronized internal state rather than `@MainActor`
  isolation.
- Continuations must be resumed exactly once and outside dispatcher locks.
- `@unchecked Sendable` requires a documented safety invariant and should be
  revisited in future cleanup if Swift/GStreamer ownership support improves.
- Watch callback code must not await.
- Borrowed C pointers must stay inside short lexical scopes.
- If documentation or DocC changes are included with implementation, update
  README, `APIContract.md`, and related ADR/task notes to describe dispatcher
  ownership and direct bus API bypass behavior.
- If DocC files are touched, run DocC generation when tooling and system
  dependencies are available.

## Test Plan

- Run dependency preflight:
  `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`.
- Run focused runtime tests for dispatcher fan-out, terminal behavior,
  cancellation, close, late waiters, late observers, overflow, and concurrent
  `Bus.dispatcher()` identity.
- Run static API safety tests for public signatures, no public initializer,
  direct bus API source compatibility, no derived direct drainers, and borrowed
  pointer ownership.
- Run `swiftly run swift test` when dependencies are available.
- Run `swiftly run swift package generate-documentation --target GStreamer` if
  DocC files are touched and DocC tooling is available.

## Success Metrics

- Concurrent derived observers on one dispatcher do not steal matching messages
  from each other in focused runtime tests.
- Terminal waiters complete deterministically for EOS, ERROR, and explicit
  close.
- Late waiters observe memoized terminal state immediately.
- Observer queues remain bounded at 256 under slow-consumer tests.
- Borrowed `GstMessage` pointers never escape callback scope in static safety
  checks.
- Direct `Bus` APIs remain source-compatible in static API checks.
- Focused dispatcher tests, static API safety tests, and full
  `swiftly run swift test` pass when dependencies are available.

## Open Questions

- Should a future major release deprecate direct bus convenience APIs after
  dispatcher adoption stabilizes?
- Should a future release add replay or durable retention as a separate API with
  explicit storage and backpressure semantics?
- Should a future release split low-level bus ownership and high-level
  application event dispatch into separate products or namespaces?
