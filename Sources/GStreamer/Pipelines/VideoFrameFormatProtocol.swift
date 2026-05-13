/// Video caps format carried by the experimental typed pipeline DSL.
///
/// Format types describe the caps segment that maps a typed layout to a
/// GStreamer media type. Direct caps strings and ``Caps`` remain the low-level
/// API for custom pipelines.
public protocol VideoFrameFormatProtocol: Sendable {
    /// GStreamer media type name, such as `x-raw`.
    static var name: String { get }

    /// Caps options emitted for this typed format.
    static var options: [String] { get }
}

/// Raw video frame format for a statically typed pixel layout.
public enum RawVideoFrameFormat<
    PixelLayout: PixelLayoutProtocol
>: VideoFrameFormatProtocol {
    public static var name: String { "x-raw" }
    public static var options: [String] { 
        [
            "format=\(PixelLayout.name)",
        ]
    }
}
