# PRD: Reliable Packet Delivery — Phase 1 (RFC-001)

## Introduction/Overview

This PRD covers **Phase 1** of `RFC-001: Realtime vs Reliable Archival Encoded Packet Delivery`. The goal is to introduce a no-drop, pull-based, throwing AsyncSequence primitive — `ReliablePackets<Element>` — and expose it through a single audio file/decode-style entry point, without disturbing the existing realtime `packets()` API.

Per the accepted RFC-001 Migration Plan #2, Phase 1 is intentionally scoped to **file/decode-style sources only**. Live-source exposure (microphone, webcam) is implemented by the RFC-002 follow-up.

The rationale, semantics, options analysis, and reliability boundary discussion live in `docs/RFCs/RFC-001-realtime-vs-archival-packet-delivery.md`. This PRD does not re-litigate those decisions; it specifies the implementation work.

## Status

Last updated: 2026-05-11.

- PRD: accepted for Phase 1 implementation.
- Implementation: complete in local uncommitted changes; review-ready.
- Story status: US-001 through US-013 implemented for Phase 1.
- Follow-up hardening: complete for callback context lifetime, startup-timeout atomicity, and shared duration conversion.
- Checklist: all Phase 1 acceptance criteria and follow-up hardening checks completed.
- Verification:
  - `swiftly run swift test --filter Reliable` passed.
  - `swiftly run swift build --target gst-reliable-audio` passed.
  - `swiftly run swift test` passed on rerun; an initial full-suite run showed a transient failure in the pre-existing `QueueLeakyBehaviorTests` suite.
  - `git diff --check` passed.
- Resolved implementation decisions:
  - Source typing uses a distinct `AudioFileSource` returned by `AudioSource.file(path:)`, so microphone-built `AudioSource` values do not expose `reliablePackets()`.
  - Public API name is `reliablePackets()`.
  - Reliable iteration surfaces bus failures as `GStreamerError.busError(...)`.
  - Deterministic test assets are generated at runtime in per-test temporary directories; `Tests/SwiftGStreamerTests/Resources/ReliablePackets/README.md` reserves the resource location for future binary fixtures.
- Related work: RFC-001 (Accepted); RFC-002 implements the live-source extension; `tasks/prd-live-caps-bus-watch-concurrency-fixes.md` records shared reliable-packet hardening.

## Goals

- Provide an `AsyncSequence`-conforming reliable packet primitive that **does not drop packets in Swift**.
- Pull from `appsink` only when the consumer awaits, so memory stays bounded by design.
- Throw on pipeline errors; clean EOS terminates with `nil`.
- Detach cleanly on cancellation with no leaked GStreamer mini-objects or Swift continuations.
- Keep existing realtime `packets()` API and tests **unchanged**.
- Land an audio file/decode-style entry point (`AudioSource.file(path:)` -> `AudioFileSource.reliablePackets()`) as the first concrete adopter.
- Lay generic groundwork so future video file/decode sources can adopt the same primitive without API churn.
- Record follow-up hardening for `AudioFileSource` callback registration lifetime, startup-timeout races, and timeout duration conversion.

## User Stories

### US-001: Add minimal audio file/decode source builder

**Description:** As an implementer, I need an audio source builder that wraps a file/decode-style pipeline (`URIDecodeSource` + audio-only branch + encoder + appsink), so that Phase 1 has a real call site for `reliablePackets()`. The current `AudioSource` builder is microphone-only and has no path to back-pressureable input.

**Acceptance Criteria:**
- [x] New public builder entry point on `AudioSource` for file/decode input: `AudioSource.file(path:)`.
- [x] Pipeline produces audio-only output (audio branch selected from a multi-stream container).
- [x] Reuses existing `Encoding` (`.raw`, `.opus`, `.aac`) configuration on the builder.
- [x] AppSink configuration for this builder uses `drop=false` and a non-trivial `max-buffers` (sized for back-pressure, not realtime drop).
- [x] At least one happy-path build test that runs to PLAYING and reaches EOS on a finite test asset.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-002: Add `ReliablePackets<Element>` generic AsyncSequence type

**Description:** As an implementer, I need the generic primitive type so the public API surface is committed before any pull-iterator implementation lands.

**Acceptance Criteria:**
- [x] Public `struct ReliablePackets<Element: Sendable>: AsyncSequence, Sendable` declared in a new file under `Sources/GStreamer/`.
- [x] Nested `AsyncIterator: AsyncIteratorProtocol` with `public func next() async throws -> Element?`.
- [x] Public `makeAsyncIterator()` factory.
- [x] Type and iterator pass strict-concurrency checks under Swift 6 mode.
- [x] Public docs contrast `ReliablePackets` with realtime `packets()`; RFC-001 is linked from PRD/CHANGELOG context.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-003: Implement pull-based AppSink bridge

**Description:** As an implementer, I need an internal helper that bridges `appsink`'s `new-sample` signal into Swift's structured concurrency without blocking executor threads, since `gst_app_sink_pull_sample` is blocking and must never run synchronously on a cooperative thread.

**Acceptance Criteria:**
- [x] Internal reliable source/active-candidate bridge owns the `appsink`, bus observer, and signal registration lifetimes.
- [x] Bridge resumes a single `CheckedContinuation` per `new-sample` arrival and uses `try_pull_sample` (non-blocking) to obtain the buffer.
- [x] EOS produces a `nil` result; `GST_MESSAGE_ERROR` from the pipeline produces a thrown `GStreamerError` consistent with the rest of the bridge.
- [x] Single-consumer contract: the sequence stores at most one continuation and rejects concurrent `next()` calls with `GStreamerError.invalidArgument`.
- [x] Iterator entry point is `@concurrent`, and reliable sequence/source state is `Sendable` or explicitly synchronized so iteration composes naturally on `@MainActor` call sites.
- [x] Swift build/test pass under the package's Swift 6 settings; no separate project lint command is defined in this PRD.

### US-004: Cancellation correctness

**Description:** As an implementer, I need cancellation to release the appsink signal handler synchronously, drain any pending continuation, and let the rest of the pipeline (Bus, etc.) keep draining.

**Acceptance Criteria:**
- [x] Iteration uses `withTaskCancellationHandler` to detach the `new-sample` handler on cancel.
- [x] After cancellation, no Swift continuation is left pending and callback cleanup is observable through lifecycle probes.
- [x] After cancellation, the underlying pipeline is still able to drain Bus messages (verified by an integration test that observes a post-cancel Bus message).
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-005: Wire `AudioFileSource.reliablePackets()` entry point

**Description:** As a library user, I want `myFileSource.reliablePackets()` on file/decode-style audio sources to obtain a `ReliablePackets<Buffer>` that delivers every encoded packet until EOS.

**Acceptance Criteria:**
- [x] `AudioFileSource` exposes `public func reliablePackets() -> ReliablePackets<Buffer>`.
- [x] Calling `reliablePackets()` on a microphone-built `AudioSource` does not compile because the method is not present on `AudioSource`.
- [x] DocC comment leads with the *Reliability Boundary* caveat from RFC-001 §Reliability Boundary.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-006: Test — finite source delivers complete packet stream

**Description:** As an implementer, I need to verify the core no-drop promise on a finite input.

**Acceptance Criteria:**
- [x] Test fixture is a finite, deterministic audio file generated in a per-test temporary directory, with `Tests/SwiftGStreamerTests/Resources/ReliablePackets/README.md` reserving the fixture location for future checked-in assets.
- [x] Test reads via `for try await packet in source.reliablePackets() { ... }` and asserts packet count is within the expected window (±1 for encoder framing).
- [x] Order preservation is asserted by a strictly increasing PTS (or buffer offset) check.
- [x] EOS terminates the loop without throwing.
- [x] Test runs under `.timeLimit(.minutes(1))`.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-007: Test — slow consumer does not lose packets

**Description:** As an implementer, I need to verify that introducing artificial consumer delay does not cause loss on a finite source.

**Acceptance Criteria:**
- [x] Test consumer adds a deterministic delay between packets (e.g. 5 ms).
- [x] Final packet count equals the count from US-006.
- [x] Memory does not grow unboundedly during the slow run (sampled high-water mark stays within a documented envelope).
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-008: Test — cancellation mid-iteration releases resources

**Description:** As an implementer, I need to verify cancellation correctness empirically.

**Acceptance Criteria:**
- [x] Test cancels the iterating `Task` after N packets.
- [x] Test verifies the reliable bridge's `new-sample` handler count returns to zero after cleanup.
- [x] Test verifies no Swift continuation remains pending through lifecycle probe state.
- [x] Test verifies a subsequent Bus message can still be observed on the same pipeline.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-009: Test — pipeline error during iteration throws

**Description:** As an implementer, I need to verify that `GST_MESSAGE_ERROR` surfaces as a thrown error rather than silent termination.

**Acceptance Criteria:**
- [x] Test induces a deliberate pipeline error (e.g. an injected element that errors after N packets, or via `gst_element_post_message` from a probe).
- [x] `for try await` throws.
- [x] The thrown error is a `GStreamerError` case consistent with the rest of the bridge (specifically not a generic Swift error type).
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-010: Test — `packets()` vs `reliablePackets()` semantic distinction

**Description:** As an implementer, I need a side-by-side test that pins both APIs' contracts on the same finite input.

**Acceptance Criteria:**
- [x] Two parallel iterations on equivalent sources: one over `packets()` with a slow consumer, one over `reliablePackets()` with a slow consumer.
- [x] `packets()` path may show packet count strictly less than reference; `reliablePackets()` path must show packet count equal to reference.
- [x] Test does not assert exact dropped-count for `packets()`, only `received <= reference`.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-011: DocC topic group + landing article

**Description:** As a library user, I want DocC documentation that lets me discover `reliablePackets()` and understand when to choose it over `packets()`.

**Acceptance Criteria:**
- [x] New DocC article (working title: `EncodedPacketDelivery.md`) under `Sources/GStreamer/Documentation.docc/` covering realtime vs reliable, with a decision flowchart matching RFC-001 §Reliability Boundary.
- [x] Topic group references both `packets()` and `reliablePackets()`.
- [x] Cross-link from `AudioSource` symbol-level DocC to the new article.
- [x] `swiftly run swift package generate-documentation` succeeds; the repo still emits its existing executable-target top-level-content warnings, including the new example executable target.
- [x] Swift build/test and DocC generation pass; no separate project lint command is defined in this PRD.

### US-012: README example

**Description:** As a library user, I want a runnable README snippet that uses `reliablePackets()` for the recording-style use case.

**Acceptance Criteria:**
- [x] New section under `README.md` (or replacement of the existing recording snippet, if any) showing `for try await packet in source.reliablePackets() { ... }` against a file/decode source.
- [x] Snippet compiles when copy-pasted into an example target (verify in `Examples/`).
- [x] Snippet calls out the live-source caveat in one sentence and links to the DocC article from US-011.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-013: CHANGELOG and migration notes

**Description:** As a downstream maintainer, I need a release-note entry that explains the addition.

**Acceptance Criteria:**
- [x] CHANGELOG (or `RELEASE_NOTES.md` if that is the project convention) entry under the next release with: feature summary, scope (file/decode only, live deferred), link to RFC-001.
- [x] Migration note clarifies that no existing API changes; `packets()` is unchanged.
- [x] Swift build/test pass; no separate project lint command is defined in this PRD.

### US-014: File Reliable Follow-Up Hardening

**Description:** As a maintainer, I need the Phase 1 file reliable bridge to
incorporate review hardening for callback lifetime, startup timeout races, and
duration conversion overflow handling.

**Acceptance Criteria:**
- [x] `AudioFileSource.ActiveCandidate.init` keeps the local Swift callback context alive with `withExtendedLifetime(context)` through all C registration calls.
- [x] Startup timeout reporting checks active candidate identity, shutdown state, and first-packet delivery under one state lock before writing `terminalError`.
- [x] The first delivered packet is marked before `next()` returns it to the caller.
- [x] `Duration.nanosecondsForReliablePackets` delegates to `ReliableDurationConversion.nanosecondsClampingNegativeToZero`.
- [x] Static API safety tests cover callback lifetime, startup-timeout atomicity, and duration conversion.

## Functional Requirements

- **FR-1:** Add `public struct ReliablePackets<Element: Sendable>: AsyncSequence, Sendable` with nested `AsyncIterator: AsyncIteratorProtocol` whose `next()` is `async throws -> Element?`.
- **FR-2:** Provide `AudioFileSource.reliablePackets() -> ReliablePackets<Buffer>` exclusively through `AudioSource.file(path:)`.
- **FR-3:** Add an audio file/decode-style builder on `AudioSource` (US-001) sufficient to host FR-2.
- **FR-4:** Configure the file/decode `appsink` with `drop=false` and a `max-buffers` value sized for back-pressure rather than realtime drop. The realtime `packets()` `appsink` configuration must remain `drop=true max-buffers=1`.
- **FR-5:** Bridge `appsink` output via the `new-sample` signal and `try_pull_sample`; the iterator must never call `gst_app_sink_pull_sample` synchronously from `async` context.
- **FR-6:** Cancellation of the iterating Task must, **synchronously**, detach the `new-sample` signal handler and release any pending continuation.
- **FR-7:** EOS terminates iteration with `nil`. `GST_MESSAGE_ERROR` during iteration causes `next()` to throw a `GStreamerError`.
- **FR-8:** `ReliablePackets` is **single-consumer**. Concurrent iteration from two tasks is rejected with a structured invalid-argument error.
- **FR-9:** Existing `AudioSource.packets() -> AsyncStream<Buffer>` API, behavior, and tests are unchanged.
- **FR-10:** No public API surface is added on `VideoSource` in this PRD.
- **FR-11:** No public API surface is added that exposes `reliablePackets()` on microphone-built `AudioSource` in this PRD.
- **FR-12:** All new public types and methods pass Swift 6 strict-concurrency checks.
- **FR-13:** File reliable callback registration must protect local `passUnretained` contexts through the complete C registration call.
- **FR-14:** File reliable startup timeout must not write a terminal timeout error after the first packet has been delivered.
- **FR-15:** Reliable startup timeout duration conversion must use the shared overflow-safe reliable duration conversion helper.

## Non-Goals (Out of Scope)

- **NG-1:** Live-source exposure (`AudioSource.microphone()`, `VideoSource.webcam()`, any `is-live=true` source). Tracked in RFC-002.
- **NG-2:** Video file/decode entry point on `VideoSource`. Mirrors a future PRD.
- **NG-3:** `record(to: URL)` / file-oriented recording convenience API. Tracked in a future RFC.
- **NG-4:** Multi-consumer / fan-out semantics on `ReliablePackets`.
- **NG-5:** Any user-visible knob for backpressure configuration on `reliablePackets()`. Pipeline-level queue config remains the source builder's responsibility.
- **NG-6:** Renaming or deprecating `packets()`.
- **NG-7:** Changing the value of `MediaStreamBackpressure.encodedPacketsNewest` (currently 8) or moving it out of `AudioSource.swift`.
- **NG-8:** Introducing a `LocalizedError` conformance on `GStreamerError` (tracked in PRD for ADR-001).
- **NG-9:** A `packets(buffer:)` overload exposing realtime queue depth (tracked as deferred in RFC-001).

## Design Considerations

- **Source typing.** Implemented with two distinct source types: `AudioSource` for microphone/live capture, and `AudioFileSource` for file/decode reliable delivery. `reliablePackets()` lives only on `AudioFileSource`.
- **DocC structure.** New article slot fits under an "Encoded Packet Delivery" topic, parallel to the existing audio capture / device topics in `Sources/GStreamer/Documentation.docc/`.
- **Naming.** Implemented as `reliablePackets()`.

## Technical Considerations

- **Existing infrastructure to reuse.** The `AudioPacketSink` pattern in `Sources/GStreamer/AudioSource.swift` already shows how an `appsink` is wired with `emit-signals=true`; the reliable bridge will be a sibling of this with different `drop` / `max-buffers` defaults and a different consumer pattern.
- **Concurrency.** All new types must compile under Swift 6 strict concurrency. Bridge state is mutated under a small actor or via `os_unfair_lock`-equivalent; pick whichever matches the rest of the bridge codebase.
- **Cancellation timing.** `withTaskCancellationHandler` runs its handler synchronously on cancel. The handler must not block on GStreamer state changes; it should only detach signal connections and resume any pending continuation with a sentinel.
- **Bus error correlation.** The iterator and the pipeline's `Bus` consumer can race on receiving the same error. The bridge subscribes to bus error messages internally for the duration of iteration, and the existing `Bus` API must remain functional after iteration ends or is cancelled.
- **Test fixtures.** Tests generate short deterministic WAV/container fixtures at runtime, avoiding binary fixture churn while keeping a resource directory placeholder for future committed assets.
- **Callback registration lifetime.** Registration sites that pass a local Swift context through `passUnretained` must use `withExtendedLifetime(context)` around the C registration calls.
- **Startup timeout race.** Startup timeout reporting must perform its candidate, shutdown, and first-packet checks in the same state-lock transition that writes the terminal error.

## Success Metrics

- All new tests in US-006 through US-010 pass on CI on every supported platform.
- `swiftly run swift test --filter Reliable` runs to completion in under 30 s on the local runner.
- No regression in existing `packets()` test suite (`swiftly run swift test --filter AppSink`, `swiftly run swift test --filter Audio`, etc.).
- Memory high-water mark in US-007 stays within an order of magnitude of single-packet size.
- Cancellation in US-008 completes in under 100 ms wall-clock.
- DocC generation succeeds; executable-target top-level-content warnings remain a known repo-wide documentation issue.
- Static safety tests pin file reliable callback lifetime, startup-timeout atomicity, and shared duration conversion.

## Resolved Questions

- **Source typing decision:** distinct `AudioFileSource`, returned from `AudioSource.file(path:)`.
- **Naming:** `reliablePackets()`.
- **Misuse error model:** microphone-built `AudioSource` misuse does not compile because no `reliablePackets()` member is exposed there.
- **Test asset format:** deterministic runtime-generated fixtures, with raw and Opus coverage plus conditional AAC coverage.
- **Bus error type taxonomy:** existing `GStreamerError.busError(...)`.
- **Follow-up hardening:** `AudioFileSource.ActiveCandidate` callback lifetime, startup-timeout race handling, and duration conversion reuse are complete.
