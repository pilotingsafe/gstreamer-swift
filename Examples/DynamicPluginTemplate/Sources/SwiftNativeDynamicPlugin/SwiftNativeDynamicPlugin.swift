#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GStreamer
import SwiftNativeDynamicPluginEntrypoint

@_cdecl("swift_native_dynamic_plugin_init")
public func swiftNativeDynamicPluginInit(_ rawPlugin: OpaquePointer?) -> Int32 {
    swift_native_dynamic_plugin_link_anchor()

    guard let rawPlugin else {
        recordStatus(nil, "Swift native dynamic plugin received a missing GstPlugin pointer")
        return 0
    }

    do {
        if environmentVariableEquals("SWIFT_NATIVE_DYNAMIC_PLUGIN_FORCE_REGISTRATION_FAILURE", "1") {
            throw GStreamerError.initializationFailed("forced Swift dynamic plugin registration failure")
        }

        try GStreamer.withDynamicPluginContext(rawPlugin: rawPlugin) { plugin in
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                SwiftBaseTransformElement.inPlace(
                    factoryName: "swiftnativeidentity",
                    metadata: NativeElementMetadata(
                        klass: "Filter/Effect/Video",
                        longName: "Swift native identity transform",
                        description: "Pass-through Swift-backed BaseTransform from the dynamic plugin template",
                        author: "gstreamer-swift"
                    ),
                    sinkCaps: "ANY",
                    srcCaps: "ANY",
                    makeInstance: { SwiftNativeIdentityTransform() }
                )
            }
        }
        return 1
    } catch {
        recordStatus(rawPlugin, String(describing: error))
        return 0
    }
}

private func environmentVariableEquals(_ name: String, _ expectedValue: String) -> Bool {
    name.withCString { namePointer in
        guard let valuePointer = getenv(namePointer) else {
            return false
        }
        return expectedValue.withCString { strcmp(valuePointer, $0) == 0 }
    }
}

private func recordStatus(_ rawPlugin: OpaquePointer?, _ message: String) {
    message.withCString { cMessage in
        swift_native_dynamic_plugin_record_status_error(rawPlugin, cMessage)
    }
}

private final class SwiftNativeIdentityTransform: SwiftBaseTransformInstance {
    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}
