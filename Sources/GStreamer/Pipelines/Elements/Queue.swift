/// Queue leaky behavior when full.
public enum QueueLeaky: Int, Sendable {
    /// Not leaky; block the upstream producer when full. Equivalent to GStreamer `leaky=0`.
    case none = 0
    /// Leaky on the upstream side; drop newest/incoming buffers when full; keep oldest queued.
    /// Equivalent to GStreamer `leaky=1`.
    case upstream = 1
    /// Leaky on the downstream side; drop oldest/queued buffers when full; keep newest.
    /// Equivalent to GStreamer `leaky=2`.
    case downstream = 2
}

/// A pipeline element that buffers data between elements.
///
/// Queue decouples the data flow between elements, allowing each to run at its own pace.
/// This is useful for:
/// - Preventing upstream elements from blocking
/// - Adding threading boundaries
/// - Handling bursty data
///
/// Queue preserves the frame layout type in typed pipelines automatically.
///
/// ## Example
///
/// ```swift
/// @VideoPipelineBuilder
/// func bufferedPipeline() -> PartialPipeline<_VideoFrame<BGRA<1920, 1080>>> {
///     TypedVideoTestSource<BGRA<1920, 1080>>()
///     Queue(maxBuffers: 5)  // Layout inferred
///     VideoConvert()
/// }
/// ```
public struct Queue: TypedConvertible, VideoPipelineConvert {
    public typealias VideoFrameInput = VideoFrame
    public typealias VideoFrameOutput = VideoFrame

    public func _asTypedConvert<Layout: PixelLayoutProtocol>(_ layout: Layout.Type) -> AnyTypedConvert<Layout> {
        AnyTypedConvert<Layout>(pipeline: self.pipeline)
    }

    private let maxBuffers: UInt?
    private let maxBytes: UInt?
    private let maxTime: UInt64?
    private let leaky: QueueLeaky?

    public var pipeline: String {
        var options = ["queue"]
        if let maxBuffers {
            options.append("max-size-buffers=\(maxBuffers)")
        }
        if let maxBytes {
            options.append("max-size-bytes=\(maxBytes)")
        }
        if let maxTime {
            options.append("max-size-time=\(maxTime)")
        }
        if let leaky {
            options.append("leaky=\(leaky.rawValue)")
        }
        return options.joined(separator: " ")
    }

    /// Create a Queue element with default settings.
    public init() {
        self.maxBuffers = nil
        self.maxBytes = nil
        self.maxTime = nil
        self.leaky = nil
    }

    /// Create a Queue element with specified limits.
    ///
    /// - Parameters:
    ///   - maxBuffers: Maximum number of buffers to queue.
    ///   - maxBytes: Maximum bytes to queue.
    ///   - maxTime: Maximum time to queue in nanoseconds.
    ///   - leaky: Behavior when queue is full.
    public init(
        maxBuffers: UInt? = nil,
        maxBytes: UInt? = nil,
        maxTime: UInt64? = nil,
        leaky: QueueLeaky? = nil
    ) {
        self.maxBuffers = maxBuffers
        self.maxBytes = maxBytes
        self.maxTime = maxTime
        self.leaky = leaky
    }

    /// Create a leaky queue that drops oldest queued buffers when full so the consumer sees
    /// the most recent live data.
    ///
    /// Useful where latency is preserved over completeness. Equivalent to GStreamer `leaky=2`.
    public static func leaky(maxBuffers: UInt = 1) -> Queue {
        Queue(maxBuffers: maxBuffers, leaky: .downstream)
    }
}
