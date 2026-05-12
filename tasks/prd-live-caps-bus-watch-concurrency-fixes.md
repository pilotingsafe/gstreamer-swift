# PRD: Live Caps, Bus Watch, and Callback Concurrency Fixes

## Introduction/Overview

This PRD covers the concurrency and robustness follow-up fixes for reliable
packet delivery, bus message iteration, and the shared callback-registration
bridge in the GStreamer Swift package.

First, `LiveAudioReliablePacketBridge.detectDiscontinuity` previously performed
GStreamer caps operations while holding `packetState.withLock`. The locked block
included `swift_gst_caps_is_equal`, `swift_gst_caps_ref`, and
`swift_gst_caps_unref`. These calls are not expected to call back into Swift
today, but they can extend the critical section and increase callback latency
for sample, EOS, and error paths that need the same mutex. The implemented fix
keeps caps refcount and equality work outside the packet-state lock while
preserving existing discontinuity semantics.

Second, `Bus.Messages.AsyncIterator.next()` previously called
`swift_gst_bus_timed_pop_filtered` directly from async code with a 100 ms
timeout. That synchronous C call can block a Swift cooperative executor thread.
The implemented fix replaces this with a private GstBus watch-backed delivery
path that uses a private GLib main context and native thread, while keeping the
public `Bus.messageSequence(filter:)` API source-compatible.

The same review pass also closed callback lifetime and lifecycle gaps:
`passUnretained(context)` registration sites are protected with
`withExtendedLifetime(context)`, startup rollback no longer double-decrements
live new-sample handler state, startup timeouts are checked atomically against
first-packet delivery, duration conversion delegates to the shared overflow-safe
helper, `BusMessage.element` parses structure fields, and C callback
registration destruction is claimed once under the mutex before the final
release path runs.

This PRD now records the implemented Swift, C shim, test, and documentation
changes for the caps-lock, bus-watch, callback lifetime, startup-timeout,
duration-conversion, element-field, and callback-registration lifecycle fixes.
A later review pass bounded the watch-backed bus parsed-message backlog and
closed zero-size reliable-packet marker edge cases without changing public API.

## Status

Last updated: 2026-05-12.

- PRD: complete.
- Implementation: complete.
- Checklist: all acceptance criteria completed.
- Review: follow-up review comments addressed, including callback registration
  single-shot destruction, bounded bus backlog overflow, live zero-size marker
  draining, audio-file zero-size sample yielding, and reliable fallback timeout
  test hardening.
- Verification: dependency preflight, focused tests, static API checks, `git diff --check`, and full `swiftly run swift test` passed on 2026-05-11. Additional 2026-05-12 focused verification covers the bounded bus backlog, reliable zero-length markers, live zero-size marker drainage, startup fallback timeout, queue leaky behavior, and static safety checks.
- Scope: caps-lock, bus-watch, callback context lifetime, callback
  registration lifecycle, startup-timeout, duration-conversion, live rollback,
  element-field parsing, bounded bus backlog, and zero-size reliable marker
  fixes described here.
- Active implementation toolchain: Swift 6.3.1.
- Package compatibility requirement: preserve compatibility with the manifest's declared `// swift-tools-version:6.2`.

## Goals

- Remove GStreamer caps ref, equality, and unref operations from `packetState.withLock` critical sections.
- Preserve current live reliable packet discontinuity behavior for format changes, gaps, discont flags, inferred drops, markers, pending discontinuities, prior PTS, and prior duration.
- Remove synchronous 100 ms bus timed-pop blocking from `Bus.Messages.AsyncIterator.next()`.
- Keep `Bus.messageSequence(filter:)`, `Bus.Messages`, and `Bus.Messages.AsyncIterator.next()` public signatures source-compatible.
- Preserve demand-facing async iteration while allowing the active bus watch to buffer matching `BusMessage` values.
- Bound the watch-backed bus parsed-message backlog and prefer ERROR/EOS during
  best-effort overflow.
- Make C and Swift ownership, cancellation, and teardown rules explicit enough for a safe implementation.
- Ensure Swift callback contexts outlive registration calls until C-side retain callbacks have executed.
- Make C callback registration destruction single-shot when disconnect races with an in-flight callback.
- Prevent reliable audio startup timeout and cleanup races from writing stale terminal errors or over-adjusting handler counts.
- Reuse the shared reliable duration conversion path for overflow-safe timeout conversion.
- Populate `BusMessage.element` structure fields instead of returning an unconditional empty payload.
- Ensure zero-size reliable marker samples do not stall live drainage or hot-spin
  file/decode iteration.

## User Stories

### US-001: Move Caps C API Work Out of Packet-State Lock

**Description:** As a library maintainer, I want caps comparison and refcount operations to run outside `packetState.withLock` so that live reliable sample, EOS, and error callbacks are not delayed by caps C API work.

**Acceptance Criteria:**
- [x] `detectDiscontinuity` does not call `swift_gst_caps_is_equal` inside any `packetState.withLock` closure.
- [x] `detectDiscontinuity` does not call `swift_gst_caps_ref` inside any `packetState.withLock` closure.
- [x] `detectDiscontinuity` does not call `swift_gst_caps_unref` inside any `packetState.withLock` closure.
- [x] Replacing or clearing `previousCaps` does not destroy the old retained caps wrapper while `packetState` is locked.
- [x] Typecheck passes under the selected Swift 6.3.1 toolchain.

### US-002: Preserve Live Reliable Discontinuity Semantics

**Description:** As a reliable live audio consumer, I want the caps-lock refactor to preserve existing discontinuity annotations so that downstream packet handling does not change.

**Acceptance Criteria:**
- [x] Existing format-change tests still produce `.formatChange` on the expected packet.
- [x] Existing gap, discont, and inferred dropped-discontinuity tests still pass.
- [x] Marker samples still accumulate pending discontinuity state without emitting a packet.
- [x] Pending discontinuity precedence remains unchanged.
- [x] Clean EOS and cancellation still release retained caps.

### US-003: Add Private GstBus Watch Shim

**Description:** As an implementer, I need an internal C shim around GstBus watch APIs so that bus messages are delivered by GLib instead of by blocking Swift async tasks.

**Acceptance Criteria:**
- [x] Add internal C shim support for a `SwiftGstBusWatchRegistration`.
- [x] The shim creates a private `GMainContext` for each active watch pump.
- [x] The shim creates a `GSource` with `gst_bus_create_watch`.
- [x] The shim runs the private main context on a native thread owned by the registration.
- [x] The shim exposes start and stop functions for Swift internal use.
- [x] The shim does not add public Swift API.

### US-004: Queue Bus Messages Without Storing Borrowed Pointers

**Description:** As an implementer, I need the watch callback to handle borrowed `GstMessage` values safely so that queued async iteration never uses invalid C pointers.

**Acceptance Criteria:**
- [x] The watch callback parses a borrowed `GstMessage` synchronously into a Swift `BusMessage` value before returning.
- [x] Raw `GstMessage` pointers are never stored in the Swift FIFO.
- [x] Swift does not call `swift_gst_message_unref` for borrowed messages received from the watch callback.
- [x] If a future implementation queues raw `GstMessage` pointers, it must first `gst_message_ref` each queued pointer and release exactly once. This PRD requires value queueing instead.
- [x] Unmodeled messages are ignored after parsing returns nil.

### US-005: Preserve Demand-Facing Bus Iteration

**Description:** As a caller of `messageSequence(filter:)`, I want the public async iterator shape to remain source-compatible while avoiding executor-thread blocking.

**Acceptance Criteria:**
- [x] `Bus.messageSequence(filter:) -> Bus.Messages` remains public and source-compatible.
- [x] `Bus.Messages.AsyncIterator.next()` remains `async -> BusMessage?` and non-throwing.
- [x] `next()` no longer calls `swift_gst_bus_timed_pop_filtered`.
- [x] `next()` returns queued messages in FIFO order.
- [x] Queued parsed messages are capped at 256 while no waiter is pending.
- [x] Overflow keeps later ERROR/EOS observable on a best-effort basis by
  dropping older noncritical messages first.
- [x] EOS remains a `BusMessage.eos` value and does not automatically finish the sequence.
- [x] ERROR remains a `BusMessage.error(message:debug:)` value and does not throw from `next()`.

### US-006: Define Watch Pump Lifecycle and Cancellation

**Description:** As an implementer, I need deterministic watch pump lifecycle rules so that cancellation and teardown do not leak threads, GSources, contexts, or Swift continuations.

**Acceptance Criteria:**
- [x] The watch pump protects its FIFO, waiter list, cancellation IDs, and closed/startup-failed state with `Synchronization.Mutex` or equivalent synchronous locking.
- [x] The watch callback never awaits.
- [x] Continuations are always resumed outside the pump lock.
- [x] Closing the pump drains queued values, clears waiters, marks closed, and resumes all waiters with nil outside the lock.
- [x] Stopping the C registration destroys the source, wakes the context, joins the thread, unrefs source/context/bus, and releases the Swift callback context.
- [x] Stop is idempotent.
- [x] Cancelling a pending `next()` removes only that waiter and returns nil for that call; it does not stop the shared pump solely because one copied iterator call was cancelled.

### US-007: Update Static and Runtime Verification

**Description:** As a maintainer, I want tests to pin the new concurrency guarantees so regressions are caught before release.

**Acceptance Criteria:**
- [x] Static checks forbid caps ref, equality, unref, and old retained-caps destruction inside `packetState.withLock`.
- [x] Static bus checks no longer require `swift_gst_bus_timed_pop_filtered`, `100_000_000`, or `swift_gst_message_unref` inside `Bus.Messages`.
- [x] Static bus checks require the new watch shim path.
- [x] Static bus checks forbid `Task.detached` in the Swift iterator path.
- [x] Static bus checks allow continuations and waiters for the watch-backed queue.
- [x] Static bus checks verify raw `GstMessage` pointers are not stored or queued in the Swift iterator or pump path.
- [x] Static bus checks require an explicit `messageSequence` buffer limit and
  bounded overflow handling.
- [x] Runtime bus tests verify bounded overflow keeps a later ERROR observable.

### US-008: Protect Callback Context Lifetime Across C Registration

**Description:** As a bridge maintainer, I need Swift callback contexts to remain
alive until the C shim's retain callback has claimed them so optimized ARC
builds cannot release a locally-created context too early.

**Acceptance Criteria:**
- [x] `LiveAudioReliablePacketBridge.startCallbacks` wraps all callback registration calls in `withExtendedLifetime(context)`.
- [x] `AudioFileSource.ActiveCandidate.init` wraps all callback registration calls in `withExtendedLifetime(context)`.
- [x] `Bus.MessagePump.startWatch` wraps `swift_gst_bus_watch_start` in `withExtendedLifetime(context)`.
- [x] Static API safety tests check all three lifetime guards.
- [x] The pattern stays aligned with the existing `Pad.addProbe` context lifetime guard.

### US-009: Make Callback Registration Destruction Single-Shot

**Description:** As a C bridge maintainer, I need disconnect, callback completion,
and startup-failure paths to agree on exactly one final destruction owner so
concurrent teardown cannot double-release the Swift context, GObject, or
registration allocation.

**Acceptance Criteria:**
- [x] `SwiftGstCallbackRegistration` includes a synchronized `destroying` state bit.
- [x] The destroy claim helper checks `signal_destroyed`, `in_flight == 0`, and `!destroying` while holding the mutex.
- [x] The claim helper sets `destroying = TRUE` before unlocking.
- [x] Final destruction releases the Swift context, unrefs the GObject, clears the mutex, and frees the registration exactly once outside the mutex.
- [x] Disconnect-while-callback-in-flight test coverage verifies retain/release balance.
- [x] Static API safety tests require the single-shot destroy claim pattern.

### US-010: Close Reliable Audio Startup Edge Cases

**Description:** As a reliable-packet caller, I need startup timeout, duration
conversion, and cleanup rollback paths to be deterministic under races and
extreme testing inputs.

**Acceptance Criteria:**
- [x] Live reliable startup rollback marks the unstored new-sample registration as disconnected so cleanup does not decrement handler state twice.
- [x] Audio file reliable startup timeout checks candidate identity, shutdown state, and first-packet delivery under one state lock before writing `terminalError`.
- [x] The first delivered audio-file packet is marked before `next()` returns it to the caller.
- [x] `Duration.nanosecondsForReliablePackets` delegates to `ReliableDurationConversion.nanosecondsClampingNegativeToZero`.
- [x] Static API safety tests cover rollback, startup-timeout atomicity, and duration conversion.
- [x] Startup fallback tests avoid applying an unrealistically short timeout to
  the valid fallback candidate under full parallel test load.

### US-011: Populate Element Message Fields

**Description:** As a bus consumer, I need `BusMessage.element(name:fields:)` to
carry available `GstStructure` fields so the `.element` filter is useful for
messages such as navigation, marker, or sink-specific events.

**Acceptance Criteria:**
- [x] `GST_MESSAGE_ELEMENT` parsing reads `gst_message_get_structure`.
- [x] Structure field names are enumerated with `gst_structure_n_fields` and `gst_structure_nth_field_name`.
- [x] String fields are read with `gst_structure_get_string` to avoid lossy quoting.
- [x] Non-string fields use `gst_value_serialize` as a best-effort textual representation.
- [x] Runtime bus tests verify an element marker field is delivered through `messageSequence(filter: [.element])`.

### US-012: Close Bounded Backlog and Zero-Size Marker Review Findings

**Description:** As a maintainer, I need the review follow-ups to keep
backpressured bus iteration memory bounded and make zero-size reliable marker
samples cooperative under queued-sample and flood conditions.

**Acceptance Criteria:**
- [x] `Bus.messageSequence(filter:)` buffers at most 256 parsed `BusMessage`
  values while no waiter is pending.
- [x] Bus overflow handling treats ERROR and EOS as critical, dropping older
  noncritical messages before discarding critical events.
- [x] Live reliable zero-size marker samples are skipped by continuing the
  nonblocking drain loop before waiting on a newer generation.
- [x] Audio file/decode reliable zero-size samples are skipped one sample per
  pull, yield cooperatively before retrying, and re-check terminal state.
- [x] Review hardening tests cover bus backlog overflow, live queued-marker
  drainage, repeated file zero-length samples, fallback startup timeout, and the
  queue leaky comparison flake.

## Functional Requirements

- **FR-1:** `detectDiscontinuity` must use a deterministic retry loop for lock-free caps work.
- **FR-2:** The retry loop must snapshot, under lock, every discontinuity state value read by `detectDiscontinuity`, including `previousCaps`, prior PTS, prior duration, pending discontinuity, and a state version token.
- **FR-3:** The state version token must change whenever any snapshotted discontinuity state changes, including `previousCaps` replacement or clearing.
- **FR-4:** After taking a snapshot, caps retain and equality comparison must happen outside `packetState.withLock`.
- **FR-5:** After caps comparison, `detectDiscontinuity` must reacquire the lock and apply caps plus discontinuity updates only if the full state token still matches.
- **FR-6:** On token mismatch, any newly retained caps must be released outside the lock and the operation must retry from a fresh snapshot.
- **FR-7:** There is no allowed fallback that treats a token mismatch as "no format change."
- **FR-8:** If packet state becomes cancelled, stopped, or completed during retry, `detectDiscontinuity` must return nil without mutating discontinuity state.
- **FR-9:** Replacing or clearing `previousCaps` must move or swap the old retained wrapper into a local variable while locked, then release it after unlocking.
- **FR-10:** No `swift_gst_caps_ref`, `swift_gst_caps_is_equal`, `swift_gst_caps_unref`, or RAII wrapper destruction may occur inside `packetState.withLock`.
- **FR-11:** `Bus.Messages.AsyncIterator.next()` must not call blocking bus timed-pop APIs.
- **FR-12:** The watch-backed path must use a private `GMainContext` and native thread per active watch pump.
- **FR-13:** The C shim must use `gst_bus_create_watch` to create the `GSource`.
- **FR-14:** The watch callback must consume all bus messages delivered to the active watch, filter them using the caller's `filter.gstMessageType`, parse matching modeled messages into `BusMessage`, and ignore nonmatching or unmodeled messages.
- **FR-15:** The Swift pump must use a bounded FIFO queue for matching parsed
  `BusMessage` values while the iterator is active, capped at 256 messages when
  no waiter is pending.
- **FR-16:** If watch startup fails, or GStreamer refuses a second active watch for a bus, the pump must close deterministically: release partial resources, resume pending waiters with nil, and make future `next()` calls return nil.
- **FR-17:** `Bus.Messages.AsyncIterator` copies made from the same `makeAsyncIterator()` result must share one pump reference rather than creating competing watches.
- **FR-18:** Public `Bus` and `Bus.Messages` API signatures must remain source-compatible.
- **FR-19:** Callback registration call sites that pass local Swift contexts through `Unmanaged.passUnretained(context).toOpaque()` must keep the local strong reference alive through the complete C registration call.
- **FR-20:** C callback registration destruction must be claimed under the registration mutex before any final release work can run.
- **FR-21:** Live reliable startup rollback must not let later cleanup decrement the new-sample handler count a second time for a registration that was never stored.
- **FR-22:** Audio file reliable startup timeout must not write a terminal timeout error after the first packet has been delivered.
- **FR-23:** Reliable packet duration conversion must clamp negative values to zero and overflow values to `UInt64.max` through the shared helper.
- **FR-24:** `BusMessage.element` must preserve available structure fields as `[String: String]` without changing the public enum shape.
- **FR-25:** Bus overflow handling must prefer ERROR and EOS over older
  noncritical messages on a best-effort basis.
- **FR-26:** Live reliable zero-size marker samples must not cause iteration to
  wait for a newer generation when a real sample is already queued.
- **FR-27:** Audio file/decode reliable zero-size samples must not spin in a
  nonblocking pull loop without yielding or checking terminal state.

## Non-Goals (Out of Scope)

- No public bus observer API is added.
- No fan-out bus dispatcher or replay registry is added.
- No legacy `Bus.messages(filter:)` buffering contract is changed. Bounded
  overflow is scoped to the watch-backed `messageSequence(filter:)` parsed-value
  backlog.
- No public `BusMessage` shape change is added.
- No change is made to `Bus.messages(filter:)`, `Bus.errors()`, `Bus.warnings()`, or `Bus.stateChanges()` public signatures.
- No change is made to the package manifest's declared Swift tools version.

## Technical Considerations

- Implemented areas are `AudioSourceReliableDelivery.swift`, `AudioFileSource.swift`, `Bus.swift`, `GStreamerAppShim.c`, and the internal C shim headers and source.
- The caps RAII wrapper should make ownership explicit, but implementation must avoid triggering its destructor while `packetState` is locked.
- The discontinuity retry token should be simple and internal, for example a monotonically increasing integer stored in packet state.
- The bus watch callback receives borrowed messages. GStreamer unrefs those messages after the callback returns, so the Swift path must queue value-typed `BusMessage` results, not raw message pointers.
- The watch pump lock should protect all mutable Swift pump state. It should not be held while resuming continuations.
- The active watch changes internal semantics of `messageSequence(filter:)`: the API remains demand-facing, but messages can be drained and buffered before the consumer awaits `next()`. That parsed-value backlog is bounded at 256 messages with best-effort ERROR/EOS retention.
- `withExtendedLifetime(context)` is required around registration calls that rely on the C shim's retain callback, because the raw `UnsafeMutableRawPointer` produced by `passUnretained` is not an ARC lifetime use after `toOpaque()` returns.
- The C callback registration finalizer must run after releasing the registration mutex; only the single-shot claim itself belongs under the lock.
- Documentation and static tests must be updated to remove the old claim that `messageSequence(filter:)` polls only when `next()` is awaited.
- The implementation should be validated with Swift 6.3.1 through `swiftly`, while avoiding source or manifest features that require a tools version newer than 6.2.

## Test Plan

- [x] Add static checks ensuring `detectDiscontinuity` lock closures do not contain caps ref, equality, unref calls, or direct `previousCaps` replacement that can destroy old caps under lock.
- [x] Keep and run live reliable behavior tests covering format change, pending discontinuity precedence, marker handling, cleanup, and retained caps release.
- [x] Add bus tests proving watch-backed `messageSequence` receives EOS, ERROR, and state changes.
- [x] Add bus tests proving EOS remains non-terminating for `messageSequence`.
- [x] Add bus tests proving pending `next()` completes promptly with nil on cancellation.
- [x] Add a bus filter test proving nonmatching messages consumed by the active watch are not delivered to a narrower-filter iterator.
- [x] Update static bus tests to remove requirements for `swift_gst_bus_timed_pop_filtered`, `100_000_000`, and `swift_gst_message_unref` inside `Bus.Messages`.
- [x] Update static bus tests to require the new watch shim path, forbid `Task.detached` in Swift iterator code, allow continuations or waiters, and verify raw `GstMessage` pointers are not stored or queued.
- [x] Add static and runtime checks for the bounded watch-backed bus backlog and
  best-effort ERROR/EOS overflow behavior.
- [x] Add static checks for `withExtendedLifetime(context)` around live reliable, audio file reliable, and bus watch callback registration.
- [x] Add static checks for callback registration single-shot destruction claimed under the mutex.
- [x] Add a focused callback lifecycle test for disconnect while a callback is in flight.
- [x] Add static checks for live startup rollback handler-count cleanup.
- [x] Add static checks for audio file startup-timeout atomicity.
- [x] Add static checks for shared overflow-safe duration conversion.
- [x] Add bus runtime coverage for element message structure fields.
- [x] Add reliable-packet coverage for live zero-size marker drainage and
  repeated file/decode zero-length samples.
- [x] Harden the startup fallback timeout and queue leaky behavior tests against
  full parallel suite scheduling noise.
- [x] Run dependency preflight: `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`.
- [x] Run focused verification with Swift 6.3.1:
  - [x] `swiftly run swift test --filter AudioSourceReliableLiveBehavior`
  - [x] `swiftly run swift test --filter BusMessageSequence`
  - [x] `swiftly run swift test --filter CallbackRegistrationLifecycleTests`
  - [x] `swiftly run swift test --filter APISafetyStaticTests`
  - [x] `git diff --check`
- [x] `swiftly run swift test`
  - [x] 2026-05-12 focused review follow-up checks:
    `BusMessageSequenceTests`, `ReliablePacketZeroLengthMarkerTests`,
    `AudioSourceReliableLiveBehaviorTests`,
    `ReliablePacketStartupTimeoutTests`, `QueueLeakyBehaviorTests`, and
    `APISafetyStaticTests`.

## Success Metrics

- [x] The PRD is saved at `tasks/prd-live-caps-bus-watch-concurrency-fixes.md`.
- [x] The PRD is detailed enough for an implementer to proceed without choosing caps ownership, retry, watch lifecycle, filtering, buffering, or cancellation semantics.
- [x] The PRD preserves public API compatibility while documenting the accepted internal semantic change for `messageSequence(filter:)`.
- [x] The PRD lists concrete static and runtime verification steps.
- [x] The PRD records the follow-up callback lifetime, C registration lifecycle, startup-timeout, duration-conversion, element-field parsing, bounded bus backlog, and zero-size marker fixes.

## Open Questions

- None. The implementation choices are fixed for this PRD.
