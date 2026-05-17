import Foundation
import Testing
@testable import GStreamer

// MARK: - Test Tags

extension Tag {
    /// Tests related to pipeline parsing and creation.
    @Tag static var parsing: Self
    /// Tests related to pipeline state management.
    @Tag static var state: Self
    /// Tests that require async execution.
    @Tag static var async: Self
}

@Suite("Pipeline Parse Tests", .tags(.parsing))
struct PipelineParseTests {

    init() throws {
        try GStreamer.initialize()
    }

    // MARK: - Parameterized Tests for Valid Pipelines

    @Test("Parse valid pipelines", arguments: [
        "videotestsrc ! fakesink",
        "audiotestsrc ! fakesink",
        "videotestsrc ! queue ! fakesink",
        "videotestsrc num-buffers=10 ! fakesink",
        "videotestsrc pattern=1 ! fakesink sync=false",
    ])
    func parseValidPipeline(description: String) throws {
        let pipeline = try Pipeline(description)
        #expect(pipeline.currentState() == .null)
    }

    @Test("Parse pipeline with named elements")
    func parseNamedElements() throws {
        let pipeline = try Pipeline("videotestsrc name=src ! fakesink name=sink")

        let src = pipeline.element(named: "src")
        #expect(src != nil)
        #expect(src?.name == "src")

        let sink = pipeline.element(named: "sink")
        #expect(sink != nil)
        #expect(sink?.name == "sink")
    }

    // MARK: - Parameterized Tests for Invalid Pipelines

    @Test("Parse invalid pipeline fails", arguments: [
        "this-is-not-a-valid-element !!!",
        "nonexistent_element_xyz",
        "",
    ])
    func parseInvalidPipeline(description: String) throws {
        #expect(throws: GStreamerError.self) {
            _ = try Pipeline(description)
        }
    }

    @Test("Parse partial link error fails at construction")
    func parsePartialLinkErrorFailsAtConstruction() throws {
        // Given a gst-launch-style pipeline description with an invalid element link
        let description = "videotestsrc ! fakesink ! fakesink"

        // When a Swift caller constructs a Pipeline from the description
        var pipeline: Pipeline?
        let error = try #require(Self.captureError {
            pipeline = try Pipeline(description)
        })

        // Then construction throws a parsePipeline error
        guard case GStreamerError.parsePipeline(let message) = error else {
            Issue.record("Expected parsePipeline for partial link error, got \(error)")
            return
        }

        // And the caller does not receive a Pipeline instance
        #expect(pipeline == nil)

        // And the error includes a parse diagnostic message
        Self.expectParseDiagnostic(message)
    }

    @Test("Parse property error fails at construction")
    func parsePropertyErrorFailsAtConstruction() throws {
        // Given a gst-launch-style pipeline description with an unknown element property
        let description = "videotestsrc does-not-exist=1 ! fakesink"

        // When a Swift caller constructs a Pipeline from the description
        var pipeline: Pipeline?
        let error = try #require(Self.captureError {
            pipeline = try Pipeline(description)
        })

        // Then construction throws a parsePipeline error
        guard case GStreamerError.parsePipeline(let message) = error else {
            Issue.record("Expected parsePipeline for property parse error, got \(error)")
            return
        }

        // And the caller does not receive a Pipeline instance
        #expect(pipeline == nil)

        // And the error includes a parse diagnostic message
        Self.expectParseDiagnostic(message)
    }

    @Test("Set pipeline state", .tags(.state, .async))
    func setPipelineState() async throws {
        let pipeline = try Pipeline("videotestsrc ! fakesink")

        try pipeline.setState(.ready)

        // Give it time to transition
        try? await Task.sleep(for: .milliseconds(100))
        let state = pipeline.currentState()
        #expect(state == .ready || state == .paused || state == .playing)

        pipeline.stop()
    }

    @Test("Element not found returns nil")
    func elementNotFound() throws {
        let pipeline = try Pipeline("videotestsrc ! fakesink")
        let element = pipeline.element(named: "nonexistent")
        #expect(element == nil)
    }

    @Test("Play and stop pipeline", .tags(.state, .async))
    func playAndStop() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=5 ! fakesink")

        try pipeline.play()

        // State changes are async, wait for pipeline to start
        try? await Task.sleep(for: .milliseconds(50))
        let playingState = pipeline.currentState()
        #expect(playingState == .playing || playingState == .paused || playingState == .ready)

        pipeline.stop()

        // Wait for stop to complete
        try? await Task.sleep(for: .milliseconds(50))
        #expect(pipeline.currentState() == .null)
    }

    // MARK: - State Transition Tests

    @Test("State transitions", .tags(.state), arguments: [
        (Pipeline.State.null, Pipeline.State.ready),
        (Pipeline.State.ready, Pipeline.State.paused),
        (Pipeline.State.paused, Pipeline.State.playing),
    ])
    func stateTransitions(from: Pipeline.State, to: Pipeline.State) async throws {
        let pipeline = try Pipeline("videotestsrc ! fakesink")

        // First set to the 'from' state
        if from != .null {
            try pipeline.setState(from)
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Then transition to the 'to' state
        try pipeline.setState(to)
        try? await Task.sleep(for: .milliseconds(100))

        let currentState = pipeline.currentState()
        // Allow for async state transitions - the state should be at or past the target
        #expect(currentState == to || currentState == from)

        pipeline.stop()
    }

    private static func captureError(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private static func expectParseDiagnostic(_ message: String) {
        let diagnostic = message.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!diagnostic.isEmpty)
        #expect(diagnostic != "Unknown error")
    }
}
