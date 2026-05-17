# Release Scope

This file summarizes the v0.2 release scope and known limitations.

## Stable Core Surface

The stable v0.2 core surface remains the low-level Swift wrapper layer:

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

## Native Elements Stability

Native Elements are available from the main `GStreamer` target in v0.2, with
stability split by workflow:

- In-process `BaseSink` registration through `SwiftBaseSinkElement` is preview
  but usable for local pipelines that register factories before constructing
  pipeline descriptions.
- In-place `BaseTransform` registration through
  `SwiftBaseTransformElement.inPlace(...)` is preview but usable for local
  pipelines that inspect or mutate callback-scoped buffers.
- Out-of-place transforms, Native Element properties, and static plugin grouping
  are experimental and may continue to evolve.
- The dynamic plugin template in `Examples/DynamicPluginTemplate` is preview.
  Validate staged plugin builds externally with `gst-inspect-1.0` and
  `gst-launch-1.0` before treating them as deployable GStreamer plugins.

## Non-Core and Experimental Layers

Source and sink builders are non-core convenience layers. They are useful when
their platform and plugin choices fit an application, but direct `Pipeline`
construction remains the stable v0.2 foundation for custom graphs.

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
