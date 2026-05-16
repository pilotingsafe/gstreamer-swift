# Native Elements

Use Swift-backed native elements when a pipeline needs custom element behavior
implemented in Swift while staying inside the current application process.

## In-process Swift Native Elements

In-process registration is the simplest native-element workflow. Register the
Swift-backed factory with the current process, then create a pipeline
description that uses the factory name.

### SwiftBaseSinkElement

Use ``SwiftBaseSinkElement`` when Swift needs to consume buffers at the end of a
pipeline. Implement ``SwiftBaseSinkInstance/render(_:)`` to inspect each
callback-scoped ``BorrowedBuffer`` and return a ``FlowReturn``. Call
`GStreamer.register(_:)` before creating pipeline descriptions that reference
the sink factory name.

```swift
try GStreamer.register(
    SwiftBaseSinkElement(
        factoryName: "swiftbuffersink",
        metadata: NativeElementMetadata(
            klass: "Sink/Swift",
            longName: "Swift Buffer Sink",
            description: "Consumes buffers in Swift"
        ),
        sinkCaps: "video/x-raw",
        makeInstance: { BufferSinkHandler() }
    )
)
```

### SwiftBaseTransformElement.inPlace

Use `SwiftBaseTransformElement.inPlace` when Swift needs to mutate buffers
without replacing them. Implement
``SwiftBaseTransformInstance/transformInPlace(_:)`` to edit the
callback-scoped ``MutableBorrowedBuffer`` and return a ``FlowReturn``. Provide
sink and source caps, register the element with `GStreamer.register(_:)`, then
use the transform factory name in pipeline descriptions created in the same
process.

### BorrowedBuffer and MutableBorrowedBuffer Lifetime

``BorrowedBuffer`` and ``MutableBorrowedBuffer`` are valid only during the
callback that receives them. Raw pointers from `withUnsafeBytes(_:)` or
`withUnsafeMutableBytes(_:)` must not escape their closures. Use
`retainedReference()` or `deepCopy()` when data or buffers need to outlive the
callback.

### Synchronous Callback Rule

Native element callbacks run synchronously on GStreamer's streaming path. They
are not `async`, do not run on `MainActor` by default, and should avoid long
blocking CPU or I/O work. Hand off retained buffers to another queue when work
must continue after the callback returns.

### In-process Registration vs Static Plugin vs Dynamic Plugin

| Mode | API or template | Visibility |
|---|---|---|
| In-process registration | `GStreamer.register(_:)` | Simplest default. Factories are current-process only, but pipeline descriptions in that process can use them after registration. |
| Static plugin grouping | ``GStreamer/registerStaticPlugin(name:description:version:license:source:package:origin:elements:)`` | Groups multiple factories under plugin metadata. Factories are still current-process only, but pipeline descriptions in that process can use them after registration. |
| Dynamic plugin | `Examples/DynamicPluginTemplate` | Builds a plugin artifact for external GStreamer discovery. Separate `gst-inspect-1.0` and `gst-launch-1.0` processes can discover and use the factories through `GST_PLUGIN_PATH`. |

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
Plugin scanner discovery, install path handling, rpath configuration, Swift runtime
linking, and codesign are Phase 6 dynamic plugin responsibilities, not Phase 5
static plugin grouping responsibilities.

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

## Phase 6: Dynamic Plugins

Phase 6 adds a dynamic plugin workflow for Swift-backed native elements that
must be discovered by external GStreamer tools. The package-wide tested and
supported GStreamer baseline is 1.28.2 or newer.

Use `Examples/DynamicPluginTemplate` as the starting point. The template builds
a SwiftPM dynamic library named for the plugin ID, with the default artifact
names `libgstswiftnative.dylib` on macOS and `libgstswiftnative.so` on Linux.
The C target owns `GST_PLUGIN_DEFINE`, while the Swift target exports a
`swift_native_dynamic_plugin_init` function and registers Swift factories
against the `GstPlugin *` supplied by GStreamer:

```swift
@_cdecl("swift_native_dynamic_plugin_init")
public func swiftNativeDynamicPluginInit(_ rawPlugin: OpaquePointer?) -> Int32 {
    guard let rawPlugin else { return 0 }

    do {
        try GStreamer.withDynamicPluginContext(rawPlugin: rawPlugin) { plugin in
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                SwiftBaseTransformElement.inPlace(...)
            }
        }
        return 1
    } catch {
        recordStatus(rawPlugin, String(describing: error))
        return 0
    }
}
```

Do not call `GStreamer.initialize()` from this init function. Dynamic plugin
loading happens after GStreamer has supplied a borrowed plugin pointer. The
borrowed ``NativeElementDynamicPluginContext`` is noncopyable, has no public raw
pointer storage, and is valid only during the synchronous
``GStreamer/withDynamicPluginContext(rawPlugin:_:)`` body.
The template's C helper records caught Swift failures with
`gst_plugin_add_status_error` before returning `FALSE` to GStreamer.

Dynamic registration reuses the Phase 5 grouped-element validation rules. Empty
groups, invalid caps, duplicate factory names, duplicate GType names, and
already registered factories or GTypes fail before grouped registration starts.
On success, each factory is registered against the non-null dynamic plugin
owner rather than as a process-local factory.

Install into a staged install prefix first. Put the plugin library below
`<prefix>/lib/gstreamer-1.0`, put Swift runtime and private SwiftPM dynamic
libraries below a sibling Swift library directory, and leave GStreamer, GLib,
libSystem, libc, libpthread, libdl, and other platform dependencies external.
Validate with an isolated registry so stale plugin scanner cache entries do not
hide loader failures:

```bash
export GST_PLUGIN_PATH="$prefix/lib/gstreamer-1.0"
export GST_REGISTRY="$(mktemp -t swiftnative-registry.XXXXXX)"
rm -f "$GST_REGISTRY"
gst-inspect-1.0 swiftnative
gst-inspect-1.0 swiftnativeidentity
gst-launch-1.0 videotestsrc num-buffers=1 ! swiftnativeidentity ! fakesink
```

Staged installs are the default workflow and do not require `sudo`. If a
downstream deployment intentionally installs into the platform GStreamer plugin
directory, discover that directory with:

```bash
pkg-config --variable=pluginsdir gstreamer-1.0
```

Then copy `libgst<pluginID>.dylib` or `libgst<pluginID>.so` into that directory
only after the staged prefix validates successfully.

Common loader failures are missing Swift runtime libraries, missing private
SwiftPM libraries, missing external GStreamer or GLib libraries, incorrect
rpath values, stale registry blacklist entries, and macOS signing failures.
The template scripts inspect Swift target information, copy Swift libraries,
configure relative rpaths such as `@loader_path/../swift` or
`$ORIGIN/../swift`, run `codesign` on macOS after binary modifications, and
report unavailable host tools instead of claiming successful external
discovery. They resolve paths from the template directory, so they can be
invoked from another working directory; the default staged prefix is
`Examples/DynamicPluginTemplate/.stage`.
