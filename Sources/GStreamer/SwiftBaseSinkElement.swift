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

    internal var baseSinkRenderGstFlowReturn: GstFlowReturn {
        switch self {
        case .dropped:
            return swift_gst_base_sink_flow_dropped()
        default:
            return gstFlowReturn
        }
    }

    internal var baseTransformGstFlowReturn: GstFlowReturn {
        switch self {
        case .dropped:
            return swift_gst_base_transform_flow_dropped()
        default:
            return gstFlowReturn
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

/// A case for a string-backed native element enum property.
///
/// String-backed enum properties are installed as string GObject properties.
/// The case `name` is the canonical stored value. The optional `nick` is an
/// additional accepted input spelling, and the optional `blurb` documents the
/// case for Swift authors and future introspection work.
public struct NativeElementEnumCase: Sendable {
    public var name: String
    public var nick: String?
    public var blurb: String?

    public init(name: String, nick: String? = nil, blurb: String? = nil) {
        self.name = name
        self.nick = nick
        self.blurb = blurb
    }
}

/// Native element property declaration for a Swift-backed native element.
///
/// Declarations are validated before C registration. Invalid declarations throw
/// during `GStreamer.register(_:)`, before any process-local factory is
/// registered. Runtime values outside a descriptor's Swift-side range or enum
/// cases are ignored so the previous valid value remains readable through
/// `Element` getters and callback readers.
public enum NativeElementProperty: Sendable {
    case bool(name: String, default: Bool, blurb: String)
    case int(name: String, default: Int, min: Int, max: Int, blurb: String)
    case double(name: String, default: Double, min: Double, max: Double, blurb: String)
    case string(name: String, default: String?, blurb: String)
    case stringEnum(name: String, default: String, cases: [NativeElementEnumCase], blurb: String)
}

/// Reads current native element property values from Swift callbacks.
///
/// A property reader is a thread-safe snapshot interface for callback code.
///
/// A reader is injected into property-aware native element factories before
/// lifecycle callbacks begin. Reads are thread-safe and return only values for
/// matching declared property kinds. String-backed enum properties are exposed
/// through ``enumCase(_:)`` and return canonical case names, never nicks.
public struct NativeElementPropertyReader: Sendable {
    private let store: NativeElementPropertyStore?

    fileprivate init(store: NativeElementPropertyStore?) {
        self.store = store
    }

    internal static let empty = NativeElementPropertyReader(store: nil)

    /// Returns a Bool property value, or nil if the property is unknown or has a different kind.
    public func bool(_ name: String) -> Bool? {
        store?.bool(name)
    }

    /// Returns an Int property value, or nil if the property is unknown or has a different kind.
    ///
    /// Returned Int values are backed by GObject `gint` storage and are known to
    /// fit in the Int32 range.
    public func int(_ name: String) -> Int? {
        store?.int(name)
    }

    /// Returns a Double property value, or nil if the property is unknown or has a different kind.
    public func double(_ name: String) -> Double? {
        store?.double(name)
    }

    /// Returns a nullable String property value.
    ///
    /// This returns nil for unknown properties, enum properties, and declared
    /// String properties whose current value is nil.
    public func string(_ name: String) -> String? {
        store?.string(name)
    }

    /// Returns a string-backed enum property's canonical case name.
    public func enumCase(_ name: String) -> String? {
        store?.enumCase(name)
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
    public let properties: [NativeElementProperty]
    public let makeInstance: @Sendable () -> any SwiftBaseSinkInstance
    internal let makeInstanceWithProperties: @Sendable (NativeElementPropertyReader) -> any SwiftBaseSinkInstance

    public init(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        properties: [NativeElementProperty] = [],
        makeInstance: @escaping @Sendable () -> any SwiftBaseSinkInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.properties = properties
        self.makeInstance = makeInstance
        self.makeInstanceWithProperties = { _ in makeInstance() }
    }

    public init(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        properties: [NativeElementProperty] = [],
        makeInstance: @escaping @Sendable (NativeElementPropertyReader) -> any SwiftBaseSinkInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.properties = properties
        self.makeInstance = { makeInstance(.empty) }
        self.makeInstanceWithProperties = makeInstance
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

/// A borrowed GStreamer buffer valid only for the transform callback scope.
///
/// Raw pointers received through ``withUnsafeBytes(_:)`` or
/// ``withUnsafeMutableBytes(_:)`` must not escape the closure. Read-only access
/// is attempted with ``withUnsafeBytes(_:)``. Mutable access is available only
/// when GStreamer provides a writable buffer. Use ``retainedReference()`` or
/// ``deepCopy()`` when data must outlive the callback.
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

    /// Maps the borrowed buffer for write access during the closure.
    ///
    /// Passthrough `transform_ip_on_passthrough` callbacks may receive a
    /// non-writable buffer. In that case, write mapping fails and this method
    /// throws ``GStreamerError/bufferMapFailed``.
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

/// Result returned by optional general out-of-place BaseTransform hooks.
///
/// The Swift bridge maps this enum to the C `SwiftGstBaseTransformHookStatus`
/// ABI values `SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT`,
/// `SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE`, and
/// `SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE`.
public enum BaseTransformHookResult<Value: Sendable>: Sendable {
    case useDefault
    case value(Value)
    case failure
}

/// Out-of-place BaseTransform allocation behavior.
public struct SwiftBaseTransformOutOfPlaceOptions: Sendable, Equatable {
    internal enum Mode: Sendable {
        case fixedSize
        case general
    }

    internal var mode: Mode

    /// Preserve the fixed-size Phase 4 behavior.
    public static let fixedSize = SwiftBaseTransformOutOfPlaceOptions(mode: .fixedSize)

    /// Use GStreamer's negotiated output allocation and general negotiation hooks.
    public static let general = SwiftBaseTransformOutOfPlaceOptions(mode: .general)
}

/// Snapshot of allocation parameters from a GStreamer allocation query.
public struct AllocationParams: Sendable {
    public var flags: UInt32
    public var align: Int
    public var prefix: Int
    public var padding: Int

    public init(flags: UInt32 = 0, align: Int = 0, prefix: Int = 0, padding: Int = 0) {
        self.flags = flags
        self.align = align
        self.prefix = prefix
        self.padding = padding
    }

    internal init(_ params: GstAllocationParams) {
        self.flags = UInt32(params.flags.rawValue)
        self.align = Int(params.align)
        self.prefix = Int(params.prefix)
        self.padding = Int(params.padding)
    }

    internal func withGstAllocationParams<R>(
        _ body: (UnsafePointer<GstAllocationParams>) throws -> R
    ) rethrows -> R? {
        guard align >= 0, prefix >= 0, padding >= 0 else {
            return nil
        }

        var params = GstAllocationParams()
        gst_allocation_params_init(&params)
        params.flags = GstMemoryFlags(rawValue: flags)
        params.align = gsize(align)
        params.prefix = gsize(prefix)
        params.padding = gsize(padding)
        return try withUnsafePointer(to: params, body)
    }
}

/// Snapshot of allocation metadata advertised by an allocation query.
public struct AllocationMetadata: Sendable {
    public var apiName: String
    public var paramsDescription: String?

    public init(apiName: String, paramsDescription: String? = nil) {
        self.apiName = apiName
        self.paramsDescription = paramsDescription
    }

    internal init(api: GType, params: UnsafePointer<GstStructure>?) {
        self.apiName = GLibString.borrow(swift_gst_g_type_name(api)) ?? ""
        self.paramsDescription = GLibString.takeOwnership(swift_gst_structure_to_string_nullable(params))
    }
}

public struct AllocationPoolConfiguration: Sendable {
    public var pool: AllocationPool?
    public var size: Int
    public var minimumBuffers: Int
    public var maximumBuffers: Int
}

/// Owned reference to a GStreamer buffer pool returned from an allocation query.
public final class AllocationPool: @unchecked Sendable {
    internal let pool: UnsafeMutablePointer<GstBufferPool>

    internal init(pool: UnsafeMutablePointer<GstBufferPool>) {
        self.pool = pool
    }

    deinit {
        swift_gst_object_unref(pool)
    }
}

/// Owned reference to a GStreamer allocator returned from an allocation query.
public final class BufferAllocator: @unchecked Sendable {
    internal let allocator: UnsafeMutablePointer<GstAllocator>

    internal init(allocator: UnsafeMutablePointer<GstAllocator>) {
        self.allocator = allocator
    }

    deinit {
        swift_gst_object_unref(allocator)
    }
}

public struct AllocationParamConfiguration: Sendable {
    public var allocator: BufferAllocator?
    public var params: AllocationParams
}

/// Borrowed allocation query wrapper scoped to a general-mode callback.
public struct AllocationQuery: ~Copyable {
    private let rawQuery: UnsafeMutablePointer<GstQuery>

    internal init(query: UnsafeMutablePointer<GstQuery>) {
        self.rawQuery = query
    }

    public var caps: Caps? {
        guard let caps = swift_gst_allocation_query_get_caps(rawQuery) else {
            return nil
        }
        return Caps(caps: caps, ownsReference: true)
    }

    public var needsPool: Bool {
        swift_gst_allocation_query_get_needs_pool(rawQuery) != 0
    }

    public var allocationPools: [AllocationPoolConfiguration] {
        (0..<Int(swift_gst_allocation_query_pool_count(rawQuery))).map { index in
            var size: guint = 0
            var minBuffers: guint = 0
            var maxBuffers: guint = 0
            let pool = swift_gst_allocation_query_pool_at(
                rawQuery,
                guint(index),
                &size,
                &minBuffers,
                &maxBuffers
            ).map { AllocationPool(pool: $0) }
            return AllocationPoolConfiguration(
                pool: pool,
                size: Int(size),
                minimumBuffers: Int(minBuffers),
                maximumBuffers: Int(maxBuffers)
            )
        }
    }

    public var allocationParams: [AllocationParamConfiguration] {
        (0..<Int(swift_gst_allocation_query_param_count(rawQuery))).map { index in
            var params = GstAllocationParams()
            gst_allocation_params_init(&params)
            let allocator = swift_gst_allocation_query_param_at(rawQuery, guint(index), &params)
                .map { BufferAllocator(allocator: $0) }
            return AllocationParamConfiguration(
                allocator: allocator,
                params: AllocationParams(params)
            )
        }
    }

    public var allocationMetadata: [AllocationMetadata] {
        (0..<Int(swift_gst_allocation_query_meta_count(rawQuery))).map { index in
            let api = swift_gst_allocation_query_meta_api_at(rawQuery, guint(index))
            return AllocationMetadata(
                apiName: GLibString.borrow(swift_gst_g_type_name(api)) ?? "",
                paramsDescription: GLibString.takeOwnership(
                    swift_gst_allocation_query_meta_params_string_at(rawQuery, guint(index))
                )
            )
        }
    }

    public func addPool(
        _ pool: AllocationPool?,
        size: Int,
        minimumBuffers: Int,
        maximumBuffers: Int
    ) {
        guard let gstSize = guint(exactly: size),
              let gstMinimumBuffers = guint(exactly: minimumBuffers),
              let gstMaximumBuffers = guint(exactly: maximumBuffers)
        else {
            return
        }

        swift_gst_allocation_query_add_pool(
            rawQuery,
            pool?.pool,
            gstSize,
            gstMinimumBuffers,
            gstMaximumBuffers
        )
    }

    public func addAllocationParam(_ allocator: BufferAllocator?, params: AllocationParams) {
        _ = params.withGstAllocationParams { gstParams in
            swift_gst_allocation_query_add_param(rawQuery, allocator?.allocator, gstParams)
        }
    }

    public func addAllocationMetadata(_ metadata: AllocationMetadata) {
        let type = g_type_from_name(metadata.apiName)
        guard type != 0 else {
            return
        }
        swift_gst_allocation_query_add_meta(rawQuery, type)
    }
}

/// Borrowed metadata wrapper scoped to a general-mode metadata callback.
public struct BufferMetadata: ~Copyable {
    private let rawMetadata: UnsafeMutablePointer<GstMeta>

    internal init(metadata: UnsafeMutablePointer<GstMeta>) {
        self.rawMetadata = metadata
    }

    public var apiName: String {
        GLibString.borrow(swift_gst_buffer_meta_api_name(rawMetadata)) ?? ""
    }

    public var implementationName: String {
        GLibString.borrow(swift_gst_buffer_meta_implementation_name(rawMetadata)) ?? ""
    }

    public var flags: UInt32 {
        UInt32(swift_gst_buffer_meta_flags(rawMetadata).rawValue)
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

/// Per-instance callbacks for a Swift-backed out-of-place BaseTransform element.
public protocol SwiftBaseTransformOutOfPlaceInstance: AnyObject, Sendable {
    func start() throws
    func stop()
    func setCaps(input: Caps, output: Caps) throws -> Bool

    /// Transform caps for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default transform_caps,
    /// `.value` with owned caps to handle the callback, or `.failure` to fail.
    func transformCaps(direction: Pad.Direction, caps: Caps, filter: Caps?) throws -> BaseTransformHookResult<Caps>

    /// Fixate caps for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default fixate_caps,
    /// `.value` with owned caps to handle the callback, or `.failure` to fail.
    func fixateCaps(direction: Pad.Direction, caps: Caps, otherCaps: Caps) throws -> BaseTransformHookResult<Caps>

    /// Report a unit size for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default get_unit_size,
    /// `.value` with a positive byte size, or `.failure` to fail.
    func getUnitSize(for caps: Caps) throws -> BaseTransformHookResult<Int>

    /// Transform a buffer size for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default transform_size,
    /// `.value` with a positive byte size, or `.failure` to fail.
    func transformSize(
        direction: Pad.Direction,
        caps: Caps,
        size: Int,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Int>

    /// Decide output allocation for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default decide_allocation,
    /// `.value` with true or false to handle it, or `.failure` to fail.
    func decideAllocation(_ query: borrowing AllocationQuery) throws -> BaseTransformHookResult<Bool>

    /// Propose input allocation for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default propose_allocation,
    /// `.value` with true or false to handle it, or `.failure` to fail.
    func proposeAllocation(
        decideQuery: borrowing AllocationQuery,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool>

    /// Filter allocation metadata for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default filter_meta,
    /// `.value` with true or false to handle it, or `.failure` to fail.
    func filterAllocationMetadata(
        _ metadata: AllocationMetadata,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool>

    /// Copy buffer metadata for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default copy_metadata,
    /// `.value` with true or false to handle it, or `.failure` to fail.
    func copyMetadata(
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool>

    /// Transform one metadata item for general mode.
    /// Return `.useDefault` to delegate to GStreamer's default transform_meta,
    /// `.value` with true or false to handle it, or `.failure` to fail.
    func transformMetadata(
        _ metadata: borrowing BufferMetadata,
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool>

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn
}

public extension SwiftBaseTransformOutOfPlaceInstance {
    func start() throws {}
    func stop() {}
    func setCaps(input: Caps, output: Caps) throws -> Bool { true }
    func transformCaps(direction: Pad.Direction, caps: Caps, filter: Caps?) throws -> BaseTransformHookResult<Caps> {
        .useDefault
    }
    func fixateCaps(direction: Pad.Direction, caps: Caps, otherCaps: Caps) throws -> BaseTransformHookResult<Caps> {
        .useDefault
    }
    func getUnitSize(for caps: Caps) throws -> BaseTransformHookResult<Int> {
        .useDefault
    }
    func transformSize(
        direction: Pad.Direction,
        caps: Caps,
        size: Int,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Int> {
        .useDefault
    }
    func decideAllocation(_ query: borrowing AllocationQuery) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }
    func proposeAllocation(
        decideQuery: borrowing AllocationQuery,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }
    func filterAllocationMetadata(
        _ metadata: AllocationMetadata,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }
    func copyMetadata(
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }
    func transformMetadata(
        _ metadata: borrowing BufferMetadata,
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }
}

/// Registration description for a Swift-backed in-place BaseTransform element.
public struct SwiftBaseTransformElement: Sendable {
    public let factoryName: String
    public let typeName: String?
    public let metadata: NativeElementMetadata
    public let sinkCaps: String
    public let srcCaps: String
    public let passthroughOptions: SwiftBaseTransformPassthroughOptions
    public let properties: [NativeElementProperty]
    public let makeInstance: @Sendable () -> any SwiftBaseTransformInstance
    internal let makeInstanceWithProperties: @Sendable (NativeElementPropertyReader) -> any SwiftBaseTransformInstance

    private init(
        factoryName: String,
        typeName: String?,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        passthroughOptions: SwiftBaseTransformPassthroughOptions,
        properties: [NativeElementProperty],
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance,
        makeInstanceWithProperties: @escaping @Sendable (NativeElementPropertyReader) -> any SwiftBaseTransformInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.srcCaps = srcCaps
        self.passthroughOptions = passthroughOptions
        self.properties = properties
        self.makeInstance = makeInstance
        self.makeInstanceWithProperties = makeInstanceWithProperties
    }

    public static func inPlace(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        passthroughOptions: SwiftBaseTransformPassthroughOptions = .default,
        properties: [NativeElementProperty] = [],
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata,
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            passthroughOptions: passthroughOptions,
            properties: properties,
            makeInstance: makeInstance,
            makeInstanceWithProperties: { _ in makeInstance() }
        )
    }

    public static func inPlace(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        passthroughOptions: SwiftBaseTransformPassthroughOptions = .default,
        properties: [NativeElementProperty] = [],
        makeInstance: @escaping @Sendable (NativeElementPropertyReader) -> any SwiftBaseTransformInstance
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata,
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            passthroughOptions: passthroughOptions,
            properties: properties,
            makeInstance: { makeInstance(.empty) },
            makeInstanceWithProperties: makeInstance
        )
    }
}

/// Registration description for a Swift-backed out-of-place BaseTransform element.
public struct SwiftBaseTransformOutOfPlaceElement: Sendable {
    public let factoryName: String
    public let typeName: String?
    public let metadata: NativeElementMetadata
    public let sinkCaps: String
    public let srcCaps: String
    public let options: SwiftBaseTransformOutOfPlaceOptions
    public let properties: [NativeElementProperty]
    public let makeInstance: @Sendable () -> any SwiftBaseTransformOutOfPlaceInstance
    internal let makeInstanceWithProperties: @Sendable (NativeElementPropertyReader) -> any SwiftBaseTransformOutOfPlaceInstance

    public init(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        properties: [NativeElementProperty] = [],
        options: SwiftBaseTransformOutOfPlaceOptions = .fixedSize,
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformOutOfPlaceInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.srcCaps = srcCaps
        self.options = options
        self.properties = properties
        self.makeInstance = makeInstance
        self.makeInstanceWithProperties = { _ in makeInstance() }
    }

    public init(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata,
        sinkCaps: String,
        srcCaps: String,
        properties: [NativeElementProperty] = [],
        options: SwiftBaseTransformOutOfPlaceOptions = .fixedSize,
        makeInstance: @escaping @Sendable (NativeElementPropertyReader) -> any SwiftBaseTransformOutOfPlaceInstance
    ) {
        self.factoryName = factoryName
        self.typeName = typeName
        self.metadata = metadata
        self.sinkCaps = sinkCaps
        self.srcCaps = srcCaps
        self.options = options
        self.properties = properties
        self.makeInstance = { makeInstance(.empty) }
        self.makeInstanceWithProperties = makeInstance
    }
}

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

/// A scoped borrowed GStreamer dynamic plugin context.
///
/// Values of this type are valid only for the synchronous
/// ``GStreamer/withDynamicPluginContext(rawPlugin:_:)`` body that receives
/// them. Store native element state in element instances, not in this context.
public struct NativeElementDynamicPluginContext: ~Copyable {
    fileprivate let rawPlugin: OpaquePointer

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

    static func generatedBaseTransformOutOfPlaceTypeName(factoryName: String) -> String {
        "SwiftGstNativeBaseTransformOutOfPlace_\(sanitizedFactoryNameComponent(factoryName))_\(fnv1a64Hex(factoryName))"
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

    fileprivate static func recordBaseTransformOutOfPlaceCRegistrationAttempt() {
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

    fileprivate static func recordStaticPluginCRegistrationAttempt(_ metadata: NativeStaticPluginMetadata) {
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

    fileprivate static func forcedStaticPluginInitFailureMessage(factoryName: String) -> String? {
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

    fileprivate static func recordPluginAwareBaseSinkRegistration(pluginIsNull: Bool) {
        pluginAwareNativeElementRegistrationState.withLock { state in
            guard state != nil else { return }
            if pluginIsNull {
                state?.nullPluginRegistrationCount += 1
            } else {
                state?.baseSinkNonNullPluginCount += 1
            }
        }
    }

    fileprivate static func recordPluginAwareBaseTransformRegistration(
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

    fileprivate static func recordStaticPluginContextRetain() {
        staticPluginContextRetainReleaseState.withLock { $0?.retainCount += 1 }
    }

    fileprivate static func recordStaticPluginContextRelease() {
        staticPluginContextRetainReleaseState.withLock { $0?.releaseCount += 1 }
    }

    fileprivate static func recordStaticPluginElementClassContextRelease() {
        staticPluginContextRetainReleaseState.withLock {
            $0?.elementClassContextReleaseCount += 1
        }
    }
}

private struct ValidatedBaseSinkRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var properties: [ValidatedNativeElementProperty]
}

private struct ValidatedBaseTransformRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var srcCaps: String
    var passthroughOptions: SwiftBaseTransformPassthroughOptions
    var properties: [ValidatedNativeElementProperty]
}

private struct ValidatedBaseTransformOutOfPlaceRegistration {
    var factoryName: String
    var typeName: String
    var metadata: NativeElementMetadata
    var sinkCaps: String
    var srcCaps: String
    var options: SwiftBaseTransformOutOfPlaceOptions
    var properties: [ValidatedNativeElementProperty]
}

private struct NativeStaticPluginMetadata: Sendable {
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

private enum NativeStaticPluginEntry {
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

private enum NativeStaticPluginRegistration {
    static func validate(_ entries: [NativeElementPluginEntry]) throws -> [NativeStaticPluginEntry] {
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

        try preflightNames(registrations)
        return registrations
    }

    private static func preflightNames(_ registrations: [NativeStaticPluginEntry]) throws {
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
            guard !factoryNameIsRegistered(registration.factoryName) else {
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

    private static func factoryNameIsRegistered(_ factoryName: String) -> Bool {
        factoryName.withCString { factoryName in
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
private final class NativeStaticPluginContext: @unchecked Sendable {
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

extension GStreamer {
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

fileprivate enum NativeElementBaseClass {
    case baseSink
    case baseTransform

    var diagnosticName: String {
        switch self {
        case .baseSink:
            return "BaseSink"
        case .baseTransform:
            return "BaseTransform"
        }
    }

    var gtype: GType {
        switch self {
        case .baseSink:
            return gst_base_sink_get_type()
        case .baseTransform:
            return gst_base_transform_get_type()
        }
    }
}

fileprivate enum NativePropertyKind: Sendable {
    case bool
    case int
    case double
    case string
    case stringEnum
}

fileprivate struct ValidatedNativeElementEnumCase: Sendable {
    var name: String
    var nick: String?
    var blurb: String?
}

fileprivate struct ValidatedNativeElementProperty: Sendable {
    var name: String
    var blurb: String
    var kind: NativePropertyKind
    var boolDefault: Bool
    var intDefault: Int32
    var intMin: Int32
    var intMax: Int32
    var doubleDefault: Double
    var doubleMin: Double
    var doubleMax: Double
    var stringDefault: String?
    var enumCases: [ValidatedNativeElementEnumCase]
    var enumDefault: String?
    var enumInputToCanonical: [String: String]

    var defaultValue: NativePropertyValue {
        switch kind {
        case .bool:
            return .bool(boolDefault)
        case .int:
            return .int(intDefault)
        case .double:
            return .double(doubleDefault)
        case .string:
            return .string(stringDefault)
        case .stringEnum:
            return .stringEnum(enumDefault ?? "")
        }
    }
}

fileprivate enum NativePropertyValue: Sendable {
    case bool(Bool)
    case int(Int32)
    case double(Double)
    case string(String?)
    case stringEnum(String)
}

// Safety invariant: descriptors and name indexes are immutable after init, and
// all mutable property values are accessed only while holding this Mutex.
fileprivate final class NativeElementPropertyStore: @unchecked Sendable {
    private let descriptors: [ValidatedNativeElementProperty]
    private let indexesByName: [String: Int]
    private let values: Mutex<[NativePropertyValue]>

    init(descriptors: [ValidatedNativeElementProperty]) {
        self.descriptors = descriptors
        self.indexesByName = Dictionary(uniqueKeysWithValues: descriptors.enumerated().map { index, descriptor in
            (descriptor.name, index)
        })
        self.values = Mutex(descriptors.map(\.defaultValue))
    }

    func bool(_ name: String) -> Bool? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .bool, case .bool(let boolValue) = value else {
                return nil
            }
            return boolValue
        }
    }

    func int(_ name: String) -> Int? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .int, case .int(let intValue) = value else {
                return nil
            }
            return Int(intValue)
        }
    }

    func double(_ name: String) -> Double? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .double, case .double(let doubleValue) = value else {
                return nil
            }
            return doubleValue
        }
    }

    func string(_ name: String) -> String? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .string, case .string(let stringValue) = value else {
                return nil
            }
            return stringValue
        }
    }

    func enumCase(_ name: String) -> String? {
        read(name: name) { descriptor, value in
            guard descriptor.kind == .stringEnum, case .stringEnum(let enumValue) = value else {
                return nil
            }
            return enumValue
        }
    }

    func setBool(index: Int, value: Bool) {
        update(index: index) { descriptor in
            guard descriptor.kind == .bool else { return nil }
            return .bool(value)
        }
    }

    func setInt(index: Int, value: Int32) {
        update(index: index) { descriptor in
            guard descriptor.kind == .int, descriptor.intMin...descriptor.intMax ~= value else {
                return nil
            }
            return .int(value)
        }
    }

    func setDouble(index: Int, value: Double) {
        update(index: index) { descriptor in
            guard descriptor.kind == .double,
                  value.isFinite,
                  descriptor.doubleMin...descriptor.doubleMax ~= value
            else {
                return nil
            }
            return .double(value)
        }
    }

    func setString(index: Int, value: String?) {
        update(index: index) { descriptor in
            switch descriptor.kind {
            case .string:
                return .string(value)
            case .stringEnum:
                guard let value, let canonical = descriptor.enumInputToCanonical[value] else {
                    return nil
                }
                return .stringEnum(canonical)
            case .bool, .int, .double:
                return nil
            }
        }
    }

    func bool(index: Int) -> Bool {
        read(index: index) { descriptor, value in
            guard descriptor.kind == .bool, case .bool(let boolValue) = value else {
                return false
            }
            return boolValue
        } ?? false
    }

    func int(index: Int) -> Int32 {
        read(index: index) { descriptor, value in
            guard descriptor.kind == .int, case .int(let intValue) = value else {
                return 0
            }
            return intValue
        } ?? 0
    }

    func double(index: Int) -> Double {
        read(index: index) { descriptor, value in
            guard descriptor.kind == .double, case .double(let doubleValue) = value else {
                return 0
            }
            return doubleValue
        } ?? 0
    }

    func stringForC(index: Int) -> UnsafeMutablePointer<CChar>? {
        let value: String? = read(index: index) { descriptor, value in
            switch (descriptor.kind, value) {
            case (.string, .string(let stringValue)):
                return stringValue
            case (.stringEnum, .stringEnum(let enumValue)):
                return enumValue
            default:
                return nil
            }
        } ?? nil

        guard let value else {
            return nil
        }
        return g_strdup(value)
    }

    private func read<T>(
        name: String,
        _ body: (ValidatedNativeElementProperty, NativePropertyValue) -> T?
    ) -> T? {
        guard let index = indexesByName[name] else {
            return nil
        }
        return read(index: index, body)
    }

    private func read<T>(
        index: Int,
        _ body: (ValidatedNativeElementProperty, NativePropertyValue) -> T?
    ) -> T? {
        guard descriptors.indices.contains(index) else {
            return nil
        }
        let descriptor = descriptors[index]
        return values.withLock { values in
            guard values.indices.contains(index) else {
                return nil
            }
            return body(descriptor, values[index])
        }
    }

    private func update(
        index: Int,
        _ value: (ValidatedNativeElementProperty) -> NativePropertyValue?
    ) {
        guard descriptors.indices.contains(index) else {
            return
        }
        let descriptor = descriptors[index]
        guard let newValue = value(descriptor) else {
            return
        }
        values.withLock { values in
            guard values.indices.contains(index) else {
                return
            }
            values[index] = newValue
        }
    }
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
        let properties = try validateProperties(element.properties, baseClass: .baseSink)

        return ValidatedBaseSinkRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            properties: properties
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
        let properties = try validateProperties(element.properties, baseClass: .baseTransform)

        return ValidatedBaseTransformRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            srcCaps: element.srcCaps,
            passthroughOptions: element.passthroughOptions,
            properties: properties
        )
    }

    static func validateBaseTransformOutOfPlace(
        _ element: SwiftBaseTransformOutOfPlaceElement
    ) throws -> ValidatedBaseTransformOutOfPlaceRegistration {
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
            let generated = NativeElementTypeName.generatedBaseTransformOutOfPlaceTypeName(
                factoryName: element.factoryName
            )
            try validateTypeName(generated)
            typeName = generated
        }

        try validateMetadata(element.metadata)
        try validateCaps(element.sinkCaps, parameter: "sinkCaps")
        try validateCaps(element.srcCaps, parameter: "srcCaps")
        let properties = try validateProperties(element.properties, baseClass: .baseTransform)

        return ValidatedBaseTransformOutOfPlaceRegistration(
            factoryName: element.factoryName,
            typeName: typeName,
            metadata: element.metadata,
            sinkCaps: element.sinkCaps,
            srcCaps: element.srcCaps,
            options: element.options,
            properties: properties
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

    private static func validateProperties(
        _ properties: [NativeElementProperty],
        baseClass: NativeElementBaseClass
    ) throws -> [ValidatedNativeElementProperty] {
        var names = Set<String>()
        var validated: [ValidatedNativeElementProperty] = []
        validated.reserveCapacity(properties.count)

        for property in properties {
            let name = property.propertyName
            try validatePropertyName(name)
            guard names.insert(name).inserted else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "duplicate native element property name '\(name)'"
                )
            }
            guard !inheritedPropertyExists(named: name, baseClass: baseClass) else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "\(baseClass.diagnosticName) property '\(name)' collides with an inherited GObject property"
                )
            }

            validated.append(try validateProperty(property))
        }

        return validated
    }

    private static func validateProperty(_ property: NativeElementProperty) throws -> ValidatedNativeElementProperty {
        switch property {
        case .bool(let name, let defaultValue, let blurb):
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .bool,
                boolDefault: defaultValue,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: nil,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .int(let name, let defaultValue, let min, let max, let blurb):
            guard let intMin = Int32(exactly: min),
                  let intMax = Int32(exactly: max),
                  let intDefault = Int32(exactly: defaultValue)
            else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Int property bounds and default must fit in Int32"
                )
            }
            guard intMin <= intMax else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Int property minimum must be less than or equal to maximum"
                )
            }
            guard intMin...intMax ~= intDefault else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Int property default must be within its descriptor range"
                )
            }
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .int,
                boolDefault: false,
                intDefault: intDefault,
                intMin: intMin,
                intMax: intMax,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: nil,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .double(let name, let defaultValue, let min, let max, let blurb):
            guard min.isFinite, max.isFinite, defaultValue.isFinite else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Double property bounds and default must be finite"
                )
            }
            guard min <= max else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Double property minimum must be less than or equal to maximum"
                )
            }
            guard min...max ~= defaultValue else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Double property default must be within its descriptor range"
                )
            }
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .double,
                boolDefault: false,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: defaultValue,
                doubleMin: min,
                doubleMax: max,
                stringDefault: nil,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .string(let name, let defaultValue, let blurb):
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .string,
                boolDefault: false,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: defaultValue,
                enumCases: [],
                enumDefault: nil,
                enumInputToCanonical: [:]
            )

        case .stringEnum(let name, let defaultValue, let cases, let blurb):
            let (enumCases, inputMap) = try validateEnumCases(cases, propertyName: name)
            guard let canonicalDefault = inputMap[defaultValue] else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(name)",
                    reason: "Enum property default must match a declared case name or nick"
                )
            }
            return ValidatedNativeElementProperty(
                name: name,
                blurb: blurb,
                kind: .stringEnum,
                boolDefault: false,
                intDefault: 0,
                intMin: 0,
                intMax: 0,
                doubleDefault: 0,
                doubleMin: 0,
                doubleMax: 0,
                stringDefault: canonicalDefault,
                enumCases: enumCases,
                enumDefault: canonicalDefault,
                enumInputToCanonical: inputMap
            )
        }
    }

    private static func validateEnumCases(
        _ cases: [NativeElementEnumCase],
        propertyName: String
    ) throws -> ([ValidatedNativeElementEnumCase], [String: String]) {
        guard !cases.isEmpty else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.\(propertyName)",
                reason: "Enum property must declare at least one case"
            )
        }

        var names = Set<String>()
        var nicks = Set<String>()
        var inputMap: [String: String] = [:]
        var validated: [ValidatedNativeElementEnumCase] = []
        validated.reserveCapacity(cases.count)

        for enumCase in cases {
            guard !enumCase.name.isEmpty else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(propertyName)",
                    reason: "Enum case names must not be empty"
                )
            }
            guard inputMap[enumCase.name] == nil else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(propertyName)",
                    reason: "Enum case names and nicks must not collide"
                )
            }
            guard names.insert(enumCase.name).inserted else {
                throw GStreamerError.invalidArgument(
                    parameter: "properties.\(propertyName)",
                    reason: "Enum case names must be unique"
                )
            }
            inputMap[enumCase.name] = enumCase.name

            if let nick = enumCase.nick {
                guard !nick.isEmpty else {
                    throw GStreamerError.invalidArgument(
                        parameter: "properties.\(propertyName)",
                        reason: "Enum case nicks must not be empty"
                    )
                }
                guard nicks.insert(nick).inserted else {
                    throw GStreamerError.invalidArgument(
                        parameter: "properties.\(propertyName)",
                        reason: "Enum case nicks must be unique"
                    )
                }
                guard inputMap[nick] == nil else {
                    throw GStreamerError.invalidArgument(
                        parameter: "properties.\(propertyName)",
                        reason: "Enum case names and nicks must not collide"
                    )
                }
                inputMap[nick] = enumCase.name
            }

            validated.append(
                ValidatedNativeElementEnumCase(
                    name: enumCase.name,
                    nick: enumCase.nick,
                    blurb: enumCase.blurb
                )
            )
        }

        return (validated, inputMap)
    }

    private static func validatePropertyName(_ name: String) throws {
        guard let first = name.unicodeScalars.first else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.name",
                reason: "property name must not be empty"
            )
        }
        guard first.isASCIILetter else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.\(name)",
                reason: "property name must start with an ASCII letter"
            )
        }
        guard name.unicodeScalars.allSatisfy({ $0.isASCIIAlphaNumeric || $0 == "-" }) else {
            throw GStreamerError.invalidArgument(
                parameter: "properties.\(name)",
                reason: "property name may contain only ASCII letters, digits, and hyphens"
            )
        }
    }

    private static func inheritedPropertyExists(
        named name: String,
        baseClass: NativeElementBaseClass
    ) -> Bool {
        let types: [GType] = [
            g_object_get_type(),
            gst_object_get_type(),
            gst_element_get_type(),
            baseClass.gtype,
        ]

        return types.contains { type in
            guard let klass = g_type_class_ref(type) else {
                return false
            }
            defer { g_type_class_unref(klass) }
            return name.withCString { namePointer in
                g_object_class_find_property(
                    klass.assumingMemoryBound(to: GObjectClass.self),
                    namePointer
                ) != nil
            }
        }
    }
}

private extension NativeElementProperty {
    var propertyName: String {
        switch self {
        case .bool(let name, _, _),
             .int(let name, _, _, _, _),
             .double(let name, _, _, _, _),
             .string(let name, _, _),
             .stringEnum(let name, _, _, _):
            return name
        }
    }
}

private final class SwiftBaseSinkClassContext: @unchecked Sendable {
    let element: SwiftBaseSinkElement
    let properties: [ValidatedNativeElementProperty]

    init(element: SwiftBaseSinkElement, properties: [ValidatedNativeElementProperty]) {
        self.element = element
        self.properties = properties
    }
}

private final class SwiftBaseSinkInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseSinkInstance
    let propertyStore: NativeElementPropertyStore

    init(instance: any SwiftBaseSinkInstance, propertyStore: NativeElementPropertyStore) {
        self.instance = instance
        self.propertyStore = propertyStore
    }
}

private final class SwiftBaseTransformClassContext: @unchecked Sendable {
    let element: SwiftBaseTransformElement
    let properties: [ValidatedNativeElementProperty]

    init(element: SwiftBaseTransformElement, properties: [ValidatedNativeElementProperty]) {
        self.element = element
        self.properties = properties
    }
}

private final class SwiftBaseTransformInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseTransformInstance
    let propertyStore: NativeElementPropertyStore

    init(instance: any SwiftBaseTransformInstance, propertyStore: NativeElementPropertyStore) {
        self.instance = instance
        self.propertyStore = propertyStore
    }
}

private final class SwiftBaseTransformOutOfPlaceClassContext: @unchecked Sendable {
    let element: SwiftBaseTransformOutOfPlaceElement
    let properties: [ValidatedNativeElementProperty]

    init(element: SwiftBaseTransformOutOfPlaceElement, properties: [ValidatedNativeElementProperty]) {
        self.element = element
        self.properties = properties
    }
}

private final class SwiftBaseTransformOutOfPlaceInstanceContext: @unchecked Sendable {
    let instance: any SwiftBaseTransformOutOfPlaceInstance
    let propertyStore: NativeElementPropertyStore

    init(instance: any SwiftBaseTransformOutOfPlaceInstance, propertyStore: NativeElementPropertyStore) {
        self.instance = instance
        self.propertyStore = propertyStore
    }
}

private final class NativePropertyCDescriptorStorage {
    let descriptors: UnsafeMutablePointer<SwiftGstNativePropertyDescriptor>?
    let count: guint

    private var strings: [UnsafeMutablePointer<CChar>] = []
    private var enumCaseArrays: [UnsafeMutablePointer<SwiftGstNativeEnumCaseDescriptor>] = []

    init(properties: [ValidatedNativeElementProperty]) {
        self.count = guint(properties.count)
        guard !properties.isEmpty else {
            self.descriptors = nil
            return
        }

        let descriptors = UnsafeMutablePointer<SwiftGstNativePropertyDescriptor>.allocate(capacity: properties.count)
        self.descriptors = descriptors

        for (index, property) in properties.enumerated() {
            let enumCases = makeEnumCaseArray(property.enumCases)
            descriptors[index] = SwiftGstNativePropertyDescriptor(
                name: makeCString(property.name),
                blurb: makeCString(property.blurb),
                kind: property.cKind,
                bool_default: property.boolDefault ? 1 : 0,
                int_default: property.intDefault,
                int_min: property.intMin,
                int_max: property.intMax,
                double_default: property.doubleDefault,
                double_min: property.doubleMin,
                double_max: property.doubleMax,
                string_default: makeCString(property.stringDefault),
                enum_cases: enumCases,
                enum_case_count: guint(property.enumCases.count)
            )
        }
    }

    deinit {
        for pointer in strings {
            g_free(pointer)
        }
        for pointer in enumCaseArrays {
            pointer.deallocate()
        }
        descriptors?.deallocate()
    }

    private func makeCString(_ value: String?) -> UnsafePointer<CChar>? {
        guard let value else {
            return nil
        }
        guard let pointer = value.withCString({ g_strdup($0) }) else {
            return nil
        }
        strings.append(pointer)
        return UnsafePointer(pointer)
    }

    private func makeEnumCaseArray(
        _ enumCases: [ValidatedNativeElementEnumCase]
    ) -> UnsafePointer<SwiftGstNativeEnumCaseDescriptor>? {
        guard !enumCases.isEmpty else {
            return nil
        }
        let pointer = UnsafeMutablePointer<SwiftGstNativeEnumCaseDescriptor>.allocate(capacity: enumCases.count)
        enumCaseArrays.append(pointer)
        for (index, enumCase) in enumCases.enumerated() {
            pointer[index] = SwiftGstNativeEnumCaseDescriptor(
                name: makeCString(enumCase.name),
                nick: makeCString(enumCase.nick),
                blurb: makeCString(enumCase.blurb)
            )
        }
        return UnsafePointer(pointer)
    }
}

private extension ValidatedNativeElementProperty {
    var cKind: SwiftGstNativePropertyKind {
        switch kind {
        case .bool:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_BOOL
        case .int:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_INT
        case .double:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_DOUBLE
        case .string:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_STRING
        case .stringEnum:
            return SWIFT_GST_NATIVE_PROPERTY_KIND_STRING_ENUM
        }
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

private func swiftGstBaseSinkCallbacks() -> SwiftGstBaseSinkCallbacks {
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

private func swiftGstBaseTransformCallbacks() -> SwiftGstBaseTransformCallbacks {
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

private func swiftGstBaseTransformOutOfPlaceCallbacks(
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

private func swiftGstBaseSinkRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseSinkClassContext>.fromOpaque(context).retain()
}

private func swiftGstBaseSinkReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
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

private func swiftGstBaseTransformRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseTransformClassContext>.fromOpaque(context).retain()
}

private func swiftGstBaseTransformReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
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

private func swiftGstBaseTransformOutOfPlaceRetainClassContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    _ = Unmanaged<SwiftBaseTransformOutOfPlaceClassContext>.fromOpaque(context).retain()
}

private func swiftGstBaseTransformOutOfPlaceReleaseClassContext(_ context: UnsafeMutableRawPointer?) {
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
