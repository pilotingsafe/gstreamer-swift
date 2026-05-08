# PRD: GStreamer Bridge Safety and Reliability Fixes

## Introduction

This PRD defines a safety and reliability repair effort for the Swift/GStreamer bridge in `gstreamer-swift`. The work addresses correctness bugs in C callback bridging, unsafe public mutability on pulled video frames, invalid appsrc input crashes, unbounded media stream buffering, request pad ownership, and verification gaps.

Phase 1 and Phase 2 are the required first implementation scope. Phase 3 and Phase 4 may be split into follow-up PRs if needed.

## Status

Last updated: 2026-05-08.

- Phase 1: Complete in current uncommitted changes.
- Phase 2: Complete in current uncommitted changes; public symbol verification is recorded under Phase 4.
- Phase 3: Complete in current uncommitted changes.
- Phase 4: Complete in current uncommitted changes.
- Review: Complete; current uncommitted changes were reviewed with no actionable issues found.

Verified locally:
- `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`
- `pkg-config --modversion gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`
- `swift package dump-symbol-graph --minimum-access-level public --skip-synthesized-members > /tmp/gstreamer-swift-symbols.json`
- `jq -e '([.symbols[] | select(.pathComponents[0] == "VideoFrame") | .pathComponents | join(".")] | index("VideoFrame.bytes") and index("VideoFrame.withUnsafeBytes(_:)") and (index("VideoFrame.mutableBytes") | not) and (index("VideoFrame.withUnsafeMutableBytes(_:)") | not))' .build/arm64-apple-macosx/symbolgraph/GStreamer.symbols.json`
- `swift build`
- `swift test --filter PadProbeTests`
- `swift test --filter AppSourceTests`
- `swift test --filter RequestPadLifecycleTests`
- `swift test --filter APISafetyStaticTests`
- `swift test --filter 'DeviceMonitorTests|AppSinkSmokeTests|CVPixelBufferTests|TimestampTests|AudioTests|BusMessageTests|AppSourceTests|TeeTests|VideoFrameReadOnlyAPITests'`
- `swift test --filter VideoFrameReadOnlyAPITests`
- `swift test --filter BufferValueSemanticsTests`
- `swift test`
- `git diff --check`
- `git diff --cached --check`

Verification notes:
- `pkg-config --modversion` reported `1.28.2` for `gstreamer-1.0`, `gstreamer-app-1.0`, and `gstreamer-video-1.0`.
- The symbol graph dump command writes status lines to `/tmp/gstreamer-swift-symbols.json`; the actual public symbol JSON was checked in `.build/arm64-apple-macosx/symbolgraph/*.symbols.json`.
- The public symbol graph contains `VideoFrame.bytes` and `VideoFrame.withUnsafeBytes(_:)`; it does not contain `VideoFrame.mutableBytes` or `VideoFrame.withUnsafeMutableBytes(_:)`. The mutable API absence check was scoped to `VideoFrame`; `Buffer.mutableBytes` and `Buffer.withUnsafeMutableBytes(_:)` remain public.
- Phase 4 test hygiene replaced silent CI guard-return skips and silent async smoke-test passes with deterministic zero-or-more assertions, `#require` evidence checks, post-loop assertions, and `.timeLimit(.minutes(1))` on finite async smoke suites.
- Review verification reran `swift build`, a focused safety/lifecycle/API test filter, and full `swift test`; all passed. Existing non-fatal GStreamer parent-disposal critical logs still appear in some runs, but the final full-suite run completed successfully with 155 Swift Testing tests and no signal 11.

## Goals

- Fix `Pad.addProbe` so Swift callbacks execute reliably and callback context ownership is released exactly once.
- Make pulled `VideoFrame` values read-only at the public API level to prevent concurrent mutation of shared `GstBuffer` storage.
- Make all public `AppSource` push entry points reject invalid empty input or non-positive byte counts without trapping.
- Add bounded buffering defaults to current media APIs that already return `AsyncStream`, while keeping their return types unchanged.
- Close request pad lifecycle gaps and simplify `Buffer.mutableBytes` copy-on-write behavior.
- Improve tests, README/API consistency, and dependency preflight guidance for GStreamer system libraries.

## User Stories

### US-001: Pad Probe Callback Bridge

**Description:** As a library user, I want pad probe callbacks to execute reliably so that I can inspect or control GStreamer pad data flow.

**Acceptance Criteria:**
- [x] `addProbe` passes retained Swift context as GStreamer `user_data`.
- [x] `destroy_data` releases retained context exactly once.
- [x] Probe context has synchronized cleanup state so explicit zero-id cleanup and `destroy_data` cannot double-release.
- [x] Callback return values map correctly to `GstPadProbeReturn`.
- [x] `.remove` removes the probe and releases context.
- [x] `ProbeHandle` id `0` is invalid internally, and `removeProbe` is a no-op for id `0`.
- [x] `addIdleProbe` is safe if callback fires during `gst_pad_add_probe`.
- [x] `swift test --filter PadProbeTests` passes when dependencies are installed.

### US-002: Read-Only VideoFrame

**Description:** As a concurrency-safe Swift user, I want pulled frames to be immutable so copied `VideoFrame` values cannot concurrently mutate shared C storage.

**Acceptance Criteria:**
- [x] `VideoFrame` keeps `bytes` and `withUnsafeBytes`.
- [x] `mutableBytes` and `withUnsafeMutableBytes` are absent from public API.
- [x] Internal build, docs, examples, and tests no longer reference removed mutable APIs.
- [x] Migration notes explain mutation requires copying into `Buffer` or another mutable structure.
- [x] Public symbol graph or generated docs no longer include mutable `VideoFrame` APIs.

### US-003: AppSource Input Validation

**Description:** As a library user, I want invalid appsrc pushes to throw predictably so empty input cannot crash my process.

**Acceptance Criteria:**
- [x] Empty `[UInt8]`, `Span<UInt8>`, and `RawSpan` pushes throw `GStreamerError.bufferMapFailed`.
- [x] `push(bytes:count:)` rejects `count <= 0`.
- [x] For `count > 0`, docs state the caller must pass a valid pointer for at least `count` bytes.
- [x] Non-empty pushes preserve current timestamp and ownership behavior.
- [x] Tests assert invalid inputs throw and do not trap.

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
- [x] Request pad released state is protected by synchronization.
- [x] Request pad ownership model is documented as strong `Element` owner unless a retained raw pointer approach is justified and tested.
- [x] `Buffer.mutableBytes` uses one COW path.
- [x] README lists required system dependencies and preflight commands.
- [x] README/examples are checked for stale API names.
- [x] Silent-pass and non-deterministic tests are replaced with explicit skip/known issue semantics or deterministic assertions.

## Functional Requirements

- FR-1: Probe callback lookup must not depend on a global id-to-context dictionary.
- FR-2: Probe context ownership must be transferred with `Unmanaged.passRetained` and released by exactly one synchronized cleanup path.
- FR-3: Zero probe id cleanup must check synchronized cleanup state before explicit release.
- FR-4: Public `VideoFrame` must not expose mutable access to pulled `GstBuffer` data.
- FR-5: All public appsrc push APIs must validate non-empty input before pointer access or `gsize` conversion.
- FR-6: `push(bytes:count:)` must reject `count <= 0`; pointer validity for `count > 0` remains caller responsibility.
- FR-7: Current `AsyncStream` media APIs must define bounded buffering without changing return types in this PR.
- FR-8: Request pad release must be synchronized and idempotent.
- FR-9: Build docs must state all system dependencies needed before `swift build` or `swift test`.

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
- If `gst_pad_add_probe` returns `0`, avoid both leaks and double-release by tracking whether `destroy_data` executed with synchronized state on `ProbeContext`.
- Cover `.remove`, manual `removeProbe`, id `0` no-op, and `addIdleProbe` immediate callback behavior.
- Validate empty input and `count <= 0` across all public `AppSource` push APIs.

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

If `gst_pad_add_probe` returns `0`, the implementation must avoid both leaks and double-release. Track whether `destroy_data` executed, for example with a synchronized flag on `ProbeContext`, before performing explicit zero-id cleanup.

### Request Pad Owner Model

Request pads should keep a strong owner `Element` reference for reliable auto-release. A retained raw owner pointer may only be used if the implementation documents why it is safer and tests balanced ref/unref behavior.

## Success Metrics

- Pad probe tests fail on current implementation and pass after the fix.
- Empty appsrc input tests pass without runtime traps.
- Symbol graph or generated docs no longer expose mutable `VideoFrame` access.
- Current `AsyncStream` media APIs have explicit bounded defaults: raw audio newest 1, encoded packets newest 8.
- `swift build` and `swift test` pass in an environment with GStreamer development dependencies installed.
- README setup instructions let a fresh macOS/Linux developer diagnose missing `pkg-config` before Swift compilation.

## Open Questions

- Should a future release add a more semantically precise public error case for invalid appsrc input?
- Should encoded packet APIs eventually gain a reliable archival delivery alternative separate from best-effort realtime streams?
- Should bus messages later migrate to a pull-based sequence to avoid control-plane buffering ambiguity?

## Assumptions

- Phase 1 and Phase 2 are required first implementation scope.
- Phase 3 and Phase 4 may be split into follow-up PRs.
- Source-breaking removal of public mutable `VideoFrame` access is acceptable.
- Empty appsrc input is invalid and should throw `GStreamerError.bufferMapFailed`.
- Encoded packet streams are best-effort realtime streams, not reliable recording streams.
- Request pads should keep a strong owner `Element` model by default.
