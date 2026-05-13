/// Frame type accepted by the experimental typed pipeline DSL.
///
/// Conforming types can be initialized from the low-level ``VideoFrame`` value
/// emitted by ``AppSink``. The conversion is intentionally a DSL bridge; direct
/// ``VideoFrame`` handling remains the core frame API.
public protocol VideoFrameProtocol: Sendable {
    /// Create the typed frame wrapper from a low-level frame value.
    init(unsafeCast: VideoFrame)
}

extension VideoFrame: VideoFrameProtocol {
    public init(unsafeCast: VideoFrame) {
        self = unsafeCast
    }
}

/// Typed frame wrapper that carries a compile-time pixel layout.
///
/// `_VideoFrame` belongs to the experimental typed pipeline layer and stores
/// the underlying low-level ``VideoFrame`` for actual byte and metadata access.
public struct _VideoFrame<
    PixelLayout: PixelLayoutProtocol
>: VideoFrameProtocol {
    /// The low-level frame value emitted by appsink.
    public let rawFrame: VideoFrame

    public init(unsafeCast: VideoFrame) {
        self.rawFrame = unsafeCast
    }
}
