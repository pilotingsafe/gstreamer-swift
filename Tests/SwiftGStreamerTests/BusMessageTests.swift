import Testing
@testable import GStreamer

@Suite("Bus Message Tests", .timeLimit(.minutes(1)))
struct BusMessageTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Get bus from pipeline")
    func getBus() throws {
        let pipeline = try Pipeline("videotestsrc ! fakesink")
        let bus = pipeline.bus
        _ = bus // Bus should be non-nil (it's not optional)
    }

    @Test("Receive EOS message via AsyncStream")
    func receiveEOS() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        try pipeline.play()
        defer { pipeline.stop() }

        var receivedEOS = false
        for await message in pipeline.bus.messages(filter: [.eos, .error]) {
            switch message {
            case .eos:
                receivedEOS = true
            case .error(let msg, _):
                Issue.record("Unexpected error: \(msg)")
            default:
                break
            }
            if receivedEOS { break }
        }

        #expect(receivedEOS)
    }

    @Test("Receive state changed messages")
    func receiveStateChanged() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        try pipeline.play()
        defer { pipeline.stop() }

        var stateChangeCount = 0
        for await message in pipeline.bus.messages(filter: [.stateChanged, .eos]) {
            switch message {
            case .stateChanged:
                stateChangeCount += 1
            case .eos:
                break
            default:
                break
            }
            if case .eos = message { break }
        }

        // Should have received some state changes
        #expect(stateChangeCount > 0)
    }

    @Test("Missing file source fails to play deterministically")
    func errorMessageDetails() throws {
        let pipeline = try Pipeline("filesrc location=/definitely/missing/gstreamer-swift-test-input ! fakesink")
        defer { pipeline.stop() }

        do {
            try pipeline.play()
            Issue.record("Expected missing filesrc input to fail when the pipeline starts")
        } catch let error as GStreamerError {
            #expect(String(describing: error).contains("State change failed"))
        } catch {
            Issue.record("Expected GStreamerError for missing filesrc input, got \(error)")
        }
    }
}
