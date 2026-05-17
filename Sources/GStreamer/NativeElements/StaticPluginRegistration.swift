import CGStreamer
import CGStreamerBaseShim
import CGStreamerShim
import Synchronization

/// A Swift-backed native element entry for grouped static plugin registration.
public enum NativeElementPluginEntry: Sendable {
    case baseSink(SwiftBaseSinkElement)
    case baseTransform(SwiftBaseTransformElement)
    case baseTransformOutOfPlace(SwiftBaseTransformOutOfPlaceElement)
}

/// Builds grouped Swift-backed native element entries for static plugin registration.
@resultBuilder
public enum NativeElementPluginBuilder {
    public static func buildExpression(
        _ expression: SwiftBaseSinkElement
    ) -> [NativeElementPluginEntry] {
        [.baseSink(expression)]
    }

    public static func buildExpression(
        _ expression: SwiftBaseTransformElement
    ) -> [NativeElementPluginEntry] {
        [.baseTransform(expression)]
    }

    public static func buildExpression(
        _ expression: SwiftBaseTransformOutOfPlaceElement
    ) -> [NativeElementPluginEntry] {
        [.baseTransformOutOfPlace(expression)]
    }

    public static func buildExpression(
        _ expression: NativeElementPluginEntry
    ) -> [NativeElementPluginEntry] {
        [expression]
    }

    public static func buildBlock(
        _ components: [NativeElementPluginEntry]...
    ) -> [NativeElementPluginEntry] {
        components.flatMap { $0 }
    }

    public static func buildOptional(
        _ component: [NativeElementPluginEntry]?
    ) -> [NativeElementPluginEntry] {
        component ?? []
    }

    public static func buildEither(
        first component: [NativeElementPluginEntry]
    ) -> [NativeElementPluginEntry] {
        component
    }

    public static func buildEither(
        second component: [NativeElementPluginEntry]
    ) -> [NativeElementPluginEntry] {
        component
    }

    public static func buildArray(
        _ components: [[NativeElementPluginEntry]]
    ) -> [NativeElementPluginEntry] {
        components.flatMap { $0 }
    }
}
extension GStreamer {
    /// Registers a process-local GStreamer static plugin containing Swift-backed native elements.
    ///
    /// The registration is private to the current process. It does not produce
    /// a dynamic plugin file and does not make Swift factories discoverable by
    /// a separate `gst-inspect-1.0` process.
    public static func registerStaticPlugin(
        name: String,
        description: String,
        version: String,
        license: String,
        source: String = "gstreamer-swift",
        package: String,
        origin: String,
        @NativeElementPluginBuilder elements: () -> [NativeElementPluginEntry]
    ) throws {
        try ensureInitialized()

        let metadata = try NativeStaticPluginMetadata(
            name: name,
            description: description,
            version: version,
            license: license,
            source: source,
            package: package,
            origin: origin
        )
        let registrations = try NativeStaticPluginRegistration.validate(elements())
        let context = NativeStaticPluginContext(metadata: metadata, entries: registrations)

        let opaqueContext = Unmanaged.passRetained(context).toOpaque()
        NativeElementRegistrationTestHooks.recordStaticPluginContextRetain()
        defer {
            NativeElementRegistrationTestHooks.recordStaticPluginContextRelease()
            Unmanaged<NativeStaticPluginContext>.fromOpaque(opaqueContext).release()
        }

        NativeElementRegistrationTestHooks.recordStaticPluginCRegistrationAttempt(metadata)

        var errorMessage: UnsafeMutablePointer<CChar>?
        let registered = metadata.withCStrings { name, description, version, license, source, package, origin in
            swift_gst_register_static_plugin(
                name,
                description,
                version,
                license,
                source,
                package,
                origin,
                swiftGstStaticPluginInit,
                opaqueContext,
                &errorMessage
            ) != 0
        }

        let cMessage = GLibString.takeOwnership(errorMessage)
        guard registered else {
            throw GStreamerError.initializationFailed(
                context.initializationError
                    ?? cMessage
                    ?? "Unknown static plugin registration failure"
            )
        }
    }
}
internal struct NativeStaticPluginMetadata: Sendable {
    var name: String
    var description: String
    var version: String
    var license: String
    var source: String
    var package: String
    var origin: String

    init(
        name: String,
        description: String,
        version: String,
        license: String,
        source: String,
        package: String,
        origin: String
    ) throws {
        self.name = try Self.validatedMetadataValue(name, parameter: "name")
        self.description = try Self.validatedMetadataValue(description, parameter: "description")
        self.version = try Self.validatedMetadataValue(version, parameter: "version")
        self.license = try Self.validatedMetadataValue(license, parameter: "license")
        self.source = try Self.validatedMetadataValue(source, parameter: "source")
        self.package = try Self.validatedMetadataValue(package, parameter: "package")
        self.origin = try Self.validatedMetadataValue(origin, parameter: "origin")
        try Self.validatePluginName(self.name)
    }

    func withCStrings<R>(
        _ body: (
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>,
            UnsafePointer<CChar>
        ) -> R
    ) -> R {
        name.withCString { name in
            description.withCString { description in
                version.withCString { version in
                    license.withCString { license in
                        source.withCString { source in
                            package.withCString { package in
                                origin.withCString { origin in
                                    body(name, description, version, license, source, package, origin)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func validatedMetadataValue(_ value: String, parameter: String) throws -> String {
        let trimmed = value.trimmingWhitespace()
        guard !trimmed.isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: parameter,
                reason: "\(parameter) must not be empty"
            )
        }
        return trimmed
    }

    private static func validatePluginName(_ name: String) throws {
        guard let first = name.unicodeScalars.first, first.isASCIIAlphaNumeric else {
            throw GStreamerError.invalidArgument(
                parameter: "name",
                reason: "name must start with an ASCII letter or digit"
            )
        }
        guard name.unicodeScalars.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == "_" || $0 == "-" }) else {
            throw GStreamerError.invalidArgument(
                parameter: "name",
                reason: "name may contain only ASCII letters, digits, '_' or '-'"
            )
        }
    }
}

internal enum NativeStaticPluginEntry {
    case baseSink(SwiftBaseSinkElement, ValidatedBaseSinkRegistration)
    case baseTransform(SwiftBaseTransformElement, ValidatedBaseTransformRegistration)
    case baseTransformOutOfPlace(
        SwiftBaseTransformOutOfPlaceElement,
        ValidatedBaseTransformOutOfPlaceRegistration
    )

    var factoryName: String {
        switch self {
        case .baseSink(_, let registration):
            registration.factoryName
        case .baseTransform(_, let registration):
            registration.factoryName
        case .baseTransformOutOfPlace(_, let registration):
            registration.factoryName
        }
    }

    var typeName: String {
        switch self {
        case .baseSink(_, let registration):
            registration.typeName
        case .baseTransform(_, let registration):
            registration.typeName
        case .baseTransformOutOfPlace(_, let registration):
            registration.typeName
        }
    }
}

internal enum NativeStaticPluginRegistration {
    static func validate(
        _ entries: [NativeElementPluginEntry],
        allowingExistingFactoriesOwnedBy allowedPluginName: String? = nil
    ) throws -> [NativeStaticPluginEntry] {
        guard !entries.isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: "elements",
                reason: "static plugin must contain at least one native element"
            )
        }

        let registrations = try entries.map { entry in
            switch entry {
            case .baseSink(let element):
                return NativeStaticPluginEntry.baseSink(
                    element,
                    try NativeElementRegistration.validateBaseSink(element)
                )
            case .baseTransform(let element):
                return NativeStaticPluginEntry.baseTransform(
                    element,
                    try NativeElementRegistration.validateBaseTransform(element)
                )
            case .baseTransformOutOfPlace(let element):
                return NativeStaticPluginEntry.baseTransformOutOfPlace(
                    element,
                    try NativeElementRegistration.validateBaseTransformOutOfPlace(element)
                )
            }
        }

        try preflightNames(registrations, allowingExistingFactoriesOwnedBy: allowedPluginName)
        return registrations
    }

    private static func preflightNames(
        _ registrations: [NativeStaticPluginEntry],
        allowingExistingFactoriesOwnedBy allowedPluginName: String?
    ) throws {
        var factoryNames = Set<String>()
        var typeNames = Set<String>()

        for registration in registrations {
            guard factoryNames.insert(registration.factoryName).inserted else {
                throw GStreamerError.invalidArgument(
                    parameter: "factoryName",
                    reason: "duplicate native element factory name '\(registration.factoryName)'"
                )
            }
            guard typeNames.insert(registration.typeName).inserted else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "duplicate native element GType name '\(registration.typeName)'"
                )
            }
            guard !factoryNameIsRegistered(
                registration.factoryName,
                allowingExistingOwnerPluginNamed: allowedPluginName
            ) else {
                throw GStreamerError.invalidArgument(
                    parameter: "factoryName",
                    reason: "native element factory '\(registration.factoryName)' is already registered"
                )
            }
            guard !typeNameIsRegistered(registration.typeName) else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "native element GType '\(registration.typeName)' is already registered"
                )
            }
        }
    }

    private static func factoryNameIsRegistered(
        _ factoryName: String,
        allowingExistingOwnerPluginNamed allowedPluginName: String?
    ) -> Bool {
        factoryName.withCString { factoryName in
            if let allowedPluginName,
               allowedPluginName.withCString({
                   swift_gst_element_factory_plugin_name_matches(factoryName, $0) != 0
               }) {
                return false
            }

            guard let factory = gst_element_factory_find(factoryName) else {
                return false
            }
            gst_object_unref(UnsafeMutableRawPointer(factory))
            return true
        }
    }

    private static func typeNameIsRegistered(_ typeName: String) -> Bool {
        typeName.withCString { g_type_from_name($0) != 0 }
    }
}

// Safety: GStreamer holds this retained context only across the synchronous
// static plugin registration callback. Metadata and entries are immutable after
// construction; the only mutable field is guarded by a Mutex.
internal final class NativeStaticPluginContext: @unchecked Sendable {
    let metadata: NativeStaticPluginMetadata
    private let entries: [NativeStaticPluginEntry]
    private let error = Mutex<String?>(nil)

    init(metadata: NativeStaticPluginMetadata, entries: [NativeStaticPluginEntry]) {
        self.metadata = metadata
        self.entries = entries
    }

    var initializationError: String? {
        error.withLock { $0 }
    }

    func registerElements(plugin: OpaquePointer) -> Bool {
        do {
            try Self.registerElements(entries, plugin: plugin, honorsForcedStaticFailures: true)
            return true
        } catch {
            record(error)
            return false
        }
    }

    static func registerElements(
        _ entries: [NativeStaticPluginEntry],
        plugin: OpaquePointer,
        honorsForcedStaticFailures: Bool = false
    ) throws {
        for entry in entries {
            if honorsForcedStaticFailures,
               let forcedFailure = NativeElementRegistrationTestHooks
                .forcedStaticPluginInitFailureMessage(factoryName: entry.factoryName) {
                throw GStreamerError.initializationFailed(forcedFailure)
            }

            switch entry {
            case .baseSink(let element, let registration):
                try registerBaseSink(element, registration: registration, plugin: plugin)
            case .baseTransform(let element, let registration):
                try registerBaseTransform(element, registration: registration, plugin: plugin)
            case .baseTransformOutOfPlace(let element, let registration):
                try registerBaseTransformOutOfPlace(element, registration: registration, plugin: plugin)
            }
        }
    }

    private func record(_ failure: Error) {
        let message: String
        if case GStreamerError.initializationFailed(let reason) = failure {
            message = reason
        } else {
            message = String(describing: failure)
        }
        error.withLock { $0 = message }
    }

    private static func registerBaseSink(
        _ element: SwiftBaseSinkElement,
        registration: ValidatedBaseSinkRegistration,
        plugin: OpaquePointer
    ) throws {
        let classContext = SwiftBaseSinkClassContext(element: element, properties: registration.properties)
        let propertyDescriptors = NativePropertyCDescriptorStorage(properties: registration.properties)
        var callbacks = swiftGstBaseSinkCallbacks()
        var errorMessage: UnsafeMutablePointer<CChar>?

        let registered = registration.factoryName.withCString { factoryName in
            registration.typeName.withCString { typeName in
                registration.metadata.klass.withCString { klass in
                    registration.metadata.longName.withCString { longName in
                        registration.metadata.description.withCString { description in
                            registration.metadata.author.withCString { author in
                                registration.sinkCaps.withCString { sinkCaps in
                                    var info = SwiftGstBaseSinkInfo(
                                        factory_name: factoryName,
                                        type_name: typeName,
                                        klass: klass,
                                        long_name: longName,
                                        description: description,
                                        author: author,
                                        rank: registration.metadata.rank.rawValue,
                                        sink_caps: sinkCaps,
                                        properties: propertyDescriptors.descriptors,
                                        property_count: propertyDescriptors.count
                                    )

                                    NativeElementRegistrationTestHooks
                                        .recordPluginAwareBaseSinkRegistration(pluginIsNull: false)
                                    return swift_gst_register_base_sink_for_plugin(
                                        plugin,
                                        &info,
                                        &callbacks,
                                        Unmanaged.passUnretained(classContext).toOpaque(),
                                        swiftGstBaseSinkRetainClassContext,
                                        swiftGstBaseSinkReleaseClassContext,
                                        &errorMessage
                                    ) != 0
                                }
                            }
                        }
                    }
                }
            }
        }

        guard registered else {
            let message = GLibString.takeOwnership(errorMessage) ?? "Unknown BaseSink registration failure"
            throw GStreamerError.initializationFailed(message)
        }

        _ = GLibString.takeOwnership(errorMessage)
    }

    private static func registerBaseTransform(
        _ element: SwiftBaseTransformElement,
        registration: ValidatedBaseTransformRegistration,
        plugin: OpaquePointer
    ) throws {
        let classContext = SwiftBaseTransformClassContext(element: element, properties: registration.properties)
        let propertyDescriptors = NativePropertyCDescriptorStorage(properties: registration.properties)
        var callbacks = swiftGstBaseTransformCallbacks()
        var errorMessage: UnsafeMutablePointer<CChar>?

        let registered = registration.factoryName.withCString { factoryName in
            registration.typeName.withCString { typeName in
                registration.metadata.klass.withCString { klass in
                    registration.metadata.longName.withCString { longName in
                        registration.metadata.description.withCString { description in
                            registration.metadata.author.withCString { author in
                                registration.sinkCaps.withCString { sinkCaps in
                                    registration.srcCaps.withCString { srcCaps in
                                        var info = SwiftGstBaseTransformInfo(
                                            factory_name: factoryName,
                                            type_name: typeName,
                                            klass: klass,
                                            long_name: longName,
                                            description: description,
                                            author: author,
                                            rank: registration.metadata.rank.rawValue,
                                            sink_caps: sinkCaps,
                                            src_caps: srcCaps,
                                            mode: SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE,
                                            passthrough_on_same_caps: registration
                                                .passthroughOptions
                                                .passthroughOnSameCaps ? 1 : 0,
                                            transform_ip_on_passthrough: registration
                                                .passthroughOptions
                                                .transformInPlaceOnPassthrough ? 1 : 0,
                                            properties: propertyDescriptors.descriptors,
                                            property_count: propertyDescriptors.count
                                        )

                                        NativeElementRegistrationTestHooks
                                            .recordPluginAwareBaseTransformRegistration(
                                                mode: info.mode,
                                                pluginIsNull: false
                                            )
                                        return swift_gst_register_base_transform_for_plugin(
                                            plugin,
                                            &info,
                                            &callbacks,
                                            Unmanaged.passUnretained(classContext).toOpaque(),
                                            swiftGstBaseTransformRetainClassContext,
                                            swiftGstBaseTransformReleaseClassContext,
                                            &errorMessage
                                        ) != 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard registered else {
            let message = GLibString.takeOwnership(errorMessage) ?? "Unknown BaseTransform registration failure"
            throw GStreamerError.initializationFailed(message)
        }

        _ = GLibString.takeOwnership(errorMessage)
    }

    private static func registerBaseTransformOutOfPlace(
        _ element: SwiftBaseTransformOutOfPlaceElement,
        registration: ValidatedBaseTransformOutOfPlaceRegistration,
        plugin: OpaquePointer
    ) throws {
        let classContext = SwiftBaseTransformOutOfPlaceClassContext(
            element: element,
            properties: registration.properties
        )
        let propertyDescriptors = NativePropertyCDescriptorStorage(properties: registration.properties)
        var callbacks = swiftGstBaseTransformOutOfPlaceCallbacks(options: registration.options)
        var errorMessage: UnsafeMutablePointer<CChar>?

        let registered = registration.factoryName.withCString { factoryName in
            registration.typeName.withCString { typeName in
                registration.metadata.klass.withCString { klass in
                    registration.metadata.longName.withCString { longName in
                        registration.metadata.description.withCString { description in
                            registration.metadata.author.withCString { author in
                                registration.sinkCaps.withCString { sinkCaps in
                                    registration.srcCaps.withCString { srcCaps in
                                        var info = SwiftGstBaseTransformInfo(
                                            factory_name: factoryName,
                                            type_name: typeName,
                                            klass: klass,
                                            long_name: longName,
                                            description: description,
                                            author: author,
                                            rank: registration.metadata.rank.rawValue,
                                            sink_caps: sinkCaps,
                                            src_caps: srcCaps,
                                            mode: registration.options == .general
                                                ? SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE_GENERAL
                                                : SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE,
                                            passthrough_on_same_caps: 0,
                                            transform_ip_on_passthrough: 0,
                                            properties: propertyDescriptors.descriptors,
                                            property_count: propertyDescriptors.count
                                        )

                                        NativeElementRegistrationTestHooks
                                            .recordPluginAwareBaseTransformRegistration(
                                                mode: info.mode,
                                                pluginIsNull: false
                                            )
                                        return swift_gst_register_base_transform_for_plugin(
                                            plugin,
                                            &info,
                                            &callbacks,
                                            Unmanaged.passUnretained(classContext).toOpaque(),
                                            swiftGstBaseTransformOutOfPlaceRetainClassContext,
                                            swiftGstBaseTransformOutOfPlaceReleaseClassContext,
                                            &errorMessage
                                        ) != 0
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        guard registered else {
            let message = GLibString.takeOwnership(errorMessage) ?? "Unknown BaseTransform registration failure"
            throw GStreamerError.initializationFailed(message)
        }

        _ = GLibString.takeOwnership(errorMessage)
    }
}
private func swiftGstStaticPluginInit(
    _ plugin: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) -> gboolean {
    guard let plugin, let userData else {
        return 0
    }

    let context = Unmanaged<NativeStaticPluginContext>.fromOpaque(userData).takeUnretainedValue()
    return context.registerElements(plugin: plugin) ? 1 : 0
}
