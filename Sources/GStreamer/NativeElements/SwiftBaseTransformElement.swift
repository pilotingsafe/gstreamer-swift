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
