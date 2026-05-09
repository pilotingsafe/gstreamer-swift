# PRD: Reliable Packet Delivery — Phase 1 (RFC-001)

## Introduction/Overview

This PRD covers **Phase 1** of `RFC-001: Realtime vs Reliable Archival Encoded Packet Delivery`. The goal is to introduce a no-drop, pull-based, throwing AsyncSequence primitive — `ReliablePackets<Element>` — and expose it through a single audio file/decode-style entry point, without disturbing the existing realtime `packets()` API.

Per the accepted RFC-001 Migration Plan #2, Phase 1 is intentionally scoped to **file/decode-style sources only**. Live-source exposure (microphone, webcam) is deferred to RFC-002.

The rationale, semantics, options analysis, and reliability boundary discussion live in `docs/RFCs/RFC-001-realtime-vs-archival-packet-delivery.md`. This PRD does not re-litigate those decisions; it specifies the implementation work.

## Status

Last updated: 2026-05-08.

- Drafting: this PRD (proposed).
- Implementation: not started.
- Related work: RFC-001 (Accepted), RFC-002 (Proposed, blocks live-source extension).

## Goals

- Provide an `AsyncSequence`-conforming reliable packet primitive that **does not drop packets in Swift**.
- Pull from `appsink` only when the consumer awaits, so memory stays bounded by design.
- Throw on pipeline errors; clean EOS terminates with `nil`.
- Detach cleanly on cancellation with no leaked GStreamer mini-objects or Swift continuations.
- Keep existing realtime `packets()` API and tests **unchanged**.
- Land an audio file/decode-style entry point (`AudioSource.reliablePackets()`) as the first concrete adopter.
- Lay generic groundwork so future video file/decode sources can adopt the same primitive without API churn.

## User Stories

### US-001: Add minimal audio file/decode source builder

**Description:** As an implementer, I need an audio source builder that wraps a file/decode-style pipeline (`URIDecodeSource` + audio-only branch + encoder + appsink), so that Phase 1 has a real call site for `reliablePackets()`. The current `AudioSource` builder is microphone-only and has no path to back-pressureable input.

**Acceptance Criteria:**
- [ ] New public builder entry point on `AudioSource` for file/decode input (working name: `AudioSource.uri(_:)` or `AudioSource.file(path:)`; final naming TBD).
- [ ] Pipeline produces audio-only output (audio branch selected from a multi-stream container).
- [ ] Reuses existing `Encoding` (`.raw`, `.opus`, `.aac`) configuration on the builder.
- [ ] AppSink configuration for this builder uses `drop=false` and a non-trivial `max-buffers` (sized for back-pressure, not realtime drop).
- [ ] At least one happy-path build test that runs to PLAYING and reaches EOS on a finite test asset.
- [ ] Typecheck and lint pass.

### US-002: Add `ReliablePackets<Element>` generic AsyncSequence type

**Description:** As an implementer, I need the generic primitive type so the public API surface is committed before any pull-iterator implementation lands.

**Acceptance Criteria:**
- [ ] Public `struct ReliablePackets<Element: Sendable>: AsyncSequence, Sendable` declared in a new file under `Sources/GStreamer/`.
- [ ] Nested `AsyncIterator: AsyncIteratorProtocol` with `mutating func next() async throws -> Element?`.
- [ ] Public `makeAsyncIterator()` factory.
- [ ] Type and iterator pass strict-concurrency checks under Swift 6 mode.
- [ ] DocC comment on the type cross-references RFC-001 and `packets()` for semantic contrast.
- [ ] Typecheck and lint pass.

### US-003: Implement pull-based AppSink bridge

**Description:** As an implementer, I need an internal helper that bridges `appsink`'s `new-sample` signal into Swift's structured concurrency without blocking executor threads, since `gst_app_sink_pull_sample` is blocking and must never run synchronously on a cooperative thread.

**Acceptance Criteria:**
- [ ] New internal type (working name: `ReliableAppSinkBridge`) that owns the `appsink` element handle.
- [ ] Bridge resumes a single `CheckedContinuation` per `new-sample` arrival and uses `try_pull_sample` (non-blocking) to obtain the buffer.
- [ ] EOS produces a `nil` result; `GST_MESSAGE_ERROR` from the pipeline produces a thrown `GStreamerError` consistent with the rest of the bridge.
- [ ] Single-consumer contract: bridge stores at most one continuation; second concurrent `next()` from another task is documented as undefined.
- [ ] Helpers are `nonisolated` and `Sendable` so iteration composes naturally on `@MainActor` call sites without pinning the main actor.
- [ ] Typecheck, lint, and strict-concurrency pass.

### US-004: Cancellation correctness

**Description:** As an implementer, I need cancellation to release the appsink signal handler synchronously, drain any pending continuation, and let the rest of the pipeline (Bus, etc.) keep draining.

**Acceptance Criteria:**
- [ ] Iteration uses `withTaskCancellationHandler` to detach the `new-sample` handler on cancel.
- [ ] After cancellation, no Swift continuation is left pending; no GStreamer mini-object is leaked (verified by ref-count inspection or weak-reference test).
- [ ] After cancellation, the underlying pipeline is still able to drain Bus messages (verified by an integration test that observes a post-cancel Bus message).
- [ ] Typecheck and lint pass.

### US-005: Wire `AudioSource.reliablePackets()` entry point

**Description:** As a library user, I want `mySource.reliablePackets()` on file/decode-style audio sources to obtain a `ReliablePackets<Buffer>` that delivers every encoded packet until EOS.

**Acceptance Criteria:**
- [ ] `extension AudioSource { public func reliablePackets() -> ReliablePackets<Buffer> }` available **only** when the source was built via the file/decode builder (US-001).
- [ ] Calling `reliablePackets()` on a microphone-built `AudioSource` either does not compile (preferred), or fails at runtime with a clearly named error (decision recorded in *Open Questions* below).
- [ ] DocC comment leads with the *Reliability Boundary* caveat from RFC-001 §Reliability Boundary.
- [ ] Typecheck and lint pass.

### US-006: Test — finite source delivers complete packet stream

**Description:** As an implementer, I need to verify the core no-drop promise on a finite input.

**Acceptance Criteria:**
- [ ] Test fixture is a finite, deterministic audio file checked into `Tests/.../Resources/` with a known encoded packet count window.
- [ ] Test reads via `for try await packet in source.reliablePackets() { ... }` and asserts packet count is within the expected window (±1 for encoder framing).
- [ ] Order preservation is asserted by a strictly increasing PTS (or buffer offset) check.
- [ ] EOS terminates the loop without throwing.
- [ ] Test runs under `.timeLimit(.minutes(1))`.
- [ ] Typecheck and lint pass.

### US-007: Test — slow consumer does not lose packets

**Description:** As an implementer, I need to verify that introducing artificial consumer delay does not cause loss on a finite source.

**Acceptance Criteria:**
- [ ] Test consumer adds a deterministic delay between packets (e.g. 5 ms).
- [ ] Final packet count equals the count from US-006.
- [ ] Memory does not grow unboundedly during the slow run (sampled high-water mark stays within a documented envelope).
- [ ] Typecheck and lint pass.

### US-008: Test — cancellation mid-iteration releases resources

**Description:** As an implementer, I need to verify cancellation correctness empirically.

**Acceptance Criteria:**
- [ ] Test cancels the iterating `Task` after N packets.
- [ ] Test verifies the appsink no longer holds the bridge's `new-sample` handler.
- [ ] Test verifies no Swift continuation is leaked (e.g. via a probe weak-reference or a swift-concurrency leak check helper).
- [ ] Test verifies a subsequent Bus message can still be observed on the same pipeline.
- [ ] Typecheck and lint pass.

### US-009: Test — pipeline error during iteration throws

**Description:** As an implementer, I need to verify that `GST_MESSAGE_ERROR` surfaces as a thrown error rather than silent termination.

**Acceptance Criteria:**
- [ ] Test induces a deliberate pipeline error (e.g. an injected element that errors after N packets, or via `gst_element_post_message` from a probe).
- [ ] `for try await` throws.
- [ ] The thrown error is a `GStreamerError` case consistent with the rest of the bridge (specifically not a generic Swift error type).
- [ ] Typecheck and lint pass.

### US-010: Test — `packets()` vs `reliablePackets()` semantic distinction

**Description:** As an implementer, I need a side-by-side test that pins both APIs' contracts on the same finite input.

**Acceptance Criteria:**
- [ ] Two parallel iterations on equivalent sources: one over `packets()` with a slow consumer, one over `reliablePackets()` with a slow consumer.
- [ ] `packets()` path may show packet count strictly less than reference; `reliablePackets()` path must show packet count equal to reference.
- [ ] Test does not assert exact dropped-count for `packets()`, only `received <= reference`.
- [ ] Typecheck and lint pass.

### US-011: DocC topic group + landing article

**Description:** As a library user, I want DocC documentation that lets me discover `reliablePackets()` and understand when to choose it over `packets()`.

**Acceptance Criteria:**
- [ ] New DocC article (working title: `EncodedPacketDelivery.md`) under `Sources/GStreamer/Documentation.docc/` covering realtime vs reliable, with a decision flowchart matching RFC-001 §Reliability Boundary.
- [ ] Topic group references both `packets()` and `reliablePackets()`.
- [ ] Cross-link from `AudioSource` symbol-level DocC to the new article.
- [ ] Build with `swift package generate-documentation` succeeds without warnings on the new symbols.
- [ ] Typecheck, lint, and DocC build pass.

### US-012: README example

**Description:** As a library user, I want a runnable README snippet that uses `reliablePackets()` for the recording-style use case.

**Acceptance Criteria:**
- [ ] New section under `README.md` (or replacement of the existing recording snippet, if any) showing `for try await packet in source.reliablePackets() { ... }` against a file/decode source.
- [ ] Snippet compiles when copy-pasted into an example target (verify in `Examples/`).
- [ ] Snippet calls out the live-source caveat in one sentence and links to the DocC article from US-011.
- [ ] Typecheck and lint pass.

### US-013: CHANGELOG and migration notes

**Description:** As a downstream maintainer, I need a release-note entry that explains the addition.

**Acceptance Criteria:**
- [ ] CHANGELOG (or `RELEASE_NOTES.md` if that is the project convention) entry under the next release with: feature summary, scope (file/decode only, live deferred), link to RFC-001.
- [ ] Migration note clarifies that no existing API changes; `packets()` is unchanged.
- [ ] Typecheck and lint pass.

## Functional Requirements

- **FR-1:** Add `public struct ReliablePackets<Element: Sendable>: AsyncSequence, Sendable` with nested `AsyncIterator: AsyncIteratorProtocol` whose `next()` is `async throws -> Element?`.
- **FR-2:** Provide `AudioSource.reliablePackets() -> ReliablePackets<Buffer>` exclusively on file/decode-built `AudioSource` instances.
- **FR-3:** Add an audio file/decode-style builder on `AudioSource` (US-001) sufficient to host FR-2.
- **FR-4:** Configure the file/decode `appsink` with `drop=false` and a `max-buffers` value sized for back-pressure rather than realtime drop. The realtime `packets()` `appsink` configuration must remain `drop=true max-buffers=1`.
- **FR-5:** Bridge `appsink` output via the `new-sample` signal and `try_pull_sample`; the iterator must never call `gst_app_sink_pull_sample` synchronously from `async` context.
- **FR-6:** Cancellation of the iterating Task must, **synchronously**, detach the `new-sample` signal handler and release any pending continuation.
- **FR-7:** EOS terminates iteration with `nil`. `GST_MESSAGE_ERROR` during iteration causes `next()` to throw a `GStreamerError`.
- **FR-8:** `ReliablePackets` is **single-consumer**. Concurrent iteration from two tasks is undefined; the doc comment must say so.
- **FR-9:** Existing `AudioSource.packets() -> AsyncStream<Buffer>` API, behavior, and tests are unchanged.
- **FR-10:** No public API surface is added on `VideoSource` in this PRD.
- **FR-11:** No public API surface is added that exposes `reliablePackets()` on microphone-built `AudioSource` in this PRD.
- **FR-12:** All new public types and methods pass Swift 6 strict-concurrency checks.

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

- **Source typing.** Two viable approaches for FR-2's "exclusively on file/decode-built `AudioSource`" constraint, to be picked during US-005:
  1. Two distinct source types (`AudioSource` for microphone, `FileAudioSource` for file/decode); `reliablePackets()` lives only on the file/decode type. Compile-time safety, larger API surface.
  2. Single `AudioSource` type with a runtime-checked `reliablePackets()` that traps or throws on microphone-built instances. Smaller API surface, weaker compile-time safety.
- **DocC structure.** New article slot fits under an "Encoded Packet Delivery" topic, parallel to the existing audio capture / device topics in `Sources/GStreamer/Documentation.docc/`.
- **Naming.** Both `reliablePackets()` and `archivalPackets()` remain acceptable per RFC-001. Pick one before US-005 lands; whichever is chosen, the doc comment leads with the boundary caveat.

## Technical Considerations

- **Existing infrastructure to reuse.** The `AudioPacketSink` pattern in `Sources/GStreamer/AudioSource.swift` already shows how an `appsink` is wired with `emit-signals=true`; the reliable bridge will be a sibling of this with different `drop` / `max-buffers` defaults and a different consumer pattern.
- **Concurrency.** All new types must compile under Swift 6 strict concurrency. Bridge state is mutated under a small actor or via `os_unfair_lock`-equivalent; pick whichever matches the rest of the bridge codebase.
- **Cancellation timing.** `withTaskCancellationHandler` runs its handler synchronously on cancel. The handler must not block on GStreamer state changes; it should only detach signal connections and resume any pending continuation with a sentinel.
- **Bus error correlation.** The iterator and the pipeline's `Bus` consumer can race on receiving the same error. The bridge subscribes to bus error messages internally for the duration of iteration, and the existing `Bus` API must remain functional after iteration ends or is cancelled.
- **Test fixtures.** A short (≤1 s), encoder-stable file (e.g. opus-in-ogg or aac-in-mp4) is sufficient for US-006/US-007; pick a fixture small enough to commit.

## Success Metrics

- All new tests in US-006 through US-010 pass on CI on every supported platform.
- `swift test --filter ReliablePackets` runs to completion in under 30 s on the project's standard runner.
- No regression in existing `packets()` test suite (`swift test --filter AppSink`, `swift test --filter Audio`, etc.).
- Memory high-water mark in US-007 stays within an order of magnitude of single-packet size.
- Cancellation in US-008 completes in under 100 ms wall-clock.
- DocC build (US-011) introduces zero new warnings.

## Open Questions

- **Source typing decision (Design §1).** Which of the two approaches — distinct file/decode source type, or runtime-checked single type — does the implementer pick? The PRD does not commit to one; US-005 records the choice.
- **Naming.** `reliablePackets()` vs `archivalPackets()`. RFC-001 leaves this to implementation time.
- **Misuse error model (FR-2 + US-005).** If runtime-checked: should an unsupported call trap, throw a new `GStreamerError` case, or return an empty/erroring sequence? Note that adding a new `GStreamerError` case interacts with the PRD for ADR-001; coordinate.
- **Test asset format.** Opus-in-ogg vs aac-in-mp4 vs raw PCM for the finite-source fixture (US-006). Pick whichever the project already has plugin coverage for on CI.
- **Bus error type taxonomy.** Which `GStreamerError` case does FR-7 surface — `busError(...)` or a new dedicated case? Default to existing `busError(...)` unless implementer finds a reason to differ.
