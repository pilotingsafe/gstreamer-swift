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
        guard let copied = gst_buffer_copy(buffer) else {
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

/// Placeholder for Phase 2 Swift-backed BaseTransform instances.
public protocol SwiftBaseTransformInstance: AnyObject, Sendable {}

/// Placeholder borrowed mutable buffer for Phase 2 transform callbacks.
public struct MutableBorrowedBuffer: ~Copyable {}

/// Placeholder for Phase 2 Swift-backed BaseTransform registration.
public struct SwiftBaseTransformElement: Sendable {
    private init() {}

    @available(*, unavailable, message: "Swift-backed BaseTransform is planned for Phase 2.")
    public static func inPlace(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance
    ) -> SwiftBaseTransformElement {
        fatalError("Swift-backed BaseTransform is planned for Phase 2.")
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

    @available(*, unavailable, message: "Swift-backed BaseTransform registration is planned for Phase 2.")
    public static func register(_ element: SwiftBaseTransformElement) throws {
        fatalError("Swift-backed BaseTransform registration is planned for Phase 2.")
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
}

private struct ValidatedBaseSinkRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
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

        do {
            let parsedCaps = try Caps(element.sinkCaps)
            guard gst_caps_is_empty(parsedCaps.caps) == 0 else {
                throw GStreamerError.invalidArgument(
                    parameter: "sinkCaps",
                    reason: "sinkCaps must not be empty"
                )
            }
        } catch {
            if case GStreamerError.invalidArgument = error {
                throw error
            } else {
                throw GStreamerError.invalidArgument(
                    parameter: "sinkCaps",
                    reason: "sinkCaps must parse as GStreamer caps"
                )
            }
        }

        return ValidatedBaseSinkRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps
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
