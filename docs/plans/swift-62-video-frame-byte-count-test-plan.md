# Swift 6.2 VideoFrame Byte Count Test Plan

> Superseded note: the repository support baseline was later raised to Swift
> 6.3.1. This historical plan documents the earlier Swift 6.2.4 compiler-crash
> workaround and is no longer the active toolchain baseline plan.

## Summary

Avoid a macOS CI Swift 6.2.4 compiler crash by reshaping test assertions that read
`VideoFrame.bytes.byteCount` directly inside Swift Testing macros. Keep the public
`VideoFrame` API, GStreamer ownership behavior, and CI Swift version unchanged.

## Problem

The macOS 26 arm64 CI job intentionally installs Swift 6.2.4 to validate Swift
6.2 compatibility. Test code currently places `frame.bytes.byteCount` directly
inside `#expect` expressions. `VideoFrame.bytes` is a lifetime-bound `RawSpan`
property implemented with `_read`, so wrapping that access in Swift Testing macro
expansion can trigger a Swift 6.2.4 frontend SIL/lifetime verifier crash.

This is a compiler/test-expression-shape problem, not a GStreamer runtime or
buffer ownership failure.

## Goals

- Preserve Swift 6.2 compatibility without moving CI to Swift 6.3 or later.
- Preserve the public `VideoFrame.bytes` and `VideoFrame.withUnsafeBytes(_:)`
  APIs.
- Keep existing async frame retrieval behavior and `#require` evidence checks.
- Avoid direct `VideoFrame.bytes` / `RawSpan` lifetime-bound access inside
  Swift Testing macro arguments where the test is only validating byte count.
- Preserve explicit coverage that `VideoFrame.bytes.byteCount` remains usable.
- Keep the change limited to tests and BDD/TDD workflow artifacts.

## Non-Goals

- Do not change GStreamer buffer mapping, reference counting, or ownership.
- Do not alter production API behavior or documentation contracts.
- Do not treat unrelated deprecation warnings, including `waitForEOS()`, as the
  cause of this failure.
- Do not change `.github/workflows/ci.yml` to a newer Swift version.

## Current Behavior

- `AppSinkSmokeTests.videoFrameData` asserts
  `#expect(frame.bytes.byteCount == 4 * 4 * 4)`.
- `AppSinkSmokeTests.pullFrames` asserts
  `#expect(frame.bytes.byteCount > 0)`.
- `AppSourceTests` asserts `#expect(frame.bytes.byteCount == 16)` for a video
  roundtrip.
- `VideoFrameReadOnlyAPITests` asserts
  `#expect(frame.bytes.byteCount == expectedByteCount)` and separately checks
  `withUnsafeBytes`.
- `APISafetyStaticTests.asyncMediaSmokeTestsKeepPostLoopEvidenceAssertions`
  requires the exact old `#expect(frame.bytes.byteCount == 4 * 4 * 4)` snippet.

## Proposed Behavior

- Tests that need byte-count evidence from actual frames should compute a plain
  local integer using:

  ```swift
  let byteCount = try frame.withUnsafeBytes { $0.count }
  #expect(byteCount == expectedCount)
  ```

- Tests specifically covering the `bytes` property should first read
  `frame.bytes.byteCount` into a local value and then assert on that local:

  ```swift
  let bytesByteCount = frame.bytes.byteCount
  #expect(bytesByteCount == expectedByteCount)
  ```

- `APISafetyStaticTests` should require equivalent post-loop byte-count evidence
  without requiring the exact crash-prone `#expect(frame.bytes.byteCount ...)`
  expression.

## Affected Modules

- `Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift`
- `Tests/SwiftGStreamerTests/AppSourceTests.swift`
- `Tests/SwiftGStreamerTests/VideoFrameReadOnlyAPITests.swift`
- `Tests/SwiftGStreamerTests/APISafetyStaticTests.swift`
- BDD/TDD workflow artifacts under `docs/plans`, `docs/bdd`, and the empty
  skeleton test file.

## Public API and Interface Changes

None. `VideoFrame.bytes` and `VideoFrame.withUnsafeBytes(_:)` remain supported
and documented. CI continues to validate `SWIFT_VERSION=6.2.4`.

## Data, State, and Lifecycle Changes

None. Frame ownership, buffer mapping, async stream behavior, and pipeline
lifecycle are unchanged.

## Error Handling and Safety

The safer test shape uses `try frame.withUnsafeBytes` where byte-count evidence
does not need to exercise the `bytes` property. This preserves normal error
propagation from failed buffer mapping while keeping unsafe pointers scoped to
the closure.

The dedicated read-only API test still exercises `frame.bytes.byteCount`, but it
stores the lifetime-bound result into a plain local before entering `#expect`.

## Compatibility

The fix targets Swift 6.2.4 compatibility and should also compile under newer
Swift toolchains. It avoids Swift 6.3-only syntax and keeps the package minimum
at Swift 6.2.

## Observability and Rollout

No runtime observability changes are needed. Rollout evidence is the focused test
set plus broader package test compilation. The definitive compatibility signal
is the macOS 26 arm64 CI job using `SWIFT_VERSION=6.2.4`.

## BDD Scenario Mapping

- Scenario 1: AppSink frame byte-count evidence avoids lifetime-bound macro
  access.
  - `AppSinkSmokeTests.videoFrameData`
  - `AppSinkSmokeTests.pullFrames`
- Scenario 2: AppSource/AppSink roundtrip byte-count evidence avoids
  lifetime-bound macro access.
  - `AppSourceTests` roundtrip test
- Scenario 3: Read-only API coverage still validates both byte access APIs.
  - `VideoFrameReadOnlyAPITests.bgraFrameReadOnlyByteViewsExposeExpectedCount`
- Scenario 4: Static safety guard accepts equivalent post-loop byte-count
  evidence.
  - `APISafetyStaticTests.asyncMediaSmokeTestsKeepPostLoopEvidenceAssertions`
- Scenario 5: CI Swift version stays pinned to Swift 6.2.4.
  - No CI file source change; verified by inspection.

## Empty-Test Skeleton Plan

Create `Tests/SwiftGStreamerTests/Swift62VideoFrameByteCountBDDTests.swift` with
only empty Swift Testing test declarations and Given/When/Then comments mapping
to the Gherkin scenarios. Do not include imports beyond minimal test syntax,
assertions, setup, helper logic, fixtures, production logic, or executable test
bodies.

## Formal Test Strategy

After user confirmation at the empty-test gate:

1. Convert the empty skeleton into formal static guard tests that inspect the
   affected test declarations.
2. Assert that no `#expect(frame.bytes.byteCount` expression remains in
   `AppSinkSmokeTests.swift`, `AppSourceTests.swift`, or
   `VideoFrameReadOnlyAPITests.swift`.
3. Assert that tests using actual frame byte-count evidence contain local
   `withUnsafeBytes { $0.count }` or equivalent local count extraction before
   `#expect`.
4. Assert that `VideoFrameReadOnlyAPITests` keeps a local
   `frame.bytes.byteCount` read and a separate `withUnsafeBytes` count check.
5. Assert that `.github/workflows/ci.yml` continues to set
   `SWIFT_VERSION: 6.2.4`.

Existing runtime smoke tests continue to validate actual frame retrieval and byte
counts after their assertions are reshaped.

## Implementation Sequence

1. Add plan and Gherkin BDD artifacts.
2. Review and revise the plan/spec until the plan reviewer reports
   `Verdict: No Findings`.
3. Create only the empty BDD test skeleton and ask the user for confirmation.
4. After confirmation, write formal static guard tests first.
5. Run required preflights before build or test work:
   - `swiftly run swift --version`
   - `pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0`
6. Run the new formal BDD/static guard suite and observe the expected failure
   before reshaping the existing tests when feasible:
   - `swiftly run swift test --filter Swift62VideoFrameByteCountBDDTests`
7. Update the affected existing tests to avoid direct lifetime-bound access in
   macros while preserving coverage.
8. Update `APISafetyStaticTests` to require equivalent byte-count evidence.
9. Rerun the BDD/static guard suite:
   - `swiftly run swift test --filter Swift62VideoFrameByteCountBDDTests`
10. Run focused tests:
   - `swiftly run swift test --filter AppSinkSmokeTests`
   - `swiftly run swift test --filter VideoFrameReadOnlyAPITests`
   - `swiftly run swift test --filter APISafetyStaticTests`
   - `swiftly run swift test --filter AppSourceTests`
11. Run `swiftly run swift test` for broader compile and test coverage when
    dependencies are available.
12. Run spec compliance, code-quality, and final whole-change reviews.

## Risks

- Local Swift is newer than CI Swift 6.2.4, so local tests cannot prove the
  compiler crash is fixed. CI remains the authoritative Swift 6.2.4 signal.
- Overly loose static guards could pass without proving byte-count evidence
  remains. Guard tests should inspect function bodies, not whole-file substrings
  only.
- Overly broad edits could accidentally reduce read-only API coverage. The
  `VideoFrameReadOnlyAPITests` local `bytes` count check prevents that.

## Acceptance Criteria

- No `#expect(frame.bytes.byteCount` remains in affected video-frame tests.
- Byte-count assertions for normal smoke tests use local counts computed through
  `withUnsafeBytes`.
- `VideoFrameReadOnlyAPITests` still validates `frame.bytes.byteCount` and
  `withUnsafeBytes` byte counts, with assertions on locals.
- `APISafetyStaticTests` no longer requires the old exact crash-prone snippet and
  requires equivalent post-loop byte-count evidence.
- No public API or CI Swift-version change is made.
- Focused tests pass locally when GStreamer dependencies are available.
- Broader `swiftly run swift test` passes locally when feasible, or any blocker
  is reported.
- Required preflights are run before local build/test verification, or any
  unavailable dependency/toolchain is reported as a blocker.
- macOS CI with `SWIFT_VERSION=6.2.4` is expected to pass without the compiler
  frontend crash.

## Assumptions

- The CI failure is a Swift 6.2.4 compiler bug exposed by Swift Testing macro
  expansion around lifetime-bound `RawSpan` access.
- Changing test expression shape is safer than changing library ownership or
  buffer mapping semantics.
- `VideoFrame.bytes` remains a supported read-only API.
