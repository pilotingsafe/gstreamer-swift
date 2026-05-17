import CGStreamer
import CGStreamerBaseShim
import CGStreamerShim
import Synchronization

extension GStreamer {
    /// Registers a Swift-backed BaseSink factory for the current process.
    public static func register(_ element: SwiftBaseSinkElement) throws {
        try ensureInitialized()

        let registration = try NativeElementRegistration.validateBaseSink(element)
        let classContext = SwiftBaseSinkClassContext(element: element, properties: registration.properties)
        let propertyDescriptors = NativePropertyCDescriptorStorage(properties: registration.properties)

        var callbacks = SwiftGstBaseSinkCallbacks()
        callbacks.create_instance = swiftGstBaseSinkCreateInstance
        callbacks.destroy_instance = swiftGstBaseSinkDestroyInstance
        callbacks.start = swiftGstBaseSinkStart
        callbacks.stop = swiftGstBaseSinkStop
        callbacks.set_caps = swiftGstBaseSinkSetCaps
        callbacks.render = swiftGstBaseSinkRender
        callbacks.set_bool_property = swiftGstBaseSinkSetBoolProperty
        callbacks.set_int_property = swiftGstBaseSinkSetIntProperty
        callbacks.set_double_property = swiftGstBaseSinkSetDoubleProperty
        callbacks.set_string_property = swiftGstBaseSinkSetStringProperty
        callbacks.get_bool_property = swiftGstBaseSinkGetBoolProperty
        callbacks.get_int_property = swiftGstBaseSinkGetIntProperty
        callbacks.get_double_property = swiftGstBaseSinkGetDoubleProperty
        callbacks.get_string_property = swiftGstBaseSinkGetStringProperty

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

                                    NativeElementRegistrationTestHooks.recordBaseSinkCRegistrationAttempt()
                                    return swift_gst_register_base_sink(
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

    public static func register(_ element: SwiftBaseTransformElement) throws {
        try ensureInitialized()

        let registration = try NativeElementRegistration.validateBaseTransform(element)
        let classContext = SwiftBaseTransformClassContext(element: element, properties: registration.properties)
        let propertyDescriptors = NativePropertyCDescriptorStorage(properties: registration.properties)

        var callbacks = SwiftGstBaseTransformCallbacks()
        callbacks.create_instance = swiftGstBaseTransformCreateInstance
        callbacks.destroy_instance = swiftGstBaseTransformDestroyInstance
        callbacks.start = swiftGstBaseTransformStart
        callbacks.stop = swiftGstBaseTransformStop
        callbacks.set_caps = swiftGstBaseTransformSetCaps
        callbacks.transform_ip = swiftGstBaseTransformIP
        callbacks.set_bool_property = swiftGstBaseTransformSetBoolProperty
        callbacks.set_int_property = swiftGstBaseTransformSetIntProperty
        callbacks.set_double_property = swiftGstBaseTransformSetDoubleProperty
        callbacks.set_string_property = swiftGstBaseTransformSetStringProperty
        callbacks.get_bool_property = swiftGstBaseTransformGetBoolProperty
        callbacks.get_int_property = swiftGstBaseTransformGetIntProperty
        callbacks.get_double_property = swiftGstBaseTransformGetDoubleProperty
        callbacks.get_string_property = swiftGstBaseTransformGetStringProperty

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
                                            .recordBaseTransformCRegistrationAttempt()
                                        return swift_gst_register_base_transform(
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

    public static func register(_ element: SwiftBaseTransformOutOfPlaceElement) throws {
        try ensureInitialized()

        let registration = try NativeElementRegistration.validateBaseTransformOutOfPlace(element)
        let classContext = SwiftBaseTransformOutOfPlaceClassContext(
            element: element,
            properties: registration.properties
        )
        let propertyDescriptors = NativePropertyCDescriptorStorage(properties: registration.properties)

        var callbacks = SwiftGstBaseTransformCallbacks()
        callbacks.create_instance = swiftGstBaseTransformOutOfPlaceCreateInstance
        callbacks.destroy_instance = swiftGstBaseTransformOutOfPlaceDestroyInstance
        callbacks.start = swiftGstBaseTransformOutOfPlaceStart
        callbacks.stop = swiftGstBaseTransformOutOfPlaceStop
        callbacks.set_caps = swiftGstBaseTransformOutOfPlaceSetCaps
        callbacks.transform = swiftGstBaseTransformOutOfPlaceTransform
        if registration.options == .general {
            callbacks.transform_caps = swiftGstBaseTransformOutOfPlaceTransformCaps
            callbacks.fixate_caps = swiftGstBaseTransformOutOfPlaceFixateCaps
            callbacks.get_unit_size = swiftGstBaseTransformOutOfPlaceGetUnitSize
            callbacks.transform_size = swiftGstBaseTransformOutOfPlaceTransformSize
            callbacks.decide_allocation = swiftGstBaseTransformOutOfPlaceDecideAllocation
            callbacks.propose_allocation = swiftGstBaseTransformOutOfPlaceProposeAllocation
            callbacks.filter_meta = swiftGstBaseTransformOutOfPlaceFilterMeta
            callbacks.copy_metadata = swiftGstBaseTransformOutOfPlaceCopyMetadata
            callbacks.transform_meta = swiftGstBaseTransformOutOfPlaceTransformMetadata
        }
        callbacks.set_bool_property = swiftGstBaseTransformOutOfPlaceSetBoolProperty
        callbacks.set_int_property = swiftGstBaseTransformOutOfPlaceSetIntProperty
        callbacks.set_double_property = swiftGstBaseTransformOutOfPlaceSetDoubleProperty
        callbacks.set_string_property = swiftGstBaseTransformOutOfPlaceSetStringProperty
        callbacks.get_bool_property = swiftGstBaseTransformOutOfPlaceGetBoolProperty
        callbacks.get_int_property = swiftGstBaseTransformOutOfPlaceGetIntProperty
        callbacks.get_double_property = swiftGstBaseTransformOutOfPlaceGetDoubleProperty
        callbacks.get_string_property = swiftGstBaseTransformOutOfPlaceGetStringProperty

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
                                            .recordBaseTransformOutOfPlaceCRegistrationAttempt()
                                        return swift_gst_register_base_transform(
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
internal enum NativeElementRegistrationTestHooks {
    internal struct CRegistrationCapture {
        let attemptCount: Int
        let error: Error?
    }

    internal struct StaticPluginCRegistrationAttempt: Sendable {
        let name: String
        let description: String
        let version: String
        let license: String
        let source: String
        let package: String
        let origin: String
    }

    internal struct StaticPluginCRegistrationCapture {
        let attemptCount: Int
        let attempts: [StaticPluginCRegistrationAttempt]
        let error: Error?
    }

    internal struct PluginAwareNativeElementRegistrationCapture {
        let error: Error?
        let baseSinkNonNullPluginCount: Int
        let baseTransformInPlaceNonNullPluginCount: Int
        let baseTransformFixedOutOfPlaceNonNullPluginCount: Int
        let baseTransformGeneralOutOfPlaceNonNullPluginCount: Int
        let nullPluginRegistrationCount: Int
    }

    internal struct StaticPluginContextRetainReleaseCapture {
        let retainCount: Int
        let releaseCount: Int
        let successfulElementClassContextReleaseCount: Int
        let error: Error?
    }

    private struct PluginAwareNativeElementRegistrationState {
        var baseSinkNonNullPluginCount = 0
        var baseTransformInPlaceNonNullPluginCount = 0
        var baseTransformFixedOutOfPlaceNonNullPluginCount = 0
        var baseTransformGeneralOutOfPlaceNonNullPluginCount = 0
        var nullPluginRegistrationCount = 0
    }

    private struct StaticPluginContextRetainReleaseState {
        var retainCount = 0
        var releaseCount = 0
        var elementClassContextReleaseCount = 0
    }

    private struct StaticPluginCRegistrationCaptureState {
        var attempts: [StaticPluginCRegistrationAttempt] = []
    }

    private struct ForcedStaticPluginInitFailure: Sendable {
        var factoryName: String
        var message: String
    }

    private static let baseSinkCRegistrationAttempts = Mutex(0)
    private static let baseTransformCRegistrationAttempts = Mutex(0)
    private static let baseTransformOutOfPlaceCRegistrationAttempts = Mutex(0)
    private static let staticPluginCRegistrationState = Mutex<StaticPluginCRegistrationCaptureState?>(nil)
    private static let forcedStaticPluginInitFailure = Mutex<ForcedStaticPluginInitFailure?>(nil)
    private static let pluginAwareNativeElementRegistrationState =
        Mutex<PluginAwareNativeElementRegistrationState?>(nil)
    private static let staticPluginContextRetainReleaseState =
        Mutex<StaticPluginContextRetainReleaseState?>(nil)

    static func captureBaseSinkCRegistrationAttempts(
        _ body: () throws -> Void
    ) -> CRegistrationCapture {
        let before = baseSinkCRegistrationAttempts.withLock { $0 }
        do {
            try body()
            let after = baseSinkCRegistrationAttempts.withLock { $0 }
            return CRegistrationCapture(attemptCount: after - before, error: nil)
        } catch {
            let after = baseSinkCRegistrationAttempts.withLock { $0 }
            return CRegistrationCapture(attemptCount: after - before, error: error)
        }
    }

    internal static func recordBaseSinkCRegistrationAttempt() {
        baseSinkCRegistrationAttempts.withLock { $0 += 1 }
    }

    static func captureBaseTransformCRegistrationAttempts(
        _ body: () throws -> Void
    ) -> CRegistrationCapture {
        let before = baseTransformCRegistrationAttempts.withLock { $0 }
        do {
            try body()
            let after = baseTransformCRegistrationAttempts.withLock { $0 }
            return CRegistrationCapture(attemptCount: after - before, error: nil)
        } catch {
            let after = baseTransformCRegistrationAttempts.withLock { $0 }
            return CRegistrationCapture(attemptCount: after - before, error: error)
        }
    }

    internal static func recordBaseTransformCRegistrationAttempt() {
        baseTransformCRegistrationAttempts.withLock { $0 += 1 }
    }

    static func captureBaseTransformOutOfPlaceCRegistrationAttempts(
        _ body: () throws -> Void
    ) -> CRegistrationCapture {
        let before = baseTransformOutOfPlaceCRegistrationAttempts.withLock { $0 }
        do {
            try body()
            let after = baseTransformOutOfPlaceCRegistrationAttempts.withLock { $0 }
            return CRegistrationCapture(attemptCount: after - before, error: nil)
        } catch {
            let after = baseTransformOutOfPlaceCRegistrationAttempts.withLock { $0 }
            return CRegistrationCapture(attemptCount: after - before, error: error)
        }
    }

    internal static func recordBaseTransformOutOfPlaceCRegistrationAttempt() {
        baseTransformOutOfPlaceCRegistrationAttempts.withLock { $0 += 1 }
    }

    static func captureStaticPluginCRegistrationAttempts(
        _ body: () throws -> Void
    ) -> StaticPluginCRegistrationCapture {
        let previous = staticPluginCRegistrationState.withLock { state -> StaticPluginCRegistrationCaptureState? in
            let previous = state
            state = StaticPluginCRegistrationCaptureState()
            return previous
        }

        let error: Error?
        do {
            try body()
            error = nil
        } catch let caughtError {
            error = caughtError
        }

        let attempts = staticPluginCRegistrationState.withLock { state in
            let attempts = state?.attempts ?? []
            state = previous
            return attempts
        }

        return StaticPluginCRegistrationCapture(
            attemptCount: attempts.count,
            attempts: attempts,
            error: error
        )
    }

    internal static func recordStaticPluginCRegistrationAttempt(_ metadata: NativeStaticPluginMetadata) {
        staticPluginCRegistrationState.withLock { state in
            guard state != nil else { return }
            state?.attempts.append(
                StaticPluginCRegistrationAttempt(
                    name: metadata.name,
                    description: metadata.description,
                    version: metadata.version,
                    license: metadata.license,
                    source: metadata.source,
                    package: metadata.package,
                    origin: metadata.origin
                )
            )
        }
    }

    static func withForcedStaticPluginInitRegistrationFailure<T>(
        factoryName: String,
        message: String,
        _ body: () throws -> T
    ) rethrows -> T {
        let failure = ForcedStaticPluginInitFailure(factoryName: factoryName, message: message)
        let previous = forcedStaticPluginInitFailure.withLock { state -> ForcedStaticPluginInitFailure? in
            let previous = state
            state = failure
            return previous
        }
        defer {
            forcedStaticPluginInitFailure.withLock { $0 = previous }
        }
        return try body()
    }

    internal static func forcedStaticPluginInitFailureMessage(factoryName: String) -> String? {
        forcedStaticPluginInitFailure.withLock { failure in
            failure?.factoryName == factoryName ? failure?.message : nil
        }
    }

    static func capturePluginAwareNativeElementRegistrations(
        _ body: () throws -> Void
    ) -> PluginAwareNativeElementRegistrationCapture {
        let previous = pluginAwareNativeElementRegistrationState.withLock { state -> PluginAwareNativeElementRegistrationState? in
            let previous = state
            state = PluginAwareNativeElementRegistrationState()
            return previous
        }

        let error: Error?
        do {
            try body()
            error = nil
        } catch let caughtError {
            error = caughtError
        }

        let state = pluginAwareNativeElementRegistrationState.withLock { state in
            let captured = state ?? PluginAwareNativeElementRegistrationState()
            state = previous
            return captured
        }

        return PluginAwareNativeElementRegistrationCapture(
            error: error,
            baseSinkNonNullPluginCount: state.baseSinkNonNullPluginCount,
            baseTransformInPlaceNonNullPluginCount: state.baseTransformInPlaceNonNullPluginCount,
            baseTransformFixedOutOfPlaceNonNullPluginCount: state.baseTransformFixedOutOfPlaceNonNullPluginCount,
            baseTransformGeneralOutOfPlaceNonNullPluginCount: state
                .baseTransformGeneralOutOfPlaceNonNullPluginCount,
            nullPluginRegistrationCount: state.nullPluginRegistrationCount
        )
    }

    internal static func recordPluginAwareBaseSinkRegistration(pluginIsNull: Bool) {
        pluginAwareNativeElementRegistrationState.withLock { state in
            guard state != nil else { return }
            if pluginIsNull {
                state?.nullPluginRegistrationCount += 1
            } else {
                state?.baseSinkNonNullPluginCount += 1
            }
        }
    }

    internal static func recordPluginAwareBaseTransformRegistration(
        mode: SwiftGstBaseTransformMode,
        pluginIsNull: Bool
    ) {
        pluginAwareNativeElementRegistrationState.withLock { state in
            guard state != nil else { return }
            if pluginIsNull {
                state?.nullPluginRegistrationCount += 1
                return
            }

            switch mode {
            case SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE:
                state?.baseTransformInPlaceNonNullPluginCount += 1
            case SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE:
                state?.baseTransformFixedOutOfPlaceNonNullPluginCount += 1
            case SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE_GENERAL:
                state?.baseTransformGeneralOutOfPlaceNonNullPluginCount += 1
            default:
                state?.nullPluginRegistrationCount += 1
            }
        }
    }

    static func captureStaticPluginContextRetainRelease(
        _ body: () throws -> Void
    ) -> StaticPluginContextRetainReleaseCapture {
        let previous = staticPluginContextRetainReleaseState.withLock { state -> StaticPluginContextRetainReleaseState? in
            let previous = state
            state = StaticPluginContextRetainReleaseState()
            return previous
        }

        let error: Error?
        do {
            try body()
            error = nil
        } catch let caughtError {
            error = caughtError
        }

        let state = staticPluginContextRetainReleaseState.withLock { state in
            let captured = state ?? StaticPluginContextRetainReleaseState()
            state = previous
            return captured
        }

        return StaticPluginContextRetainReleaseCapture(
            retainCount: state.retainCount,
            releaseCount: state.releaseCount,
            successfulElementClassContextReleaseCount: state.elementClassContextReleaseCount,
            error: error
        )
    }

    internal static func recordStaticPluginContextRetain() {
        staticPluginContextRetainReleaseState.withLock { $0?.retainCount += 1 }
    }

    internal static func recordStaticPluginContextRelease() {
        staticPluginContextRetainReleaseState.withLock { $0?.releaseCount += 1 }
    }

    internal static func recordStaticPluginElementClassContextRelease() {
        staticPluginContextRetainReleaseState.withLock {
            $0?.elementClassContextReleaseCount += 1
        }
    }
}
internal final class SwiftBaseSinkClassContext: @unchecked Sendable {
    let element: SwiftBaseSinkElement
    let properties: [ValidatedNativeElementProperty]

    init(element: SwiftBaseSinkElement, properties: [ValidatedNativeElementProperty]) {
        self.element = element
        self.properties = properties
    }
}

internal final class SwiftBaseSinkInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseSinkInstance
    let propertyStore: NativeElementPropertyStore

    init(instance: any SwiftBaseSinkInstance, propertyStore: NativeElementPropertyStore) {
        self.instance = instance
        self.propertyStore = propertyStore
    }
}

internal final class SwiftBaseTransformClassContext: @unchecked Sendable {
    let element: SwiftBaseTransformElement
    let properties: [ValidatedNativeElementProperty]

    init(element: SwiftBaseTransformElement, properties: [ValidatedNativeElementProperty]) {
        self.element = element
        self.properties = properties
    }
}

internal final class SwiftBaseTransformInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseTransformInstance
    let propertyStore: NativeElementPropertyStore

    init(instance: any SwiftBaseTransformInstance, propertyStore: NativeElementPropertyStore) {
        self.instance = instance
        self.propertyStore = propertyStore
    }
}

internal final class SwiftBaseTransformOutOfPlaceClassContext: @unchecked Sendable {
    let element: SwiftBaseTransformOutOfPlaceElement
    let properties: [ValidatedNativeElementProperty]

    init(element: SwiftBaseTransformOutOfPlaceElement, properties: [ValidatedNativeElementProperty]) {
        self.element = element
        self.properties = properties
    }
}

internal final class SwiftBaseTransformOutOfPlaceInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseTransformOutOfPlaceInstance
    let propertyStore: NativeElementPropertyStore

    init(instance: any SwiftBaseTransformOutOfPlaceInstance, propertyStore: NativeElementPropertyStore) {
        self.instance = instance
        self.propertyStore = propertyStore
    }
}
internal func swiftGstBaseSinkCallbacks() -> SwiftGstBaseSinkCallbacks {
    var callbacks = SwiftGstBaseSinkCallbacks()
    callbacks.create_instance = swiftGstBaseSinkCreateInstance
    callbacks.destroy_instance = swiftGstBaseSinkDestroyInstance
    callbacks.start = swiftGstBaseSinkStart
    callbacks.stop = swiftGstBaseSinkStop
    callbacks.set_caps = swiftGstBaseSinkSetCaps
    callbacks.render = swiftGstBaseSinkRender
    callbacks.set_bool_property = swiftGstBaseSinkSetBoolProperty
    callbacks.set_int_property = swiftGstBaseSinkSetIntProperty
    callbacks.set_double_property = swiftGstBaseSinkSetDoubleProperty
    callbacks.set_string_property = swiftGstBaseSinkSetStringProperty
    callbacks.get_bool_property = swiftGstBaseSinkGetBoolProperty
    callbacks.get_int_property = swiftGstBaseSinkGetIntProperty
    callbacks.get_double_property = swiftGstBaseSinkGetDoubleProperty
    callbacks.get_string_property = swiftGstBaseSinkGetStringProperty
    return callbacks
}

internal func swiftGstBaseTransformCallbacks() -> SwiftGstBaseTransformCallbacks {
    var callbacks = SwiftGstBaseTransformCallbacks()
    callbacks.create_instance = swiftGstBaseTransformCreateInstance
    callbacks.destroy_instance = swiftGstBaseTransformDestroyInstance
    callbacks.start = swiftGstBaseTransformStart
    callbacks.stop = swiftGstBaseTransformStop
    callbacks.set_caps = swiftGstBaseTransformSetCaps
    callbacks.transform_ip = swiftGstBaseTransformIP
    callbacks.set_bool_property = swiftGstBaseTransformSetBoolProperty
    callbacks.set_int_property = swiftGstBaseTransformSetIntProperty
    callbacks.set_double_property = swiftGstBaseTransformSetDoubleProperty
    callbacks.set_string_property = swiftGstBaseTransformSetStringProperty
    callbacks.get_bool_property = swiftGstBaseTransformGetBoolProperty
    callbacks.get_int_property = swiftGstBaseTransformGetIntProperty
    callbacks.get_double_property = swiftGstBaseTransformGetDoubleProperty
    callbacks.get_string_property = swiftGstBaseTransformGetStringProperty
    return callbacks
}

internal func swiftGstBaseTransformOutOfPlaceCallbacks(
    options: SwiftBaseTransformOutOfPlaceOptions
) -> SwiftGstBaseTransformCallbacks {
    var callbacks = SwiftGstBaseTransformCallbacks()
    callbacks.create_instance = swiftGstBaseTransformOutOfPlaceCreateInstance
    callbacks.destroy_instance = swiftGstBaseTransformOutOfPlaceDestroyInstance
    callbacks.start = swiftGstBaseTransformOutOfPlaceStart
    callbacks.stop = swiftGstBaseTransformOutOfPlaceStop
    callbacks.set_caps = swiftGstBaseTransformOutOfPlaceSetCaps
    callbacks.transform = swiftGstBaseTransformOutOfPlaceTransform
    if options == .general {
        callbacks.transform_caps = swiftGstBaseTransformOutOfPlaceTransformCaps
        callbacks.fixate_caps = swiftGstBaseTransformOutOfPlaceFixateCaps
        callbacks.get_unit_size = swiftGstBaseTransformOutOfPlaceGetUnitSize
        callbacks.transform_size = swiftGstBaseTransformOutOfPlaceTransformSize
        callbacks.decide_allocation = swiftGstBaseTransformOutOfPlaceDecideAllocation
        callbacks.propose_allocation = swiftGstBaseTransformOutOfPlaceProposeAllocation
        callbacks.filter_meta = swiftGstBaseTransformOutOfPlaceFilterMeta
        callbacks.copy_metadata = swiftGstBaseTransformOutOfPlaceCopyMetadata
        callbacks.transform_meta = swiftGstBaseTransformOutOfPlaceTransformMetadata
    }
    callbacks.set_bool_property = swiftGstBaseTransformOutOfPlaceSetBoolProperty
    callbacks.set_int_property = swiftGstBaseTransformOutOfPlaceSetIntProperty
    callbacks.set_double_property = swiftGstBaseTransformOutOfPlaceSetDoubleProperty
    callbacks.set_string_property = swiftGstBaseTransformOutOfPlaceSetStringProperty
    callbacks.get_bool_property = swiftGstBaseTransformOutOfPlaceGetBoolProperty
    callbacks.get_int_property = swiftGstBaseTransformOutOfPlaceGetIntProperty
    callbacks.get_double_property = swiftGstBaseTransformOutOfPlaceGetDoubleProperty
    callbacks.get_string_property = swiftGstBaseTransformOutOfPlaceGetStringProperty
    return callbacks
}

internal func swiftGstBaseSinkRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(context).retain()
}

internal func swiftGstBaseSinkReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    NativeElementRegistrationTestHooks.recordStaticPluginElementClassContextRelease()
    Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(context).release()
}

private func swiftGstBaseSinkCreateInstance(_ classContext: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let classContext else { return nil }
    let context = Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(classContext).takeUnretainedValue()
    let propertyStore = NativeElementPropertyStore(descriptors: context.properties)
    let reader = NativeElementPropertyReader(store: propertyStore)
    let instanceContext = SwiftBaseSinkInstanceContext(
        instance: context.element.makeInstanceWithProperties(reader),
        propertyStore: propertyStore
    )
    return Unmanaged.passRetained(instanceContext).toOpaque()
}

private func swiftGstBaseSinkDestroyInstance(_ instanceContext: UnsafeMutableRawPointer?) {
    guard let instanceContext else { return }
    Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).release()
}

private func swiftGstBaseSinkStart(_ instanceContext: UnsafeMutableRawPointer?) -> gboolean {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    do {
        try context.instance.start()
        return 1
    } catch {
        return 0
    }
}

private func swiftGstBaseSinkStop(_ instanceContext: UnsafeMutableRawPointer?) -> gboolean {
    guard let instanceContext else { return 1 }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.instance.stop()
    return 1
}

private func swiftGstBaseSinkSetCaps(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ caps: UnsafeMutablePointer<GstCaps>?
) -> gboolean {
    guard let instanceContext, let caps else { return 0 }
    guard let retainedCaps = swift_gst_caps_ref(caps) else { return 0 }
    let wrappedCaps = Caps(caps: retainedCaps, ownsReference: true)
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()

    do {
        return try context.instance.setCaps(wrappedCaps) ? 1 : 0
    } catch {
        return 0
    }
}

private func swiftGstBaseSinkRender(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ buffer: UnsafeMutablePointer<GstBuffer>?
) -> GstFlowReturn {
    guard let instanceContext, let buffer else { return GST_FLOW_ERROR }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    let borrowedBuffer = BorrowedBuffer(buffer: buffer)

    do {
        return try context.instance.render(borrowedBuffer).baseSinkRenderGstFlowReturn
    } catch {
        return GST_FLOW_ERROR
    }
}

private func swiftGstBaseSinkSetBoolProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gboolean
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setBool(index: Int(propertyIndex), value: value != 0)
}

private func swiftGstBaseSinkSetIntProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gint
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setInt(index: Int(propertyIndex), value: Int32(value))
}

private func swiftGstBaseSinkSetDoubleProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gdouble
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setDouble(index: Int(propertyIndex), value: Double(value))
}

private func swiftGstBaseSinkSetStringProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: UnsafePointer<CChar>?
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setString(index: Int(propertyIndex), value: GLibString.borrow(value))
}

private func swiftGstBaseSinkGetBoolProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gboolean {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return context.propertyStore.bool(index: Int(propertyIndex)) ? 1 : 0
}

private func swiftGstBaseSinkGetIntProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gint {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return gint(context.propertyStore.int(index: Int(propertyIndex)))
}

private func swiftGstBaseSinkGetDoubleProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gdouble {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return gdouble(context.propertyStore.double(index: Int(propertyIndex)))
}

private func swiftGstBaseSinkGetStringProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> UnsafeMutablePointer<CChar>? {
    guard let instanceContext else { return nil }
    let context = Unmanaged<SwiftBaseSinkInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return context.propertyStore.stringForC(index: Int(propertyIndex))
}

internal func swiftGstBaseTransformRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(context).retain()
}

internal func swiftGstBaseTransformReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    NativeElementRegistrationTestHooks.recordStaticPluginElementClassContextRelease()
    Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(context).release()
}

private func swiftGstBaseTransformCreateInstance(_ classContext: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let classContext else { return nil }
    let context = Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(classContext).takeUnretainedValue()
    let propertyStore = NativeElementPropertyStore(descriptors: context.properties)
    let reader = NativeElementPropertyReader(store: propertyStore)
    let instanceContext = SwiftBaseTransformInstanceContext(
        instance: context.element.makeInstanceWithProperties(reader),
        propertyStore: propertyStore
    )
    return Unmanaged.passRetained(instanceContext).toOpaque()
}

private func swiftGstBaseTransformDestroyInstance(_ instanceContext: UnsafeMutableRawPointer?) {
    guard let instanceContext else { return }
    Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).release()
}

private func swiftGstBaseTransformStart(_ instanceContext: UnsafeMutableRawPointer?) -> gboolean {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    do {
        try context.instance.start()
        return 1
    } catch {
        return 0
    }
}

private func swiftGstBaseTransformStop(_ instanceContext: UnsafeMutableRawPointer?) -> gboolean {
    guard let instanceContext else { return 1 }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.instance.stop()
    return 1
}

private func swiftGstBaseTransformSetCaps(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ inputCaps: UnsafeMutablePointer<GstCaps>?,
    _ outputCaps: UnsafeMutablePointer<GstCaps>?
) -> gboolean {
    guard let instanceContext, let inputCaps, let outputCaps else { return 0 }
    guard let retainedInputCaps = swift_gst_caps_ref(inputCaps) else { return 0 }
    guard let retainedOutputCaps = swift_gst_caps_ref(outputCaps) else {
        swift_gst_caps_unref(retainedInputCaps)
        return 0
    }

    let input = Caps(caps: retainedInputCaps, ownsReference: true)
    let output = Caps(caps: retainedOutputCaps, ownsReference: true)
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()

    do {
        return try context.instance.setCaps(input: input, output: output) ? 1 : 0
    } catch {
        return 0
    }
}

private func swiftGstBaseTransformIP(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ buffer: UnsafeMutablePointer<GstBuffer>?
) -> GstFlowReturn {
    guard let instanceContext, let buffer else { return GST_FLOW_ERROR }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    let borrowedBuffer = MutableBorrowedBuffer(buffer: buffer)

    do {
        return try context.instance.transformInPlace(borrowedBuffer).baseTransformGstFlowReturn
    } catch {
        return GST_FLOW_ERROR
    }
}

private func swiftGstBaseTransformSetBoolProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gboolean
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setBool(index: Int(propertyIndex), value: value != 0)
}

private func swiftGstBaseTransformSetIntProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gint
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setInt(index: Int(propertyIndex), value: Int32(value))
}

private func swiftGstBaseTransformSetDoubleProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gdouble
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setDouble(index: Int(propertyIndex), value: Double(value))
}

private func swiftGstBaseTransformSetStringProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: UnsafePointer<CChar>?
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    context.propertyStore.setString(index: Int(propertyIndex), value: GLibString.borrow(value))
}

private func swiftGstBaseTransformGetBoolProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gboolean {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return context.propertyStore.bool(index: Int(propertyIndex)) ? 1 : 0
}

private func swiftGstBaseTransformGetIntProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gint {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return gint(context.propertyStore.int(index: Int(propertyIndex)))
}

private func swiftGstBaseTransformGetDoubleProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gdouble {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return gdouble(context.propertyStore.double(index: Int(propertyIndex)))
}

private func swiftGstBaseTransformGetStringProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> UnsafeMutablePointer<CChar>? {
    guard let instanceContext else { return nil }
    let context = Unmanaged<SwiftBaseTransformInstanceContext>.fromOpaque(instanceContext).takeUnretainedValue()
    return context.propertyStore.stringForC(index: Int(propertyIndex))
}

internal func swiftGstBaseTransformOutOfPlaceRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseTransformOutOfPlaceClassContext>.fromOpaque(context).retain()
}

internal func swiftGstBaseTransformOutOfPlaceReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    NativeElementRegistrationTestHooks.recordStaticPluginElementClassContextRelease()
    Unmanaged<SwiftBaseTransformOutOfPlaceClassContext>.fromOpaque(context).release()
}

private func swiftGstBaseTransformOutOfPlaceCreateInstance(
    _ classContext: UnsafeMutableRawPointer?
) -> UnsafeMutableRawPointer? {
    guard let classContext else { return nil }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceClassContext>
        .fromOpaque(classContext)
        .takeUnretainedValue()
    let propertyStore = NativeElementPropertyStore(descriptors: context.properties)
    let reader = NativeElementPropertyReader(store: propertyStore)
    let instanceContext = SwiftBaseTransformOutOfPlaceInstanceContext(
        instance: context.element.makeInstanceWithProperties(reader),
        propertyStore: propertyStore
    )
    return Unmanaged.passRetained(instanceContext).toOpaque()
}

private func swiftGstBaseTransformOutOfPlaceDestroyInstance(_ instanceContext: UnsafeMutableRawPointer?) {
    guard let instanceContext else { return }
    Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>.fromOpaque(instanceContext).release()
}

private func swiftGstBaseTransformOutOfPlaceStart(_ instanceContext: UnsafeMutableRawPointer?) -> gboolean {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    do {
        try context.instance.start()
        return 1
    } catch {
        return 0
    }
}

private func swiftGstBaseTransformOutOfPlaceStop(_ instanceContext: UnsafeMutableRawPointer?) -> gboolean {
    guard let instanceContext else { return 1 }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    context.instance.stop()
    return 1
}

private func swiftGstBaseTransformOutOfPlaceSetCaps(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ inputCaps: UnsafeMutablePointer<GstCaps>?,
    _ outputCaps: UnsafeMutablePointer<GstCaps>?
) -> gboolean {
    guard let instanceContext, let inputCaps, let outputCaps else { return 0 }
    guard let retainedInputCaps = swift_gst_caps_ref(inputCaps) else { return 0 }
    guard let retainedOutputCaps = swift_gst_caps_ref(outputCaps) else {
        swift_gst_caps_unref(retainedInputCaps)
        return 0
    }

    let input = Caps(caps: retainedInputCaps, ownsReference: true)
    let output = Caps(caps: retainedOutputCaps, ownsReference: true)
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()

    do {
        return try context.instance.setCaps(input: input, output: output) ? 1 : 0
    } catch {
        return 0
    }
}

private func swiftGstBaseTransformOutOfPlaceTransform(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ inputBuffer: UnsafeMutablePointer<GstBuffer>?,
    _ outputBuffer: UnsafeMutablePointer<GstBuffer>?
) -> GstFlowReturn {
    guard let instanceContext, let inputBuffer, let outputBuffer else { return GST_FLOW_ERROR }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    let input = BorrowedBuffer(buffer: inputBuffer)
    let output = MutableBorrowedBuffer(buffer: outputBuffer)

    do {
        return try context.instance.transform(input, into: output).baseTransformGstFlowReturn
    } catch {
        return GST_FLOW_ERROR
    }
}

private func swiftGstBaseTransformOutOfPlaceTransformCaps(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ direction: GstPadDirection,
    _ caps: UnsafeMutablePointer<GstCaps>?,
    _ filter: UnsafeMutablePointer<GstCaps>?
) -> SwiftGstBaseTransformCapsResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let caps,
          let retainedCaps = swift_gst_caps_ref(caps)
    else {
        return swiftGstBaseTransformCapsFailure()
    }

    let retainedFilter = filter.flatMap { swift_gst_caps_ref($0) }
    let wrappedCaps = Caps(caps: retainedCaps, ownsReference: true)
    let wrappedFilter = retainedFilter.map { Caps(caps: $0, ownsReference: true) }

    do {
        return swiftGstBaseTransformCapsResult(
            try context.instance.transformCaps(
                direction: Pad.Direction(gstPadDirection: direction),
                caps: wrappedCaps,
                filter: wrappedFilter
            )
        )
    } catch {
        return swiftGstBaseTransformCapsFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceFixateCaps(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ direction: GstPadDirection,
    _ caps: UnsafeMutablePointer<GstCaps>?,
    _ otherCaps: UnsafeMutablePointer<GstCaps>?
) -> SwiftGstBaseTransformCapsResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let caps,
          let otherCaps,
          let retainedCaps = swift_gst_caps_ref(caps),
          let retainedOtherCaps = swift_gst_caps_ref(otherCaps)
    else {
        return swiftGstBaseTransformCapsFailure()
    }

    let wrappedCaps = Caps(caps: retainedCaps, ownsReference: true)
    let wrappedOtherCaps = Caps(caps: retainedOtherCaps, ownsReference: true)

    do {
        return swiftGstBaseTransformCapsResult(
            try context.instance.fixateCaps(
                direction: Pad.Direction(gstPadDirection: direction),
                caps: wrappedCaps,
                otherCaps: wrappedOtherCaps
            )
        )
    } catch {
        return swiftGstBaseTransformCapsFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceGetUnitSize(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ caps: UnsafeMutablePointer<GstCaps>?
) -> SwiftGstBaseTransformSizeResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let caps,
          let retainedCaps = swift_gst_caps_ref(caps)
    else {
        return swiftGstBaseTransformSizeFailure()
    }

    let wrappedCaps = Caps(caps: retainedCaps, ownsReference: true)
    do {
        return swiftGstBaseTransformSizeResult(
            try context.instance.getUnitSize(for: wrappedCaps)
        )
    } catch {
        return swiftGstBaseTransformSizeFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceTransformSize(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ direction: GstPadDirection,
    _ caps: UnsafeMutablePointer<GstCaps>?,
    _ size: gsize,
    _ otherCaps: UnsafeMutablePointer<GstCaps>?
) -> SwiftGstBaseTransformSizeResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let caps,
          let otherCaps,
          size <= gsize(Int.max),
          let retainedCaps = swift_gst_caps_ref(caps),
          let retainedOtherCaps = swift_gst_caps_ref(otherCaps)
    else {
        return swiftGstBaseTransformSizeFailure()
    }

    let wrappedCaps = Caps(caps: retainedCaps, ownsReference: true)
    let wrappedOtherCaps = Caps(caps: retainedOtherCaps, ownsReference: true)

    do {
        return swiftGstBaseTransformSizeResult(
            try context.instance.transformSize(
                direction: Pad.Direction(gstPadDirection: direction),
                caps: wrappedCaps,
                size: Int(size),
                otherCaps: wrappedOtherCaps
            )
        )
    } catch {
        return swiftGstBaseTransformSizeFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceDecideAllocation(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ query: UnsafeMutablePointer<GstQuery>?
) -> SwiftGstBaseTransformBoolResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext), let query else {
        return swiftGstBaseTransformBoolFailure()
    }

    let wrappedQuery = AllocationQuery(query: query)
    do {
        return swiftGstBaseTransformBoolResult(try context.instance.decideAllocation(wrappedQuery))
    } catch {
        return swiftGstBaseTransformBoolFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceProposeAllocation(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ decideQuery: UnsafeMutablePointer<GstQuery>?,
    _ query: UnsafeMutablePointer<GstQuery>?
) -> SwiftGstBaseTransformBoolResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let decideQuery,
          let query
    else {
        return SwiftGstBaseTransformBoolResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
            value: 0
        )
    }

    let wrappedDecideQuery = AllocationQuery(query: decideQuery)
    let wrappedQuery = AllocationQuery(query: query)
    do {
        return swiftGstBaseTransformBoolResult(
            try context.instance.proposeAllocation(decideQuery: wrappedDecideQuery, query: wrappedQuery)
        )
    } catch {
        return swiftGstBaseTransformBoolFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceFilterMeta(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ query: UnsafeMutablePointer<GstQuery>?,
    _ api: GType,
    _ params: UnsafePointer<GstStructure>?
) -> SwiftGstBaseTransformBoolResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext), let query else {
        return swiftGstBaseTransformBoolFailure()
    }

    let wrappedQuery = AllocationQuery(query: query)
    do {
        return swiftGstBaseTransformBoolResult(
            try context.instance.filterAllocationMetadata(
                AllocationMetadata(api: api, params: params),
                query: wrappedQuery
            )
        )
    } catch {
        return swiftGstBaseTransformBoolFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceCopyMetadata(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ inputBuffer: UnsafeMutablePointer<GstBuffer>?,
    _ outputBuffer: UnsafeMutablePointer<GstBuffer>?
) -> SwiftGstBaseTransformBoolResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let inputBuffer,
          let outputBuffer
    else {
        return swiftGstBaseTransformBoolFailure()
    }

    let input = BorrowedBuffer(buffer: inputBuffer)
    let output = MutableBorrowedBuffer(buffer: outputBuffer)
    do {
        return swiftGstBaseTransformBoolResult(try context.instance.copyMetadata(from: input, to: output))
    } catch {
        return swiftGstBaseTransformBoolFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceTransformMetadata(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ outputBuffer: UnsafeMutablePointer<GstBuffer>?,
    _ metadata: UnsafeMutablePointer<GstMeta>?,
    _ inputBuffer: UnsafeMutablePointer<GstBuffer>?
) -> SwiftGstBaseTransformBoolResult {
    guard let context = swiftGstBaseTransformOutOfPlaceContext(instanceContext),
          let inputBuffer,
          let outputBuffer,
          let metadata
    else {
        return swiftGstBaseTransformBoolFailure()
    }

    let input = BorrowedBuffer(buffer: inputBuffer)
    let output = MutableBorrowedBuffer(buffer: outputBuffer)
    let wrappedMetadata = BufferMetadata(metadata: metadata)
    do {
        return swiftGstBaseTransformBoolResult(
            try context.instance.transformMetadata(wrappedMetadata, from: input, to: output)
        )
    } catch {
        return swiftGstBaseTransformBoolFailure()
    }
}

private func swiftGstBaseTransformOutOfPlaceSetBoolProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gboolean
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    context.propertyStore.setBool(index: Int(propertyIndex), value: value != 0)
}

private func swiftGstBaseTransformOutOfPlaceSetIntProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gint
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    context.propertyStore.setInt(index: Int(propertyIndex), value: Int32(value))
}

private func swiftGstBaseTransformOutOfPlaceSetDoubleProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: gdouble
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    context.propertyStore.setDouble(index: Int(propertyIndex), value: Double(value))
}

private func swiftGstBaseTransformOutOfPlaceSetStringProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint,
    _ value: UnsafePointer<CChar>?
) {
    guard let instanceContext else { return }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    context.propertyStore.setString(index: Int(propertyIndex), value: GLibString.borrow(value))
}

private func swiftGstBaseTransformOutOfPlaceGetBoolProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gboolean {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    return context.propertyStore.bool(index: Int(propertyIndex)) ? 1 : 0
}

private func swiftGstBaseTransformOutOfPlaceGetIntProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gint {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    return gint(context.propertyStore.int(index: Int(propertyIndex)))
}

private func swiftGstBaseTransformOutOfPlaceGetDoubleProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> gdouble {
    guard let instanceContext else { return 0 }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    return gdouble(context.propertyStore.double(index: Int(propertyIndex)))
}

private func swiftGstBaseTransformOutOfPlaceGetStringProperty(
    _ instanceContext: UnsafeMutableRawPointer?,
    _ propertyIndex: guint
) -> UnsafeMutablePointer<CChar>? {
    guard let instanceContext else { return nil }
    let context = Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
    return context.propertyStore.stringForC(index: Int(propertyIndex))
}

private func swiftGstBaseTransformOutOfPlaceContext(
    _ instanceContext: UnsafeMutableRawPointer?
) -> SwiftBaseTransformOutOfPlaceInstanceContext? {
    guard let instanceContext else { return nil }
    return Unmanaged<SwiftBaseTransformOutOfPlaceInstanceContext>
        .fromOpaque(instanceContext)
        .takeUnretainedValue()
}

private func swiftGstBaseTransformCapsResult(
    _ result: BaseTransformHookResult<Caps>
) -> SwiftGstBaseTransformCapsResult {
    switch result {
    case .useDefault:
        return SwiftGstBaseTransformCapsResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
            caps: nil
        )
    case .value(let caps):
        guard let retainedCaps = swift_gst_caps_ref(caps.caps) else {
            return swiftGstBaseTransformCapsFailure()
        }
        return SwiftGstBaseTransformCapsResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            caps: retainedCaps
        )
    case .failure:
        return swiftGstBaseTransformCapsFailure()
    }
}

private func swiftGstBaseTransformCapsFailure() -> SwiftGstBaseTransformCapsResult {
    SwiftGstBaseTransformCapsResult(
        status: SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
        caps: nil
    )
}

private func swiftGstBaseTransformSizeResult(
    _ result: BaseTransformHookResult<Int>
) -> SwiftGstBaseTransformSizeResult {
    switch result {
    case .useDefault:
        return SwiftGstBaseTransformSizeResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
            size: 0
        )
    case .value(let size):
        guard size > 0, size < Int.max else {
            return swiftGstBaseTransformSizeFailure()
        }
        return SwiftGstBaseTransformSizeResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            size: gsize(size)
        )
    case .failure:
        return swiftGstBaseTransformSizeFailure()
    }
}

private func swiftGstBaseTransformSizeFailure() -> SwiftGstBaseTransformSizeResult {
    SwiftGstBaseTransformSizeResult(
        status: SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
        size: 0
    )
}

private func swiftGstBaseTransformBoolResult(
    _ result: BaseTransformHookResult<Bool>
) -> SwiftGstBaseTransformBoolResult {
    switch result {
    case .useDefault:
        return SwiftGstBaseTransformBoolResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT,
            value: 0
        )
    case .value(let value):
        return SwiftGstBaseTransformBoolResult(
            status: SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE,
            value: value ? 1 : 0
        )
    case .failure:
        return swiftGstBaseTransformBoolFailure()
    }
}

private func swiftGstBaseTransformBoolFailure() -> SwiftGstBaseTransformBoolResult {
    SwiftGstBaseTransformBoolResult(
        status: SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE,
        value: 0
    )
}
private extension Pad.Direction {
    init(gstPadDirection: GstPadDirection) {
        switch gstPadDirection {
        case GST_PAD_SRC:
            self = .source
        case GST_PAD_SINK:
            self = .sink
        default:
            self = .unknown
        }
    }
}
