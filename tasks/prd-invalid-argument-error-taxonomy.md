# PRD: Invalid Argument Error Taxonomy (ADR-001)

## Introduction/Overview

This PRD implements `ADR-001: Invalid Input Error Taxonomy for AppSource and Future APIs`. The feature adds a structured `GStreamerError.invalidArgument(parameter:reason:)` case for caller-side validation failures, migrates existing `AppSource` invalid-input throws away from `GStreamerError.bufferMapFailed`, and updates documentation, tests, and release notes so downstream users can distinguish invalid arguments from low-level buffer failures.

ADR-001 is `Accepted and implemented`. This PRD tracks the API cleanup release work that added the structured invalid-argument taxonomy.

## Status

Last updated: 2026-05-11.

- Drafting: reviewed and revised.
- Implementation: completed in the current API cleanup changes.
- Release notes: added in `CHANGELOG.md`.
- Verification: `swiftly run swift build`, `swiftly run swift test --filter AppSourceTests`, and `swiftly run swift test` passed; no repo lint tooling/config was found. After adding the Swift DocC plugin dependency, `swiftly run swift package generate-documentation --target GStreamer --warnings-as-errors` also runs and generates the documentation archive. The remaining console warnings are SwiftPM/pkg-config `-Wl,-rpath` warnings from the local GStreamer install, not DocC content warnings.
- Related work: `docs/ADRs/ADR-001-invalid-input-error-taxonomy.md`.

## Goals

- Add `GStreamerError.invalidArgument(parameter: String, reason: String)` using ADR-001 Option C.
- Migrate existing `AppSource` caller-input validation from `bufferMapFailed` to `invalidArgument`.
- Preserve `bufferMapFailed` for real buffer map/read/write failures, GStreamer buffer allocation/wrapping failures, and rare Swift unsafe-buffer nil-`baseAddress` ABI corners.
- Update public DocC comments so `GStreamerError` and `AppSource` throw documentation match the new semantics.
- Update tests to assert structurally on `invalidArgument` without matching free-form reason strings.
- Add release notes that treat the new public enum case as an API cleanup compatibility change for SwiftPM source-package clients.

## User Stories

### US-001: Add `invalidArgument(parameter:reason:)`

**Description:** As an implementer, I need a structured public error case on `GStreamerError` so caller-input validation has a precise taxonomy target.

**Acceptance Criteria:**
- [x] Add `case invalidArgument(parameter: String, reason: String)` to `GStreamerError` in `Sources/GStreamer/Errors.swift`.
- [x] Extend `description` so the new case returns exactly `Invalid argument '<parameter>': <reason>`.
- [x] DocC for the new case explains that it is for caller-side validation only, not genuine GStreamer mapping/allocation failure.
- [x] DocC states that `reason` is diagnostic and non-contractual; callers should branch on the enum case and `parameter`, not parse `reason`.
- [x] Typecheck and lint pass.

### US-002: Update `GStreamerError` DocC Topics

**Description:** As a library user reading `GStreamerError` docs, I need topic grouping and error prose that reflect the post-cleanup taxonomy.

**Acceptance Criteria:**
- [x] Add a `### Validation Errors` group to the file-level `## Topics` block in `Sources/GStreamer/Errors.swift`.
- [x] List `invalidArgument(parameter:reason:)` under the new Validation Errors group.
- [x] Rewrite the `bufferMapFailed` doc-comment to describe all retained public meanings: real buffer map/read/write failures, GStreamer buffer allocation/wrapping failures, and rare Swift unsafe-buffer nil-`baseAddress` ABI corners.
- [x] Remove any wording implying caller input validation uses `bufferMapFailed`.
- [x] DocC build introduces zero new warnings.
- [x] Typecheck and lint pass.

### US-003: Update `AppSource` Method Throw Docs

**Description:** As a caller reading `AppSource` symbol docs, I need each push API to document the actual errors it can throw after the taxonomy cleanup.

**Acceptance Criteria:**
- [x] Update public `push(data: [UInt8], pts:duration:)`, `push(data: Span<UInt8>, pts:duration:)`, `push(data: RawSpan, pts:duration:)`, and `push(bytes:count:pts:duration:)` `- Throws:` docs.
- [x] Update all three public `pushVideoFrame` overload `- Throws:` docs.
- [x] Throw docs mention `invalidArgument` for invalid caller input, `bufferMapFailed` for low-level buffer/ABI failure, and `pushFailed` for appsrc rejection.
- [x] Remove the current stale `stateChangeFailed` throw wording from these methods.
- [x] DocC build introduces zero new warnings.
- [x] Typecheck and lint pass.

### US-004: Migrate `pushPayload` Validation

**Description:** As a caller of `AppSource.push(...)`, I want negative byte counts and missing positive-length payload pointers to throw a precise validation error.

**Acceptance Criteria:**
- [x] In `Sources/GStreamer/AppSource.swift` `pushPayload(...)`, replace the `count < 0` `bufferMapFailed` throw with `GStreamerError.invalidArgument(parameter: "count", reason: "AppSource push requires a non-negative count")`.
- [x] In the same function, replace the positive-count nil payload throw with `GStreamerError.invalidArgument(parameter: "bytes", reason: "AppSource push requires payload bytes when count > 0")`.
- [x] Keep the nil `swift_gst_buffer_new_wrapped_full` result on `bufferMapFailed`.
- [x] Zero-length pushes still succeed.
- [x] Successful positive-length pushes preserve existing timestamp and duration behavior.
- [x] Appsrc flow failures still throw `pushFailed`.
- [x] Typecheck and lint pass.

### US-005: Migrate `pushVideoFrame` Payload Size Validation

**Description:** As a caller of `AppSource.pushVideoFrame(...)`, I want too-small pixel payloads to throw `invalidArgument` instead of `bufferMapFailed`.

**Acceptance Criteria:**
- [x] In all three `pushVideoFrame` overloads (`[UInt8]`, `Span<UInt8>`, `RawSpan`), replace the too-small data check with `GStreamerError.invalidArgument(parameter: "data", reason: "pushVideoFrame requires at least \(expectedSize) bytes for \(width)x\(height) \(format)")`.
- [x] The reason string includes the actual `expectedSize`, `width`, `height`, and `format`.
- [x] Success-path behavior is unchanged.
- [x] Typecheck and lint pass.

### US-006: Migrate `expectedVideoPayloadByteCount` Validation

**Description:** As an implementer, I need the helper that computes expected frame byte counts to use `invalidArgument` for invalid dimensions, unsupported formats, and overflow.

**Acceptance Criteria:**
- [x] Non-positive `width` throws `invalidArgument(parameter: "width", reason: ...)`.
- [x] Non-positive `height` throws `invalidArgument(parameter: "height", reason: ...)`.
- [x] `format.bytesPerPixel <= 0` throws `invalidArgument(parameter: "format", reason: ...)`.
- [x] Width-height multiplication overflow throws `invalidArgument(parameter: "dimensions", reason: ...)`.
- [x] Pixel-count-times-bytes-per-pixel overflow throws `invalidArgument(parameter: "dimensions", reason: ...)`.
- [x] Overflow reason strings name the `width`, `height`, and `format`.
- [x] Typecheck and lint pass.

### US-007: Update Validation Tests

**Description:** As an implementer, I need invalid-input tests to assert on the new structured case without coupling to diagnostic prose.

**Acceptance Criteria:**
- [x] Update `Tests/SwiftGStreamerTests/AppSourceTests.swift` tests that currently expect `bufferMapFailed` for caller-input validation.
- [x] Assertions match structurally on `.invalidArgument(let parameter, _)`.
- [x] Assertions verify the expected `parameter` value only, not the `reason` text.
- [x] Cover negative byte count (`count`), too-small video data (`data`), zero/negative width (`width`), zero/negative height (`height`), zero-BPP unknown format (`format`), and overflow-sized dimensions (`dimensions`).
- [x] No migrated validation test still expects `bufferMapFailed`.
- [x] Typecheck and lint pass.

### US-008: Preserve `bufferMapFailed` Coverage Intent

**Description:** As an implementer, I need the remaining `bufferMapFailed` semantics to stay intentional and documented.

**Acceptance Criteria:**
- [x] Search all tests for `bufferMapFailed`.
- [x] Keep or adjust only assertions that target true map/allocation/wrapping/ABI failure behavior.
- [x] If Category 3 nil-`baseAddress` behavior cannot be triggered reliably, document that as a known coverage gap in the PR description.
- [x] If Category 4 buffer wrapping/allocation failure cannot be triggered reliably, document that as a known coverage gap in the PR description.
- [x] Do not add brittle tests that require unreliable system memory or ABI behavior.
- [x] Typecheck and lint pass.

### US-009: Add Release Notes

**Description:** As a downstream caller, I need release notes that explain the new error case, migrated APIs, narrowed `bufferMapFailed` meaning, and source compatibility impact.

**Acceptance Criteria:**
- [x] If the repository still has no `CHANGELOG*` or `RELEASE_NOTES*` file at implementation time, create `CHANGELOG.md`.
- [x] Add a Next/API-cleanup entry summarizing `GStreamerError.invalidArgument(parameter:reason:)`.
- [x] Link to `docs/ADRs/ADR-001-invalid-input-error-taxonomy.md`.
- [x] List the migrated `AppSource` entry points.
- [x] State that `bufferMapFailed` remains but is narrowed to low-level buffer map/read/write, allocation/wrapping, and ABI-corner failures.
- [x] State that adding a public enum case can require SwiftPM source-package clients with exhaustive `switch`es over `GStreamerError` to update those switches on recompilation.
- [x] Typecheck and lint pass.

## Functional Requirements

- **FR-1:** The system must expose `GStreamerError.invalidArgument(parameter: String, reason: String)`.
- **FR-2:** `GStreamerError.description` must produce exactly `Invalid argument '<parameter>': <reason>` for `invalidArgument`.
- **FR-3:** `invalidArgument` docs must identify it as caller-side validation only.
- **FR-4:** `bufferMapFailed` docs must describe all retained non-validation meanings across the public API, including non-AppSource `Buffer` and `VideoFrame` uses.
- **FR-5:** Public `AppSource` push and video-frame push method docs must accurately list `invalidArgument`, `bufferMapFailed`, and `pushFailed` where applicable.
- **FR-6:** `pushPayload` must throw `invalidArgument(parameter: "count", ...)` for negative counts.
- **FR-7:** `pushPayload` must throw `invalidArgument(parameter: "bytes", ...)` for positive counts with no payload pointer.
- **FR-8:** `pushVideoFrame` overloads must throw `invalidArgument(parameter: "data", ...)` for too-small payloads.
- **FR-9:** `expectedVideoPayloadByteCount` must throw `invalidArgument` with parameters `width`, `height`, `format`, or `dimensions` for its current validation and overflow failures.
- **FR-10:** Nil unsafe-buffer `baseAddress` paths and nil `swift_gst_buffer_new_wrapped_full` must continue to throw `bufferMapFailed`.
- **FR-11:** Zero-length pushes must continue to push one zero-length buffer successfully.
- **FR-12:** Appsrc flow failures must continue to throw `pushFailed`.
- **FR-13:** Tests for migrated validation failures must assert structurally on the enum case and `parameter`, never on `reason`.
- **FR-14:** The release note must describe the SwiftPM source compatibility impact without claiming it is only a warnings-as-errors issue.

## Non-Goals (Out of Scope)

- **NG-1:** Adding `LocalizedError` conformance.
- **NG-2:** Introducing per-API nested error types, such as `AppSource.Error`.
- **NG-3:** Renaming or removing `bufferMapFailed`.
- **NG-4:** Changing behavior of `bufferMapFailed` throw sites outside `AppSource`.
- **NG-5:** Adding new validation beyond existing validation and overflow checks.
- **NG-6:** Changing SwiftPM package settings or enabling library evolution/build-for-distribution.
- **NG-7:** Refactoring unrelated `GStreamerError` cases or unrelated DocC topics.

## Design Considerations

- **Use ADR-001 Option C.** The implementation uses `invalidArgument(parameter:reason:)`, not the fallback `invalidArgument(String)`, unless release planning explicitly reverses ADR-001.
- **Parameter is stable enough for branching.** Tests and callers may branch on `parameter`; reason strings are human-facing diagnostics and may change.
- **Compatibility messaging must be conservative.** This SwiftPM package does not currently enable library evolution in `Package.swift`, so release notes must call out possible exhaustive-switch source updates for source-package clients.
- **Do not narrow global docs to AppSource only.** `bufferMapFailed` remains relevant to `Buffer` and `VideoFrame`, so global error documentation must describe the broader public meaning.

## Technical Considerations

- Primary source changes are expected in `Sources/GStreamer/Errors.swift` and `Sources/GStreamer/AppSource.swift`.
- Primary runtime test changes are expected in `Tests/SwiftGStreamerTests/AppSourceTests.swift`.
- Add static API safety coverage only if it is useful to enforce the new public API or DocC expectations.
- Verification commands:
  - `swiftly run swift build`
  - `swiftly run swift test --filter AppSourceTests`
  - `swiftly run swift test`
  - `swiftly run swift package generate-documentation` if the DocC plugin/tooling is available
- If GStreamer system dependencies or DocC tooling are unavailable, report skipped verification with the exact reason.

## Success Metrics

- `rg "GStreamerError.bufferMapFailed" Sources/GStreamer/AppSource.swift` returns only nil unsafe-buffer `baseAddress` paths and nil `swift_gst_buffer_new_wrapped_full`.
- Every AppSource validation test that previously expected `bufferMapFailed` now expects `invalidArgument` structurally.
- `bufferMapFailed` documentation accurately covers retained public meanings across `AppSource`, `Buffer`, and `VideoFrame`.
- `swiftly run swift build` and `swiftly run swift test` pass in an environment with required GStreamer system dependencies.
- DocC generation introduces zero new warnings when DocC tooling is available.

## Open Questions

- **Release coordination with RFC-001:** Completed in the shared release notes for the reliability/API cleanup work.
- **Coverage of low-level buffer failures:** Category 3 and Category 4 `bufferMapFailed` paths may be difficult to trigger deterministically; document any remaining coverage gap in the PR description rather than adding brittle tests.
