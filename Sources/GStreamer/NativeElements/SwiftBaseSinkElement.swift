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
