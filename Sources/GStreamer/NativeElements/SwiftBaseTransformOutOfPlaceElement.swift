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
