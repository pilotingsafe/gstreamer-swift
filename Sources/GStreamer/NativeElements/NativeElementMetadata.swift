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
