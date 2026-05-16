# Native Elements

Use Swift-backed native elements when a pipeline needs custom element behavior
implemented in Swift while staying inside the current application process.

## Phase 5: Static Plugin Grouping

Static plugin grouping registers related Swift-backed native elements under one
GStreamer static plugin metadata record. Use
``GStreamer/registerStaticPlugin(name:description:version:license:source:package:origin:elements:)``
to group ``SwiftBaseSinkElement``, ``SwiftBaseTransformElement``, and
``SwiftBaseTransformOutOfPlaceElement`` factories.

The registration is private to the current process, or to the current
application or library process that calls the API. It wraps GStreamer's static
plugin registration path and does not produce a dynamic plugin file. A separate
`gst-inspect-1.0` process will not discover these Swift factories by default.

Dynamic plugin output, plugin scanner discovery, install path handling, rpath
configuration, Swift runtime linking, and codesign support remain separate
Phase 6 scope.

```swift
try GStreamer.registerStaticPlugin(
    name: "swiftfilters",
    description: "Swift native elements",
    version: "0.1.0",
    license: "MIT",
    package: "gstreamer-swift",
    origin: "pilotingsafe"
) {
    SwiftBaseSinkElement(...)
    SwiftBaseTransformElement.inPlace(...)
    SwiftBaseTransformOutOfPlaceElement(...)
}
```

