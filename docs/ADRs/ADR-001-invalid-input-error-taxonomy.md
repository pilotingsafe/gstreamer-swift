# ADR-001: Invalid Input Error Taxonomy for AppSource and Future APIs

**Status:** Proposed
**Date:** 2026-05-08
**Related work:** `GStreamerBridgeSafetyandReliabilityFixes`
**Decision owner:** TBD
**Scope:** Public error taxonomy, `GStreamerError`, invalid user input handling

## Decision Needed

Should a future release add a more semantically precise public error case for invalid appsrc input, instead of continuing to throw `GStreamerError.bufferMapFailed` for negative byte counts or missing positive-length payload pointers?

## Current Behavior

The safety fix branch validates all public `AppSource` push entry points:

- `push(data: [UInt8], pts:duration:)`
- `push(data: Span<UInt8>, pts:duration:)`
- `push(data: RawSpan, pts:duration:)`
- `push(bytes:count:pts:duration:)`

Zero-length raw buffers are valid and push a zero-length GStreamer buffer. `Buffer(data: [])` is also valid.

Invalid input currently throws `GStreamerError.bufferMapFailed`:

- `count < 0`
- positive `count` with a nil or otherwise missing payload pointer

This is an intentional compatibility compromise. It avoids adding a new public enum case while preventing runtime traps from negative counts or missing positive-length payload pointers.

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

Do not change the current safety branch. Keep `GStreamerError.bufferMapFailed` there because the branch has already documented it as a compatibility compromise and verified the behavior.

For the next API cleanup release, prefer **Option B**:

```swift
case invalidArgument(String)
```

If the project expects many validation errors or needs programmatic inspection, use **Option C** instead:

```swift
case invalidArgument(parameter: String, reason: String)
```

Avoid an appsrc-specific error case unless there is a strong reason to model appsrc validation separately from the rest of the library.

## Proposed Decision

**Deferred.**

Current release behavior remains:

```swift
GStreamerError.bufferMapFailed
```

Future release should consider:

```swift
GStreamerError.invalidArgument(String)
```

or:

```swift
GStreamerError.invalidArgument(parameter:reason:)
```

## Compatibility Impact

Adding a new public enum case can affect source compatibility for downstream users who exhaustively switch over `GStreamerError`.

Example affected code:

```swift
switch error {
case .bufferMapFailed:
    ...
case .pushFailed:
    ...
// no default
}
```

Mitigation options:

- Announce the change in release notes.
- Recommend a `default` or `@unknown default` branch where appropriate.
- If semantic correctness is prioritized, accept this as part of an API cleanup release.

## Implementation Sketch

If approved:

1. Add new case to `GStreamerError`.
2. Update `description`.
3. Update documentation topics.
4. Change invalid `AppSource` input paths from `bufferMapFailed` to the new case.
5. Update tests to assert the precise error.
6. Add migration notes.

Example:

```swift
case invalidArgument(String)

case .invalidArgument(let message):
    return "Invalid argument: \(message)"
```

AppSource:

```swift
guard count >= 0 else {
    throw GStreamerError.invalidArgument("AppSource push requires a non-negative count")
}
guard count == 0 || payloadBytes != nil else {
    throw GStreamerError.invalidArgument("AppSource push requires payload bytes when count > 0")
}
```

## Tests Required

- Zero-length `[UInt8]`, `Span<UInt8>`, and `RawSpan` pushes remain valid.
- `Buffer(data: [])` remains valid.
- `push(bytes:count:)` with `count < 0` throws the new invalid argument error.
- Positive-length push paths with a nil or missing payload pointer throw the new invalid argument error.
- Positive-length pushes preserve existing timestamp and push behavior.
- Existing `bufferMapFailed` tests still cover true map/allocation failures where applicable.

## Open Questions

- Should the error be plain string-based or structured by parameter and reason?
- Should invalid input be a `GStreamerError` case or a nested API-specific error?
- Should invalid dimensions in `pushVideoFrame` use the same error case?
