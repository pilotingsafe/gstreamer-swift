import CGStreamer
import CGStreamerBaseShim
import CGStreamerShim
import Synchronization

/// Flow return values for Swift-backed native element callbacks.
public enum FlowReturn: Sendable {
    case ok
    case error
    case notNegotiated
    case flushing
    case eos
    case dropped
    case custom(Int32)
}

extension FlowReturn {
    internal var gstFlowReturn: GstFlowReturn {
        switch self {
        case .ok:
            return GST_FLOW_OK
        case .error:
            return GST_FLOW_ERROR
        case .notNegotiated:
            return GST_FLOW_NOT_NEGOTIATED
        case .flushing:
            return GST_FLOW_FLUSHING
        case .eos:
            return GST_FLOW_EOS
        case .dropped:
            return GST_FLOW_CUSTOM_SUCCESS
        case .custom(let value):
            return GstFlowReturn(rawValue: value)
        }
    }
}

/// GStreamer element factory rank.
public enum ElementRank: UInt32, Sendable {
    case none = 0
    case marginal = 64
    case secondary = 128
    case primary = 256
}

/// Metadata used when registering Swift-backed native elements.
public struct NativeElementMetadata: Sendable {
    public var klass: String
    public var longName: String
    public var description: String
    public var author: String
    public var rank: ElementRank

    public init(
        klass: String,
        longName: String,
        description: String,
        author: String = "gstreamer-swift",
        rank: ElementRank = .none
    ) {
        self.klass = klass
        self.longName = longName
        self.description = description
        self.author = author
        self.rank = rank
    }
}

/// A read-only borrowed GStreamer buffer valid only for the callback scope.
///
/// Raw pointers received through ``withUnsafeBytes(_:)`` must not escape the
/// closure. Use ``retainedReference()`` or ``deepCopy()`` when data must outlive
/// the callback.
public struct BorrowedBuffer: ~Copyable {
    private let buffer: UnsafeMutablePointer<GstBuffer>

    internal init(buffer: UnsafeMutablePointer<GstBuffer>) {
        self.buffer = buffer
    }

    /// The buffer size in bytes.
    public var size: Int {
        Int(swift_gst_buffer_get_size(buffer))
    }

    /// The presentation timestamp in nanoseconds, or nil when unset.
    public var pts: UInt64? {
        let value = swift_gst_buffer_get_pts(buffer)
        return swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
    }

    /// The buffer duration in nanoseconds, or nil when unset.
    public var duration: UInt64? {
        let value = swift_gst_buffer_get_duration(buffer)
        return swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
    }

    /// Maps the borrowed buffer for read access during the closure.
    ///
    /// The raw buffer pointer is invalid after the closure returns and must not
    /// be stored or used outside the closure.
    public func withUnsafeBytes<R>(
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) throws -> R {
        var mapInfo = GstMapInfo()
        guard swift_gst_buffer_map_read(buffer, &mapInfo) != 0 else {
            throw GStreamerError.bufferMapFailed
        }
        defer { swift_gst_buffer_unmap(buffer, &mapInfo) }

        let bytes = UnsafeRawBufferPointer(start: mapInfo.data, count: Int(mapInfo.size))
        return try body(bytes)
    }

    /// Returns an owned `Buffer` that retains the underlying `GstBuffer`.
    public func retainedReference() -> Buffer {
        _ = swift_gst_buffer_ref(buffer)
        return Buffer(buffer: buffer, ownsReference: true)
    }

    /// Returns an owned deep copy of the underlying `GstBuffer`.
    public func deepCopy() throws -> Buffer {
        guard let copied = gst_buffer_copy_deep(buffer) else {
            throw GStreamerError.bufferMapFailed
        }
        return Buffer(buffer: copied, ownsReference: true)
    }
}

/// Per-instance callbacks for a Swift-backed BaseSink element.
public protocol SwiftBaseSinkInstance: AnyObject, Sendable {
    func start() throws
    func stop()
    func setCaps(_ caps: Caps) throws -> Bool
    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn
}

public extension SwiftBaseSinkInstance {
    func start() throws {}
    func stop() {}
    func setCaps(_ caps: Caps) throws -> Bool { true }
}

/// Registration description for a Swift-backed BaseSink element.
public struct SwiftBaseSinkElement: Sendable {
    public let factoryName: String
    public let typeName: String?
    public let metadata: NativeElementMetadata
    public let sinkCaps: String
    public let makeInstance: @Sendable () -> any SwiftBaseSinkInstance

    public init(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        makeInstance: @escaping @Sendable () -> any SwiftBaseSinkInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.makeInstance = makeInstance
    }
}

/// Passthrough configuration for Swift-backed in-place BaseTransform elements.
public struct SwiftBaseTransformPassthroughOptions: Sendable {
    public var passthroughOnSameCaps: Bool
    public var transformInPlaceOnPassthrough: Bool

    public static let `default` = SwiftBaseTransformPassthroughOptions()

    public init(
        passthroughOnSameCaps: Bool = true,
        transformInPlaceOnPassthrough: Bool = false
    ) {
        self.passthroughOnSameCaps = passthroughOnSameCaps
        self.transformInPlaceOnPassthrough = transformInPlaceOnPassthrough
    }
}

/// A writable borrowed GStreamer buffer valid only for the transform callback scope.
///
/// Raw pointers received through ``withUnsafeMutableBytes(_:)`` must not escape
/// the closure. Use ``retainedReference()`` or ``deepCopy()`` when data must
/// outlive the callback.
public struct MutableBorrowedBuffer: ~Copyable {
    private let buffer: UnsafeMutablePointer<GstBuffer>

    internal init(buffer: UnsafeMutablePointer<GstBuffer>) {
        self.buffer = buffer
    }

    /// The buffer size in bytes.
    public var size: Int {
        Int(swift_gst_buffer_get_size(buffer))
    }

    /// The presentation timestamp in nanoseconds, or nil when unset.
    public var pts: UInt64? {
        let value = swift_gst_buffer_get_pts(buffer)
        return swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
    }

    /// The buffer duration in nanoseconds, or nil when unset.
    public var duration: UInt64? {
        let value = swift_gst_buffer_get_duration(buffer)
        return swift_gst_clock_time_is_valid(value) != 0 ? UInt64(value) : nil
    }

    /// Maps the borrowed buffer for write access during the closure.
    ///
    /// The raw buffer pointer is invalid after the closure returns and must not
    /// be stored or used outside the closure.
    public func withUnsafeMutableBytes<R>(
        _ body: (UnsafeMutableRawBufferPointer) throws -> R
    ) throws -> R {
        var mapInfo = GstMapInfo()
        guard swift_gst_buffer_map_write(buffer, &mapInfo) != 0 else {
            throw GStreamerError.bufferMapFailed
        }
        defer { swift_gst_buffer_unmap(buffer, &mapInfo) }

        let byteCount = Int(mapInfo.size)
        if byteCount == 0 {
            return try body(UnsafeMutableRawBufferPointer(start: nil, count: 0))
        }
        guard let data = mapInfo.data else {
            throw GStreamerError.bufferMapFailed
        }

        let bytes = UnsafeMutableRawBufferPointer(start: data, count: byteCount)
        return try body(bytes)
    }

    /// Returns an owned `Buffer` that retains the underlying `GstBuffer`.
    public func retainedReference() -> Buffer {
        _ = swift_gst_buffer_ref(buffer)
        return Buffer(buffer: buffer, ownsReference: true)
    }

    /// Returns an owned deep copy of the underlying `GstBuffer`.
    public func deepCopy() throws -> Buffer {
        guard let copied = gst_buffer_copy_deep(buffer) else {
            throw GStreamerError.bufferMapFailed
        }
        return Buffer(buffer: copied, ownsReference: true)
    }
}

/// Per-instance callbacks for a Swift-backed in-place BaseTransform element.
public protocol SwiftBaseTransformInstance: AnyObject, Sendable {
    func start() throws
    func stop()
    func setCaps(input: Caps, output: Caps) throws -> Bool
    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn
}

public extension SwiftBaseTransformInstance {
    func start() throws {}
    func stop() {}
    func setCaps(input: Caps, output: Caps) throws -> Bool { true }
}

/// Registration description for a Swift-backed in-place BaseTransform element.
public struct SwiftBaseTransformElement: Sendable {
    public let factoryName: String
    public let typeName: String?
    public let metadata: NativeElementMetadata
    public let sinkCaps: String
    public let srcCaps: String
    public let passthroughOptions: SwiftBaseTransformPassthroughOptions
    public let makeInstance: @Sendable () -> any SwiftBaseTransformInstance

    private init(
        factoryName: String,
        typeName: String?,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        passthroughOptions: SwiftBaseTransformPassthroughOptions,
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.srcCaps = srcCaps
        self.passthroughOptions = passthroughOptions
        self.makeInstance = makeInstance
    }

    public static func inPlace(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        passthroughOptions: SwiftBaseTransformPassthroughOptions = .default,
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata,
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            passthroughOptions: passthroughOptions,
            makeInstance: makeInstance
        )
    }
}

extension GStreamer {
    /// Registers a Swift-backed BaseSink factory for the current process.
    public static func register(_ element: SwiftBaseSinkElement) throws {
        try ensureInitialized()

        let registration = try NativeElementRegistration.validateBaseSink(element)
        let classContext = SwiftBaseSinkClassContext(element: element)

        var callbacks = SwiftGstBaseSinkCallbacks()
        callbacks.create_instance = swiftGstBaseSinkCreateInstance
        callbacks.destroy_instance = swiftGstBaseSinkDestroyInstance
        callbacks.start = swiftGstBaseSinkStart
        callbacks.stop = swiftGstBaseSinkStop
        callbacks.set_caps = swiftGstBaseSinkSetCaps
        callbacks.render = swiftGstBaseSinkRender

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
                                        sink_caps: sinkCaps
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
        let classContext = SwiftBaseTransformClassContext(element: element)

        var callbacks = SwiftGstBaseTransformCallbacks()
        callbacks.create_instance = swiftGstBaseTransformCreateInstance
        callbacks.destroy_instance = swiftGstBaseTransformDestroyInstance
        callbacks.start = swiftGstBaseTransformStart
        callbacks.stop = swiftGstBaseTransformStop
        callbacks.set_caps = swiftGstBaseTransformSetCaps
        callbacks.transform_ip = swiftGstBaseTransformIP

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
                                            passthrough_on_same_caps: registration
                                                .passthroughOptions
                                                .passthroughOnSameCaps ? 1 : 0,
                                            transform_ip_on_passthrough: registration
                                                .passthroughOptions
                                                .transformInPlaceOnPassthrough ? 1 : 0
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
}

internal enum NativeElementTypeName {
    static func sanitizedFactoryNameComponent(_ factoryName: String) -> String {
        var result = ""
        result.reserveCapacity(factoryName.count)
        for scalar in factoryName.unicodeScalars {
            result.unicodeScalars.append(scalar.isASCIIAlphaNumeric ? scalar : "_")
        }
        return result
    }

    static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(formatLowercaseHex: hash)
    }

    static func generatedBaseSinkTypeName(factoryName: String) -> String {
        "SwiftGstNativeBaseSink_\(sanitizedFactoryNameComponent(factoryName))_\(fnv1a64Hex(factoryName))"
    }

    static func generatedBaseTransformTypeName(factoryName: String) -> String {
        "SwiftGstNativeBaseTransform_\(sanitizedFactoryNameComponent(factoryName))_\(fnv1a64Hex(factoryName))"
    }

    static func isValidDynamicGTypeName(_ typeName: String) -> Bool {
        guard let first = typeName.unicodeScalars.first, first.isASCIILetter else {
            return false
        }
        return typeName.unicodeScalars.allSatisfy { scalar in
            scalar.isASCIIAlphaNumeric || scalar == "_"
        }
    }
}

internal enum NativeElementRegistrationTestHooks {
    internal struct CRegistrationCapture {
        let attemptCount: Int
        let error: Error?
    }

    private static let baseSinkCRegistrationAttempts = Mutex(0)
    private static let baseTransformCRegistrationAttempts = Mutex(0)

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

    fileprivate static func recordBaseSinkCRegistrationAttempt() {
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

    fileprivate static func recordBaseTransformCRegistrationAttempt() {
        baseTransformCRegistrationAttempts.withLock { $0 += 1 }
    }
}

private struct ValidatedBaseSinkRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
}

private struct ValidatedBaseTransformRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var srcCaps: String
    var passthroughOptions: SwiftBaseTransformPassthroughOptions
}

private enum NativeElementRegistration {
    static func validateBaseSink(_ element: SwiftBaseSinkElement) throws -> ValidatedBaseSinkRegistration {
        try validateFactoryName(element.factoryName)

        let typeName: String
        if let explicitTypeName = element.typeName {
            guard !explicitTypeName.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "typeName must not be empty"
                )
            }
            try validateTypeName(explicitTypeName)
            typeName = explicitTypeName
        } else {
            let generated = NativeElementTypeName.generatedBaseSinkTypeName(factoryName: element.factoryName)
            try validateTypeName(generated)
            typeName = generated
        }

        try validateMetadata(element.metadata)
        try validateCaps(element.sinkCaps, parameter: "sinkCaps")

        return ValidatedBaseSinkRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps
        )
    }

    static func validateBaseTransform(
        _ element: SwiftBaseTransformElement
    ) throws -> ValidatedBaseTransformRegistration {
        try validateFactoryName(element.factoryName)

        let typeName: String
        if let explicitTypeName = element.typeName {
            guard !explicitTypeName.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "typeName",
                    reason: "typeName must not be empty"
                )
            }
            try validateTypeName(explicitTypeName)
            typeName = explicitTypeName
        } else {
            let generated = NativeElementTypeName.generatedBaseTransformTypeName(factoryName: element.factoryName)
            try validateTypeName(generated)
            typeName = generated
        }

        try validateMetadata(element.metadata)
        try validateCaps(element.sinkCaps, parameter: "sinkCaps")
        try validateCaps(element.srcCaps, parameter: "srcCaps")

        return ValidatedBaseTransformRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            srcCaps: element.srcCaps,
            passthroughOptions: element.passthroughOptions
        )
    }

    private static func validateFactoryName(_ factoryName: String) throws {
        guard !factoryName.isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: "factoryName",
                reason: "factoryName must not be empty"
            )
        }

        guard let first = factoryName.unicodeScalars.first, first.isASCIIAlphaNumeric else {
            throw GStreamerError.invalidArgument(
                parameter: "factoryName",
                reason: "factoryName must start with an ASCII letter or digit"
            )
        }

        guard factoryName.unicodeScalars.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == "_" || $0 == "-" }) else {
            throw GStreamerError.invalidArgument(
                parameter: "factoryName",
                reason: "factoryName may contain only ASCII letters, digits, '_' or '-'"
            )
        }
    }

    private static func validateTypeName(_ typeName: String) throws {
        guard NativeElementTypeName.isValidDynamicGTypeName(typeName) else {
            throw GStreamerError.invalidArgument(
                parameter: "typeName",
                reason: "typeName must be a valid dynamic GType name"
            )
        }
    }

    private static func validateMetadata(_ metadata: NativeElementMetadata) throws {
        try requireNonEmpty(metadata.klass, parameter: "metadata.klass")
        try requireNonEmpty(metadata.longName, parameter: "metadata.longName")
        try requireNonEmpty(metadata.description, parameter: "metadata.description")
        try requireNonEmpty(metadata.author, parameter: "metadata.author")
    }

    private static func validateCaps(_ caps: String, parameter: String) throws {
        do {
            let parsedCaps = try Caps(caps)
            guard gst_caps_is_empty(parsedCaps.caps) == 0 else {
                throw GStreamerError.invalidArgument(
                    parameter: parameter,
                    reason: "\(parameter) must not be empty"
                )
            }
        } catch {
            if case GStreamerError.invalidArgument = error {
                throw error
            } else {
                throw GStreamerError.invalidArgument(
                    parameter: parameter,
                    reason: "\(parameter) must parse as GStreamer caps"
                )
            }
        }
    }

    private static func requireNonEmpty(_ value: String, parameter: String) throws {
        guard !value.trimmingWhitespace().isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: parameter,
                reason: "\(parameter) must not be empty"
            )
        }
    }
}

private final class SwiftBaseSinkClassContext: @unchecked Sendable {
    let element: SwiftBaseSinkElement

    init(element: SwiftBaseSinkElement) {
        self.element = element
    }
}

private final class SwiftBaseSinkInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseSinkInstance

    init(instance: any SwiftBaseSinkInstance) {
        self.instance = instance
    }
}

private final class SwiftBaseTransformClassContext: @unchecked Sendable {
    let element: SwiftBaseTransformElement

    init(element: SwiftBaseTransformElement) {
        self.element = element
    }
}

private final class SwiftBaseTransformInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseTransformInstance

    init(instance: any SwiftBaseTransformInstance) {
        self.instance = instance
    }
}

private func swiftGstBaseSinkRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(context).retain()
}

private func swiftGstBaseSinkReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(context).release()
}

private func swiftGstBaseSinkCreateInstance(_ classContext: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let classContext else { return nil }
    let context = Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(classContext).takeUnretainedValue()
    let instanceContext = SwiftBaseSinkInstanceContext(instance: context.element.makeInstance())
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
        return try context.instance.render(borrowedBuffer).gstFlowReturn
    } catch {
        return GST_FLOW_ERROR
    }
}

private func swiftGstBaseTransformRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(context).retain()
}

private func swiftGstBaseTransformReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(context).release()
}

private func swiftGstBaseTransformCreateInstance(_ classContext: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let classContext else { return nil }
    let context = Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(classContext).takeUnretainedValue()
    let instanceContext = SwiftBaseTransformInstanceContext(instance: context.element.makeInstance())
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
        return try context.instance.transformInPlace(borrowedBuffer).gstFlowReturn
    } catch {
        return GST_FLOW_ERROR
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphaNumeric: Bool {
        isASCIILetter || isASCIIDigit
    }

    var isASCIILetter: Bool {
        ("A"..."Z").contains(self) || ("a"..."z").contains(self)
    }

    var isASCIIDigit: Bool {
        ("0"..."9").contains(self)
    }
}

private extension String {
    init(formatLowercaseHex value: UInt64) {
        let digits = Array("0123456789abcdef")
        var result = ""
        result.reserveCapacity(16)

        for shift in stride(from: 60, through: 0, by: -4) {
            let index = Int((value >> UInt64(shift)) & 0xf)
            result.append(digits[index])
        }

        self = result
    }
}
