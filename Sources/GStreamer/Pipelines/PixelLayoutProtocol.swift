/// Pixel layout carried through the experimental typed pipeline DSL.
///
/// Layout types encode a GStreamer raw-video format plus static dimensions for
/// builder-time composition. They are convenience type markers; runtime frame
/// access still goes through the low-level ``VideoFrame`` APIs.
public protocol PixelLayoutProtocol: Sendable {
    /// GStreamer raw-video format name, such as `BGRA`.
    static var name: String { get }

    /// Caps options appended for this layout, such as width and height.
    static var options: [String] { get }

    /// The layout type after a 90° or 270° rotation (width and height swapped).
    associatedtype Rotated: PixelLayoutProtocol
}

/// Typed RGBA layout with static width and height.
public enum RGBA<
    let width: Int,
    let height: Int
>: PixelLayoutProtocol {
    public static var name: String { "RGBA" }
    public static var options: [String] { [
        "width=\(width)",
        "height=\(height)",
    ] }
    public typealias Rotated = RGBA<height, width>
}

/// Typed BGRA layout with static width and height.
public enum BGRA<
    let width: Int,
    let height: Int
>: PixelLayoutProtocol {
    public static var name: String { "BGRA" }
    public static var options: [String] { [
        "width=\(width)",
        "height=\(height)",
    ] }
    public typealias Rotated = BGRA<height, width>
}

/// Typed NV12 layout with static width and height.
public enum NV12<
    let width: Int,
    let height: Int
>: PixelLayoutProtocol {
    public static var name: String { "NV12" }
    public static var options: [String] { [
        "width=\(width)",
        "height=\(height)",
    ] }
    public typealias Rotated = NV12<height, width>
}

/// Typed I420 layout with static width and height.
public enum I420<
    let width: Int,
    let height: Int
>: PixelLayoutProtocol {
    public static var name: String { "I420" }
    public static var options: [String] { [
        "width=\(width)",
        "height=\(height)",
    ] }
    public typealias Rotated = I420<height, width>
}

/// Typed GRAY8 layout with static width and height.
public enum GRAY8<
    let width: Int,
    let height: Int
>: PixelLayoutProtocol {
    public static var name: String { "GRAY8" }
    public static var options: [String] { [
        "width=\(width)",
        "height=\(height)",
    ] }
    public typealias Rotated = GRAY8<height, width>
}
