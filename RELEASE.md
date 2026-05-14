# Release Scope

This file summarizes the v0.1 release scope and known limitations.

## Stable v0.1 Surface

The stable v0.1 surface is the low-level Swift wrapper layer:

- `Pipeline`
- `Element`
- `Bus`
- `AppSink`
- `AppSource`
- `Buffer`
- `AudioBufferSink`
- `AudioBuffer`
- `VideoFrame`

These APIs stay close to GStreamer and preserve its ownership, bus-consumption,
and backpressure model.

## Non-Core and Experimental Layers

Source and sink builders are non-core convenience layers. They are useful when
their platform and plugin choices fit an application, but direct `Pipeline`
construction remains the stable v0.1 foundation for custom graphs.

The typed pipeline DSL is experimental and non-core. Its result-builder syntax
and typed frame wrappers may continue to evolve around the stable low-level
surface.

Finite file/decode reliable delivery through `AudioFileSource.reliablePackets()`
has an explicit scoped non-core contract: each `ReliablePackets` value supports
one active consumer, throws pipeline failures, and reaches EOS through
iteration.

Reliable live delivery is experimental and non-core. It is limited to encoded
audio sources that explicitly opt into reliable delivery, and it is not lossless
under sustained slowness; the live source, driver, operating system, or
GStreamer pipeline can still impose backpressure or lose data.

## Known Limitations

- One bus drainer only.
- No bus fan-out.
- Reliable live source is not lossless under sustained slowness.
- Typed DSL is experimental.
- macOS/Linux verified only.
