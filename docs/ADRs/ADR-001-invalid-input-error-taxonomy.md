# ADR-001: Invalid Input Error Taxonomy for AppSource and Future APIs

**Status:** Accepted, Implemented, Updated
**Date:** 2026-05-08
**Accepted:** 2026-05-08
**Implemented:** 2026-05-08
**Updated:** 2026-05-11
**Related work:** `tasks/prd-invalid-argument-error-taxonomy.md`, `tasks/prd-gstreamer-bridge-safety-fixes.md`
**Decision owner:** TBD
**Scope:** Public error taxonomy, `GStreamerError`, invalid user input handling

## Decision Needed

Which public error case should represent invalid appsrc input, instead of continuing to throw `GStreamerError.bufferMapFailed` for negative byte counts or missing positive-length payload pointers?

## Pre-Implementation Behavior

The safety fix branch validates all public `AppSource` push entry points:

- `push(data: [UInt8], pts:duration:)`
- `push(data: Span<UInt8>, pts:duration:)`
- `push(data: RawSpan, pts:duration:)`
- `push(bytes:count:pts:duration:)`
- `pushVideoFrame(data:width:height:format:pts:duration:)` (three overloads: `[UInt8]`, `Span<UInt8>`, `RawSpan`)

Zero-length raw buffers are valid and push a zero-length GStreamer buffer. `Buffer(data: [])` is also valid.

Before this API cleanup, `GStreamerError.bufferMapFailed` was overloaded across four distinct semantic categories within `AppSource` alone:

| # | Trigger site | True semantic | Cleanup target |
|---|---|---|---|
| 1 | `count < 0` and "positive `count` with nil/missing payload pointer" in `pushPayload` | Caller-side argument validation | New invalid-argument case |
| 2 | `data.count < expectedSize` in all three `pushVideoFrame` overloads | Caller-side argument validation (dimensions/payload size) | New invalid-argument case |
| 3 | `withUnsafeBytes` / `withUnsafeBufferPointer` returning a `nil` `baseAddress` in the `[UInt8]` / `Span` / `RawSpan` push overloads | Swift/ABI corner case; not a user error and not a GStreamer mapping failure | Out of scope; keep `bufferMapFailed` (or rename to a more accurate internal-inconsistency case in a future cleanup) |
| 4 | `swift_gst_buffer_new_wrapped_full` returning `nil` | Genuine GStreamer buffer allocation failure | Keep `bufferMapFailed` (this is its intended semantic) |

Categories 1 and 2 were both **caller input validation** and already existed in shipping code (`pushVideoFrame` size validation was not hypothetical). Category 3 is a rare ABI/runtime edge that callers cannot prevent. Category 4 is the only case where the name `bufferMapFailed` is semantically correct.

The earlier consolidation under `bufferMapFailed` was an intentional compatibility compromise on the safety branch. It avoided adding a new public enum case while preventing runtime traps. It was not an indication that the underlying taxonomy problem had not yet ripened &mdash; it had.

## Problem

`bufferMapFailed` is not semantically precise for invalid user input. It describes a failure to map buffer memory, while negative counts and missing positive-length payload pointers are caller-side argument validation failures.

This creates three issues:

1. **Error meaning is misleading.** Users may believe GStreamer failed to map memory, when the actual problem is an invalid argument.
2. **Callers cannot cleanly distinguish invalid input from low-level buffer failures.**
3. **Future APIs may need the same concept.** AppSource is unlikely to be the only API that needs to reject invalid parameters.

## Decision Criteria

Use a new public error case if at least one of the following becomes true:

- More than one public API needs to report invalid caller input.
- Documentation repeatedly has to explain that `bufferMapFailed` also means invalid input.
- Users need to `catch` invalid input separately from low-level GStreamer or buffer mapping failures.
- The project is preparing a release that can tolerate a public error taxonomy cleanup.
- The repository adopts stricter API semantics around argument validation.

## Options

### Option A: Keep using `GStreamerError.bufferMapFailed`

```swift
guard count >= 0 else {
    throw GStreamerError.bufferMapFailed
}
guard count == 0 || payloadBytes != nil else {
    throw GStreamerError.bufferMapFailed
}
```

**Pros**

- No new public enum case.
- Minimal compatibility risk.
- Current branch already implements and tests this behavior.

**Cons**

- Semantically inaccurate.
- Makes precise error handling difficult.
- May accumulate more overloaded meanings over time.

### Option B: Add a general invalid argument case

```swift
public enum GStreamerError: Error, Sendable, CustomStringConvertible {
    case invalidArgument(String)
}
```

Example use:

```swift
guard count >= 0 else {
    throw GStreamerError.invalidArgument("AppSource push requires a non-negative count")
}
guard count == 0 || payloadBytes != nil else {
    throw GStreamerError.invalidArgument("AppSource push requires payload bytes when count > 0")
}
```

**Pros**

- General enough for AppSource, Caps, Buffer, builders, and future APIs.
- Simple public API.
- Easy to describe and catch.

**Cons**

- Adds a public enum case.
- Clients using exhaustive `switch` over `GStreamerError` may need updates when recompiling.
- Associated string is less structured for programmatic handling.

### Option C: Add a structured invalid argument case

```swift
public enum GStreamerError: Error, Sendable, CustomStringConvertible {
    case invalidArgument(parameter: String, reason: String)
}
```

Example use:

```swift
throw GStreamerError.invalidArgument(
    parameter: "count",
    reason: "AppSource push requires a non-negative count"
)
```

**Pros**

- More precise and machine-readable.
- Better for diagnostics and tests.

**Cons**

- More API surface.
- Slightly more verbose.
- May be overkill unless many APIs need structured validation errors.

### Option D: Add an appsrc-specific case

```swift
case invalidAppSourceInput
```

**Pros**

- Very clear for AppSource-specific validation.

**Cons**

- Too narrow.
- Does not scale to other invalid argument cases.
- Likely to fragment the error taxonomy.

## Recommendation

Do not change the safety branch retroactively. Keep `GStreamerError.bufferMapFailed` there because that branch documented it as a compatibility compromise and verified the behavior.

For this API cleanup release, use **Option C**:

```swift
case invalidArgument(parameter: String, reason: String)
```

Rationale for picking C over B:

- The pre-implementation code already validated **at least three distinct parameters** (`count`, payload pointer, `data.count` against `expectedVideoPayloadByteCount`) under what became `invalidArgument`. The "many APIs need structured validation" precondition for C was satisfied, not hypothetical.
- Tests can match structurally (`#expect(error == .invalidArgument(parameter: "count", reason: _))`) instead of asserting on free-form strings, which is the only practical way to keep validation tests stable across release notes wording changes.
- Migrating from `bufferMapFailed` to **any** new case is itself a one-shot taxonomy break; doing it at structured granularity costs the same compatibility budget as the unstructured form.

Use **Option B** only as a minimal-increment fallback if the release explicitly cannot afford structured associated values:

```swift
case invalidArgument(String)
```

Avoid an appsrc-specific error case (Option D) unless there is a strong reason to model appsrc validation separately from the rest of the library.

## Decision

**Accepted and implemented.**

The taxonomy problem was real and ripe: `bufferMapFailed` was overloaded across four semantically distinct categories in AppSource before this cleanup (see *Pre-Implementation Behavior*), and the trigger condition listed in *Decision Criteria* &mdash; "more than one public API needs to report invalid caller input" &mdash; was already satisfied.

Implementation was deferred from the safety branch because that branch deliberately spent its compatibility budget on safety fixes only. This API cleanup release now adds the new public `GStreamerError` case and announces it in release notes.

This API cleanup release adopts:

```swift
GStreamerError.invalidArgument(parameter: String, reason: String)
```

AppSource caller-side validation now uses `invalidArgument`. `bufferMapFailed` remains for real buffer map/read/write failures, GStreamer buffer allocation or wrapping failures, and rare Swift unsafe-buffer nil-`baseAddress` ABI corners.

`GStreamerError.invalidArgument(String)` remains documented above only as the rejected minimal-increment fallback.

## Compatibility Impact

This package is consumed as SwiftPM source and does not currently enable library evolution. Adding a public enum case can require SwiftPM source-package clients with exhaustive `switch`es over `GStreamerError` to update those switches when recompiling.

The most likely affected code is an exhaustive `switch` that handles every existing `GStreamerError` case and has no `default` or `@unknown default`. Callers with a catch-all branch should not need source changes for this case addition.

Example affected code:

```swift
switch error {
case .bufferMapFailed:
    ...
case .pushFailed:
    ...
// no default — compiler already warns this is fragile
}
```

Mitigation options:

- Announce the change in release notes so callers exhaustively switching on `GStreamerError` can plan source updates.
- Recommend `@unknown default` in downstream code, which is the official Swift idiom for non-frozen enums.
- Bundle this taxonomy change into an API cleanup release so callers can address other warnings in the same pass.

## Implementation Summary

Implemented in this API cleanup release:

1. Added the new case to `GStreamerError` in `Sources/GStreamer/Errors.swift` and extended `description`.
2. Updated the doc-comment **Topics** organization in `Errors.swift`:
   - Added a new `### Validation Errors` group that lists `invalidArgument(parameter:reason:)`.
   - Rewrote the doc-comment for `bufferMapFailed` so its prose matches its post-cleanup semantic (genuine `gst_buffer_map` / `swift_gst_buffer_new_wrapped_full` failure), and removed language implying that it covers caller input mistakes.
3. Migrated **all** Category 1 and Category 2 sites in `Sources/GStreamer/AppSource.swift` from `bufferMapFailed` to the new case &mdash; this includes both `pushPayload` argument validation and the `pushVideoFrame` size checks across the `[UInt8]` / `Span` / `RawSpan` overloads.
4. Audited `expectedVideoPayloadByteCount(width:height:format:)` and migrated its invalid dimension, format, and overflow failures to `invalidArgument`.
5. Left Category 3 (`withUnsafeBytes` returning a `nil` `baseAddress`) and Category 4 (`swift_gst_buffer_new_wrapped_full` returning `nil`) on `bufferMapFailed`. These are not caller input errors.
6. Updated tests to assert the precise error structurally by parameter, not via free-form reason string matching.
7. Added migration notes to the release.
8. Deferred adopting `LocalizedError` on `GStreamerError`; it is not required by this ADR.

Example (Option C form, recommended):

```swift
case invalidArgument(parameter: String, reason: String)

case .invalidArgument(let parameter, let reason):
    return "Invalid argument '\(parameter)': \(reason)"
```

AppSource (`pushPayload`):

```swift
guard count >= 0 else {
    throw GStreamerError.invalidArgument(
        parameter: "count",
        reason: "AppSource push requires a non-negative count"
    )
}
guard count == 0 || payloadBytes != nil else {
    throw GStreamerError.invalidArgument(
        parameter: "bytes",
        reason: "AppSource push requires payload bytes when count > 0"
    )
}
```

AppSource (`pushVideoFrame`):

```swift
guard data.count >= expectedSize else {
    throw GStreamerError.invalidArgument(
        parameter: "data",
        reason: "pushVideoFrame requires at least \(expectedSize) bytes for \(width)x\(height) \(format)"
    )
}
```

If Option B is chosen instead, collapse the `parameter:reason:` pair into a single string at each call site.

## Tests Required

- [x] Zero-length `[UInt8]`, `Span<UInt8>`, and `RawSpan` pushes remain valid.
- [x] `Buffer(data: [])` remains valid.
- [x] `push(bytes:count:)` with `count < 0` throws the new invalid argument error.
- [x] Positive-length push paths with a nil or missing payload pointer throw the new invalid argument error.
- [x] Positive-length pushes preserve existing timestamp and push behavior.
- [x] Existing `bufferMapFailed` tests still cover true map/allocation failures where applicable.

## Resolved Questions

These started as open questions and are resolved as part of accepting this ADR.

- **Plain string vs structured.** Resolved in favor of structured `parameter:reason:` (Option C). See *Recommendation*.
- **`pushVideoFrame` dimension validation.** Already overloaded onto `bufferMapFailed` in pre-implementation shipping code (Category 2 in *Pre-Implementation Behavior*); migrated to the new `invalidArgument` case as part of the same cleanup.

## Deferred Questions

- Whether invalid input should remain a top-level `GStreamerError` case or move to a nested per-API error type. Current direction is to keep it on `GStreamerError` for symmetry with the rest of the taxonomy; revisit only if per-API error types are introduced elsewhere.
- Whether to adopt `LocalizedError` on `GStreamerError` in a future cleanup.
