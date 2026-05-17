import Testing
@testable import GStreamer

@Suite("Timestamp Tests", .timeLimit(.minutes(1)))
struct TimestampTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("VideoFrame has PTS")
    func videoFrameHasPTS() async throws {
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=3 ! \
            video/x-raw,format=BGRA,width=4,height=4,framerate=30/1 ! \
            appsink name=sink
            """
        )

        let sink = try AppSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var frameCount = 0
        var lastPts: UInt64 = 0

        for try await frame in sink.frames() {
            frameCount += 1

            let pts = try #require(frame.pts, "videotestsrc should set PTS")
            // PTS should increase monotonically
            if frameCount > 1 {
                #expect(pts >= lastPts)
            }
            lastPts = pts

            if frameCount >= 3 { break }
        }

        #expect(frameCount == 3)
    }

    @Test("VideoFrame has duration")
    func videoFrameHasDuration() async throws {
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=2 ! \
            video/x-raw,format=BGRA,width=4,height=4,framerate=30/1 ! \
            appsink name=sink
            """
        )

        let sink = try AppSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected a fixed-framerate video frame")
        let duration = try #require(frame.duration, "Fixed-framerate frames should include duration")
        // At 30fps, duration should be ~33.33ms = 33,333,333 ns
        #expect(duration > 30_000_000)
        #expect(duration < 40_000_000)
    }

    @Test("AppSource PTS is preserved")
    func appSourcePTSPreserved() async throws {
        let capsString = "video/x-raw,format=BGRA,width=2,height=2,framerate=30/1"
        let pipeline = try Pipeline(
            """
            appsrc name=src ! \
            \(capsString) ! \
            appsink name=sink
            """
        )

        let src = try AppSource(pipeline: pipeline, name: "src")
        let sink = try AppSink(pipeline: pipeline, name: "sink")

        src.setCaps(capsString)
        try pipeline.play()
        defer { pipeline.stop() }

        // Push frames with specific timestamps
        let pixels = [UInt8](repeating: 128, count: try RawVideoInfo(caps: Caps(capsString)).byteSize)
        let testPts: UInt64 = 500_000_000  // 500ms
        let testDuration: UInt64 = 33_333_333

        try src.push(data: pixels, pts: testPts, duration: testDuration)
        src.endOfStream()

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected AppSource to yield one frame")
        let pts = try #require(frame.pts, "AppSource PTS should be preserved")
        let duration = try #require(frame.duration, "AppSource duration should be preserved")
        #expect(pts == testPts)
        #expect(duration == testDuration)
    }

    @Test("Calculate FPS from duration")
    func calculateFPS() async throws {
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=1 ! \
            video/x-raw,format=BGRA,width=4,height=4,framerate=60/1 ! \
            appsink name=sink
            """
        )

        let sink = try AppSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected a fixed-framerate video frame")
        let duration = try #require(frame.duration, "Fixed-framerate frames should include duration")
        let fps = 1_000_000_000.0 / Double(duration)
        // Should be approximately 60fps
        #expect(fps > 55 && fps < 65)
    }
}
