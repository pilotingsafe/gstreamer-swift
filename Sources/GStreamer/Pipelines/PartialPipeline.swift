/// Partially built launch string produced by the experimental typed pipeline DSL.
///
/// The generic `Element` parameter carries the current Swift frame type through
/// ``VideoPipelineBuilder``. The stored pipeline string is still a GStreamer
/// launch description, so direct ``Pipeline`` construction remains the core
/// lower-level API.
public struct PartialPipeline<Element: Sendable>: Sendable {
    internal var pipeline: String
    internal var sinkName: String?
    
    init(pipeline: String, sinkName: String? = nil) {
        self.pipeline = pipeline
        self.sinkName = sinkName
    }
}
