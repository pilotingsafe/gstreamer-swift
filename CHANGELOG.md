# Changelog

## Next

### Bugfixes

- Fixed `Queue.leaky(maxBuffers:)` to set `leaky=2` (`.downstream`) instead of the previous `leaky=1` (`.upstream`), which actually drops newest buffers despite the helper docs. The helper now drops oldest buffers, matching the docs and live-source intent. Callers that relied on drop-newest behavior should use `Queue(maxBuffers:, leaky: .upstream)` explicitly. The matching mapping in [RFC-002](docs/RFCs/RFC-002-live-source-reliable-delivery.md) was corrected, and `QueueLeaky` case names and raw values are unchanged.

### API Cleanup

- Added `GStreamerError.invalidArgument(parameter:reason:)` for caller-side
  validation failures. See
  [ADR-001](docs/ADRs/ADR-001-invalid-input-error-taxonomy.md).
- Migrated AppSource validation in these entry points:
  `push(bytes:count:pts:duration:)`,
  `pushVideoFrame(data:width:height:format:pts:duration:)` for `[UInt8]`,
  `Span<UInt8>`, and `RawSpan`, and the shared AppSource push internals.
- Narrowed `bufferMapFailed` to low-level buffer map, read, write,
  allocation, wrapping, and rare Swift unsafe-buffer ABI-corner failures.
- SwiftPM source-package clients with exhaustive `switch`es over
  `GStreamerError` may need to update those switches when they recompile.
