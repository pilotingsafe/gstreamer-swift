# Changelog

## Next

### Positioning

- Added v0.1 release scope notes in [RELEASE.md](RELEASE.md). v0.1 compatibility is centered on
  the low-level core public surface: `Pipeline`, `Element`, `Bus`, `AppSink`,
  `AppSource`, and buffer/frame wrappers. Source/sink builders are documented
  as non-core convenience layers, the typed pipeline DSL is experimental, finite
  file/decode reliable delivery has a scoped non-core contract, and reliable
  live delivery remains experimental/non-core; sustained slowness can still
  surface upstream or device-level loss.

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
  the [encoded packet delivery guide](Sources/GStreamer/Documentation.docc/EncodedPacketDelivery.md).

### Bugfixes

- Fixed `Queue.leaky(maxBuffers:)` to set `leaky=2` (`.downstream`) instead of the previous `leaky=1` (`.upstream`), which actually drops newest buffers despite the helper docs. The helper now drops oldest buffers, matching the docs and live-source intent. Callers that relied on drop-newest behavior should use `Queue(maxBuffers:, leaky: .upstream)` explicitly. The public QueueLeaky delivery semantics are documented in the [API contract](Sources/GStreamer/Documentation.docc/APIContract.md). `QueueLeaky` case names and raw values are unchanged.

### API Cleanup

- Added `GStreamerError.invalidArgument(parameter:reason:)` for caller-side
  validation failures.
- Migrated AppSource validation in these entry points:
  `push(bytes:count:pts:duration:)`,
  `pushVideoFrame(data:width:height:format:pts:duration:)` for `[UInt8]`,
  `Span<UInt8>`, and `RawSpan`, and the shared AppSource push internals.
- Narrowed `bufferMapFailed` to low-level buffer map, read, write,
  allocation, wrapping, and rare Swift unsafe-buffer ABI-corner failures.
- SwiftPM source-package clients with exhaustive `switch`es over
  `GStreamerError` may need to update those switches when they recompile.
