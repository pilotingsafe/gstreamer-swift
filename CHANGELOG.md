# Changelog

## Next

### Positioning

- Repositioned v0.1 compatibility around a low-level core public surface:
  `Pipeline`, `Element`, `Bus`, `AppSink`, `AppSource`, and buffer/frame
  wrappers. Source/sink builders, typed pipelines, and reliable packet delivery
  are documented as convenience or experimental layers.

### Features

- Added `Bus.messageSequence(filter:)`, a source-compatible async sequence for
  callers that want one active bus drainer without blocking Swift concurrency
  threads. The sequence now uses a private GStreamer bus watch; creating an
  iterator can drain and buffer matching `BusMessage` values before `next()` is
  awaited. The parsed-message buffer currently holds at most 256 parsed
  messages with best-effort overflow that prefers retaining ERROR and EOS over
  older noncritical messages. Existing
  `Bus.messages(filter:)`, `errors()`, `warnings()`, `stateChanges()`, and
  `waitForEOS()` behavior is unchanged. `messageSequence(filter:)` defaults to
  `.all`, which can expose more Swift-modeled message kinds than the
  `messages()` default of errors, EOS, and state changes.
- Added reliable archival audio packet delivery for local file/decode sources.
  Use `AudioSource.file(path:)` to build an `AudioFileSource`, then iterate
  `source.reliablePackets()` for a throwing, single-consumer, no-drop packet
  sequence. Existing realtime `AudioSource.packets()` behavior is unchanged and
  remains best-effort for live capture. See
  [RFC-001](docs/RFCs/RFC-001-realtime-vs-archival-packet-delivery.md).

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
