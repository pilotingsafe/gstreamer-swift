/// A scoped borrowed GStreamer dynamic plugin context.
///
/// Values of this type are valid only for the synchronous
/// ``GStreamer/withDynamicPluginContext(rawPlugin:_:)`` body that receives
/// them. Store native element state in element instances, not in this context.
public struct NativeElementDynamicPluginContext: ~Copyable {
    internal let rawPlugin: OpaquePointer

    init(rawPlugin: OpaquePointer) {
        self.rawPlugin = rawPlugin
    }
}

extension GStreamer {
    /// Runs a synchronous dynamic plugin registration body with a borrowed plugin pointer.
    ///
    /// Use this from a `GST_PLUGIN_DEFINE` init callback. This helper does not
    /// initialize GStreamer and does not register a static plugin; the supplied
    /// pointer is borrowed from GStreamer for the duration of `body`.
    public static func withDynamicPluginContext<R>(
        rawPlugin: OpaquePointer,
        _ body: (borrowing NativeElementDynamicPluginContext) throws -> R
    ) rethrows -> R {
        let context = NativeElementDynamicPluginContext(rawPlugin: rawPlugin)
        return try body(context)
    }

    /// Registers Swift-backed native element factories into a borrowed dynamic plugin.
    ///
    /// Call this only from a synchronous dynamic plugin init callback that has
    /// received `plugin` through ``withDynamicPluginContext(rawPlugin:_:)``.
    /// The API validates the complete group before any factory registration
    /// attempt and registers each entry against the borrowed non-null plugin.
    public static func registerDynamicPluginElements(
        into plugin: borrowing NativeElementDynamicPluginContext,
        @NativeElementPluginBuilder elements: () -> [NativeElementPluginEntry]
    ) throws {
        let registrations = try NativeStaticPluginRegistration.validate(elements())
        try NativeStaticPluginContext.registerElements(registrations, plugin: plugin.rawPlugin)
    }
}
