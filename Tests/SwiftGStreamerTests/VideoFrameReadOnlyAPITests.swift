import Testing
@testable import GStreamer

@Suite("VideoFrame Read-Only API Tests", .timeLimit(.minutes(1)))
struct VideoFrameReadOnlyAPITests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("BGRA frame exposes retained read-only byte counts")
    func bgraFrameReadOnlyByteViewsExposeExpectedCount() async throws {
        let width = 4
        let height = 3
        let expectedByteCount = try RawVideoInfo(
            caps: Caps("video/x-raw,format=BGRA,width=\(width),height=\(height)")
        ).byteSize
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=1 pattern=white ! \
            video/x-raw,format=BGRA,width=\(width),height=\(height) ! \
            appsink name=sink
            """
        )
        defer { pipeline.stop() }

        let sink = try pipeline.appSink(named: "sink")
        try pipeline.play()

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame)
        let bytesByteCount = frame.bytes.byteCount
        #expect(bytesByteCount == expectedByteCount)

        let unsafeByteCount = try frame.withUnsafeBytes { bytes in
            bytes.count
        }
        #expect(unsafeByteCount == expectedByteCount)
    }
}
