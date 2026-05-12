# PRD: GStreamer Bridge Safety and Reliability Fixes

## Introduction

This PRD defines a safety and reliability repair effort for the Swift/GStreamer bridge in `gstreamer-swift`. The work addresses correctness bugs in C callback bridging, unsafe public mutability on pulled video frames, invalid appsrc input handling, unbounded media stream buffering, request pad ownership, and verification gaps.

Phase 1 and Phase 2 are the required first implementation scope. Phase 3 and Phase 4 may be split into follow-up PRs if needed.

## Status

Last updated: 2026-05-11.

- Phase 1: Complete in current uncommitted changes.
- Phase 2: Complete in current uncommitted changes; public symbol verification is recorded under Phase 4.
- Phase 3: Complete in current uncommitted changes.
- Phase 4: Complete in current uncommitted changes.
- Callback registration lifecycle follow-up: Complete in current uncommitted changes.
- Checklist: all original phase checklists and callback lifecycle follow-up checks completed.
- Review: Complete; follow-up review comments were addressed in current uncommitted changes.

Verified locally:
- `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`
- `pkg-config --modversion gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`
- `swiftly run swift package dump-symbol-graph --minimum-access-level public --skip-synthesized-members > /tmp/gstreamer-swift-symbols.json`
- `jq -e '([.symbols[] | select(.pathComponents[0] == "VideoFrame") | .pathComponents | join(".")] | index("VideoFrame.bytes") and index("VideoFrame.withUnsafeBytes(_:)") and (index("VideoFrame.mutableBytes") | not) and (index("VideoFrame.withUnsafeMutableBytes(_:)") | not))' .build/arm64-apple-macosx/symbolgraph/GStreamer.symbols.json`
- `swiftly run swift build`
- `swiftly run swift test --filter PadProbeTests`
- `swiftly run swift test --filter AppSourceTests`
- `swiftly run swift test --filter RequestPadLifecycleTests`
- `swiftly run swift test --filter APISafetyStaticTests`
- `swiftly run swift test --filter 'DeviceMonitorTests|AppSinkSmokeTests|CVPixelBufferTests|TimestampTests|AudioTests|BusMessageTests|AppSourceTests|TeeTests|VideoFrameReadOnlyAPITests'`
- `swiftly run swift test --filter VideoFrameReadOnlyAPITests`
- `swiftly run swift test --filter BufferValueSemanticsTests`
- `swiftly run swift test`
- `git diff --check`
- `git diff --cached --check`

Verification notes:
- `pkg-config --modversion` reported `1.28.2` for `gstreamer-1.0`, `gstreamer-app-1.0`, and `gstreamer-video-1.0`.
- New verification reruns should use the repository-standard `swiftly run swift ...` command form.
- The symbol graph dump command writes status lines to `/tmp/gstreamer-swift-symbols.json`; the actual public symbol JSON was checked in `.build/arm64-apple-macosx/symbolgraph/*.symbols.json`.
- The public symbol graph contains `VideoFrame.bytes` and `VideoFrame.withUnsafeBytes(_:)`; it does not contain `VideoFrame.mutableBytes` or `VideoFrame.withUnsafeMutableBytes(_:)`. The mutable API absence check was scoped to `VideoFrame`; `Buffer.mutableBytes` and `Buffer.withUnsafeMutableBytes(_:)` remain public.
- Phase 4 test hygiene replaced silent CI guard-return skips and silent async smoke-test passes with deterministic zero-or-more assertions, `#require` evidence checks, post-loop assertions, and `.timeLimit(.minutes(1))` on finite async smoke suites.
- Review follow-up fixed `Element.releasePad(_:)` receiver-owner validation and added an empty `ProbeType` short-circuit while retaining zero-id probe cleanup through local synchronized context state.
- Callback registration follow-up made shared C callback registration destruction single-shot under the registration mutex and added disconnect-while-callback-in-flight coverage.
- Review verification reran `swiftly run swift build`, focused pad probe and request pad lifecycle tests, and full `swiftly run swift test`; all passed. Existing non-fatal GStreamer parent-disposal critical logs still appear in some runs, but the final full-suite run completed successfully with 158 Swift Testing tests and no signal 11.

## Goals

- Fix `Pad.addProbe` so Swift callbacks execute reliably and callback context ownership is released exactly once.
- Make pulled `VideoFrame` values read-only at the public API level to prevent concurrent mutation of shared `GstBuffer` storage.
- Make public `AppSource` raw push entry points accept zero-length buffers while rejecting negative byte counts and missing pointers for positive byte counts without trapping.
- Add bounded buffering defaults to current media APIs that already return `AsyncStream`, while keeping their return types unchanged.
- Close request pad lifecycle gaps and simplify `Buffer.mutableBytes` copy-on-write behavior.
- Improve tests, README/API consistency, and dependency preflight guidance for GStreamer system libraries.

## User Stories

### US-001: Pad Probe Callback Bridge

**Description:** As a library user, I want pad probe callbacks to execute reliably so that I can inspect or control GStreamer pad data flow.

**Acceptance Criteria:**
- [x] `addProbe` passes retained Swift context as GStreamer `user_data`.
- [x] `destroy_data` releases retained context exactly once.
- [x] Probe context has synchronized cleanup state so local zero-id release and `destroy_data` cannot double-release.
- [x] Callback return values map correctly to `GstPadProbeReturn`.
- [x] `.remove` removes the probe and releases context.
- [x] `ProbeHandle` id `0` is invalid internally, and `removeProbe` is a no-op for id `0`.
- [x] Empty probe type registration returns invalid handle without invoking the callback.
- [x] `addIdleProbe` is safe if callback fires during `gst_pad_add_probe`.
- [x] `swiftly run swift test --filter PadProbeTests` passes when dependencies are installed.

### US-002: Read-Only VideoFrame

**Description:** As a concurrency-safe Swift user, I want pulled frames to be immutable so copied `VideoFrame` values cannot concurrently mutate shared C storage.

**Acceptance Criteria:**
- [x] `VideoFrame` keeps `bytes` and `withUnsafeBytes`.
- [x] `mutableBytes` and `withUnsafeMutableBytes` are absent from public API.
- [x] Internal build, docs, examples, and tests no longer reference removed mutable APIs.
- [x] Migration notes explain mutation requires copying into `Buffer` or another mutable structure.
- [x] Public symbol graph or generated docs no longer include mutable `VideoFrame` APIs.

### US-003: AppSource Input Validation

**Description:** As a library user, I want appsrc raw pushes to handle zero-length buffers predictably and invalid positive-length inputs to throw instead of crashing my process.

**Acceptance Criteria:**
- [x] Zero-length `[UInt8]`, `Span<UInt8>`, and `RawSpan` raw pushes are valid and push zero-length GStreamer buffers.
- [x] `push(bytes:count:)` rejects `count < 0` and ignores the pointer when `count == 0`.
- [x] For `count > 0`, docs state the caller must pass a valid pointer for at least `count` bytes.
- [x] Positive-length pushes preserve current timestamp and ownership behavior.
- [x] Tests assert invalid inputs throw, and zero-length raw inputs do not trap.

### US-004: AsyncStream Media Backpressure

**Description:** As a realtime media user, I want current `AsyncStream` media APIs to avoid unbounded memory growth when consumers are slow.

**Acceptance Criteria:**
- [x] Existing media APIs that return `AsyncStream` keep that return type.
- [x] Pull-based APIs such as `AppSink.Frames` are unchanged.
- [x] Raw audio buffer streams use `.bufferingNewest(1)`.
- [x] Encoded packet streams use `.bufferingNewest(8)` or equivalent named constant.
- [x] Encoded packet docs state packets may be dropped under slow-consumer backpressure.
- [x] Bus message streams do not use a dropping bounded policy in this PR.

### US-005: Lifecycle and Test Hygiene

**Description:** As a maintainer, I want ownership and tests to reflect real behavior so regressions are caught reliably.

**Acceptance Criteria:**
- [x] Request pads release exactly once across manual release, concurrent release attempts, and deinit.
- [x] `Element.releasePad(_:)` releases only pads requested by the receiver element.
- [x] Request pad released state is protected by synchronization.
- [x] Request pad ownership model is documented as strong `Element` owner unless a retained raw pointer approach is justified and tested.
- [x] `Buffer.mutableBytes` uses one COW path.
- [x] README lists required system dependencies and preflight commands.
- [x] README/examples are checked for stale API names.
- [x] Silent-pass and non-deterministic tests are replaced with explicit skip/known issue semantics or deterministic assertions.

### US-006: Shared Callback Registration Lifecycle

**Description:** As a bridge maintainer, I want callback registration teardown to
be safe when disconnect races with an in-flight C callback so that context
release, object unref, and registration free happen exactly once.

**Acceptance Criteria:**
- [x] Callback registrations track a synchronized `destroying` state.
- [x] Destroy ownership is claimed under the registration mutex only when `signal_destroyed` is set, `in_flight == 0`, and destruction has not already been claimed.
- [x] The claim path sets `destroying = TRUE` before unlocking.
- [x] Final destruction runs outside the mutex after a successful claim.
- [x] Disconnect, callback completion, and startup failure paths all use the same claim helper.
- [x] A focused test covers disconnect while a callback is in flight and verifies balanced context retain/release counts.
- [x] Static API safety tests pin the single-shot destruction pattern.

## Functional Requirements

- FR-1: Probe callback lookup must not depend on a global id-to-context dictionary.
- FR-2: Probe context ownership must be transferred with `Unmanaged.passRetained` and released by exactly one synchronized cleanup path.
- FR-3: Zero probe id cleanup must check synchronized cleanup state before explicit release.
- FR-4: Public `VideoFrame` must not expose mutable access to pulled `GstBuffer` data.
- FR-5: Public raw appsrc push APIs must accept zero-length input without pointer access and validate negative counts before `gsize` conversion.
- FR-6: `push(bytes:count:)` must reject `count < 0`; pointer validity is required only for `count > 0`, and the pointer is ignored for `count == 0`.
- FR-7: Current `AsyncStream` media APIs must define bounded buffering without changing return types in this PR.
- FR-8: Request pad release must be synchronized and idempotent.
- FR-9: Build docs must state all system dependencies needed before `swiftly run swift build` or `swiftly run swift test`.
- FR-10: Shared C callback registration destruction must be claimed exactly once under the registration mutex.
- FR-11: Callback registration final release work must not run while holding the registration mutex.

## Non-Goals

- No new capture or playback features.
- No C++ interop or bidirectional Swift/C++ work.
- No new public error case unless later explicitly approved.
- No source-breaking stream return type migration.
- No guaranteed archival delivery for encoded packet `AsyncStream`.
- No bus dropping policy.
- No UI or browser work.

## Technical Considerations

### Implementation Phases

**Phase 1: Correctness Blockers** - Complete in current uncommitted changes
- Fix `Pad.addProbe` using retained `ProbeContext` as GStreamer `user_data`, released through `destroy_data`.
- If `gst_pad_add_probe` returns `0`, avoid both leaks and double-release by checking synchronized state on the local strong `ProbeContext` before releasing the retained unmanaged context.
- Cover `.remove`, manual `removeProbe`, id `0` no-op, and `addIdleProbe` immediate callback behavior.
- Allow zero-length raw input across public `AppSource` raw push APIs while rejecting negative counts and missing positive-length payload pointers.

**Phase 2: API Safety** - Implementation complete in current uncommitted changes; generated docs verification remains in Phase 4
- Make `VideoFrame` public API read-only.
- Update docs, README examples, and tests for removed mutable frame APIs.
- Simplify `Buffer.mutableBytes` to reuse `ensureUnique()` and avoid duplicate copy attempts.

**Phase 3: Lifecycle and Backpressure** - Complete in current uncommitted changes
- Request pads should keep a strong owner `Element` reference for reliable auto-release.
- A retained raw owner pointer may only be used if the implementation documents why it is safer and tests balanced ref/unref behavior.
- Request pad release must be synchronized and idempotent across manual release, concurrent release, and deinit.
- Raw realtime audio buffer streams default to `.bufferingNewest(1)`.
- Encoded packet streams default to `.bufferingNewest(8)` or an internal named constant with equivalent documented semantics.
- Bus messages are control-plane events; this PR must not introduce a dropping bus policy.

**Phase 4: Verification and Docs** - Complete in current uncommitted changes
- README must list `pkgconf/pkg-config` and GStreamer development packages.
- Preflight guidance must include `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`.
- Silent-pass and non-deterministic tests must be replaced with explicit skip/known issue semantics or deterministic assertions.
- Symbol graph confirms public API no longer exposes mutable `VideoFrame` members.

### Existing Stream Return Types

Current media APIs that already return `AsyncStream` must keep their `AsyncStream` return type in this PR. This does not change existing pull-based APIs such as `AppSink.Frames`.

### Encoded Packet Buffering

Encoded packet streams use a concrete bounded policy, preferably `.bufferingNewest(8)` by default, or an internal named constant with equivalent documented semantics. These streams are best-effort realtime delivery and may drop packets under slow-consumer backpressure.

### Probe Zero-Id Cleanup

If `gst_pad_add_probe` returns `0`, the implementation must avoid both leaks and double-release. Keep the local strong `ProbeContext` in scope, check its synchronized cleanup state, and release the retained unmanaged context only when `destroy_data` has not already claimed cleanup.

### Request Pad Owner Model

Request pads should keep a strong owner `Element` reference for reliable auto-release. A retained raw owner pointer may only be used if the implementation documents why it is safer and tests balanced ref/unref behavior.

### Callback Registration Destruction

The shared callback-registration bridge must treat destruction as a claimed
state transition. Once `signal_destroyed` is true and `in_flight` reaches zero,
exactly one caller may set `destroying = TRUE` while the mutex is held. That
caller performs Swift context release, object unref, mutex clear, and allocation
free outside the lock.

## Success Metrics

- Pad probe tests fail on current implementation and pass after the fix.
- Zero-length raw appsrc input tests pass without runtime traps.
- Symbol graph or generated docs no longer expose mutable `VideoFrame` access.
- Current `AsyncStream` media APIs have explicit bounded defaults: raw audio newest 1, encoded packets newest 8.
- `swiftly run swift build` and `swiftly run swift test` pass in an environment with GStreamer development dependencies installed.
- README setup instructions let a fresh macOS/Linux developer diagnose missing `pkg-config` before Swift compilation.
- Callback registration lifecycle tests verify disconnect-while-callback-in-flight teardown remains balanced.

## Open Questions

- Should a future release add a more semantically precise public error case for invalid appsrc input?
- Should encoded packet APIs eventually gain a reliable archival delivery alternative separate from best-effort realtime streams?
- Should bus messages later migrate to a pull-based sequence to avoid control-plane buffering ambiguity?

## Assumptions

- Phase 1 and Phase 2 are required first implementation scope.
- Phase 3 and Phase 4 may be split into follow-up PRs.
- Source-breaking removal of public mutable `VideoFrame` access is acceptable.
- Zero-length raw appsrc input is valid and should push a zero-length buffer; negative counts are invalid, pointer validity is required only for positive counts, and `Buffer(data: [])` is intentionally valid.
- Encoded packet streams are best-effort realtime streams, not reliable recording streams.
- Request pads should keep a strong owner `Element` model by default.
