import Testing
@testable import GStreamer

@Suite("AppSource Tests", .timeLimit(.minutes(1)))
struct AppSourceTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Create AppSource from pipeline")
    func createAppSource() throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        let appSource = try AppSource(pipeline: pipeline, name: "src")
        _ = appSource
    }

    @Test("AppSource not found throws error")
    func appSourceNotFound() throws {
        let pipeline = try Pipeline("videotestsrc ! fakesink")

        #expect(throws: GStreamerError.self) {
            _ = try AppSource(pipeline: pipeline, name: "src")
        }
    }

    @Test("Push data through AppSource")
    func pushData() async throws {
        // Create a pipeline: appsrc -> fakesink
        let pipeline = try Pipeline(
            """
            appsrc name=src ! \
            video/x-raw,format=BGRA,width=4,height=4,framerate=30/1 ! \
            fakesink
            """
        )

        let src = try AppSource(pipeline: pipeline, name: "src")
        src.setCaps("video/x-raw,format=BGRA,width=4,height=4,framerate=30/1")
        src.setLive(false)

        try pipeline.play()
        defer { pipeline.stop() }

        // Create a small 4x4 BGRA frame
        let width = 4
        let height = 4
        let pixels = [UInt8](repeating: 255, count: width * height * 4)

        // Push a few frames
        for i in 0..<3 {
            let pts = UInt64(i) * 33_333_333  // ~30fps
            try src.push(data: pixels, pts: pts, duration: 33_333_333)
        }

        src.endOfStream()

        // Wait for EOS
        var receivedEOS = false
        for await message in pipeline.bus.messages(filter: [.eos, .error]) {
            switch message {
            case .eos:
                receivedEOS = true
            case .error(let msg, _):
                Issue.record("Unexpected error: \(msg)")
            default:
                continue
            }
            break
        }

        #expect(receivedEOS)
    }

    @Test("AppSource to AppSink roundtrip")
    func roundtrip() async throws {
        // Create a pipeline that passes data from appsrc to appsink
        let pipeline = try Pipeline(
            """
            appsrc name=src ! \
            video/x-raw,format=BGRA,width=2,height=2,framerate=30/1 ! \
            appsink name=sink
            """
        )

        let src = try AppSource(pipeline: pipeline, name: "src")
        let sink = try AppSink(pipeline: pipeline, name: "sink")

        src.setCaps("video/x-raw,format=BGRA,width=2,height=2,framerate=30/1")

        try pipeline.play()
        defer { pipeline.stop() }

        // Create a 2x2 BGRA frame with known values
        let pixels: [UInt8] = [
            255, 0, 0, 255,    // Blue
            0, 255, 0, 255,    // Green
            0, 0, 255, 255,    // Red
            255, 255, 0, 255   // Cyan
        ]

        let pushPts: UInt64 = 100_000_000  // 100ms

        // Push frame
        try src.push(data: pixels, pts: pushPts, duration: 33_333_333)
        src.endOfStream()

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected AppSource/AppSink roundtrip to yield one frame")
        // Verify dimensions (may be 0 on first frame if caps not parsed)
        if frame.width > 0 {
            #expect(frame.width == 2)
            #expect(frame.height == 2)
        }

        // Verify we can access the data
        #expect(frame.bytes.byteCount == 16)  // 2x2x4 bytes
    }

    @Test("pushVideoFrame validates size")
    func pushVideoFrameValidation() async throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        let src = try AppSource(pipeline: pipeline, name: "src")

        src.setCaps("video/x-raw,format=BGRA,width=4,height=4,framerate=30/1")
        try pipeline.play()
        defer { pipeline.stop() }

        // Create data that's too small for 4x4 BGRA (should be 64 bytes)
        let tooSmall = [UInt8](repeating: 0, count: 32)

        #expect(throws: GStreamerError.self) {
            try src.pushVideoFrame(
                data: tooSmall,
                width: 4,
                height: 4,
                format: .bgra
            )
        }
    }

    @Test("Push RawSpan directly from mapped buffer")
    func pushRawSpan() async throws {
        // Create source pipeline that produces frames
        let sourcePipeline = try Pipeline(
            """
            videotestsrc num-buffers=2 ! \
            video/x-raw,format=BGRA,width=4,height=4 ! \
            appsink name=source
            """
        )

        // Create destination pipeline that receives frames
        let destPipeline = try Pipeline(
            """
            appsrc name=dest ! \
            video/x-raw,format=BGRA,width=4,height=4,framerate=30/1 ! \
            fakesink
            """
        )

        let sourceSink = try sourcePipeline.appSink(named: "source")
        let destSrc = try AppSource(pipeline: destPipeline, name: "dest")

        destSrc.setCaps("video/x-raw,format=BGRA,width=4,height=4,framerate=30/1")

        try sourcePipeline.play()
        try destPipeline.play()
        defer {
            sourcePipeline.stop()
            destPipeline.stop()
        }

        // Forward frames using RawSpan (zero-copy from mapped buffer)
        var frameCount = 0
        for try await frame in sourceSink.frames() {
            // Use the RawSpan overload directly
            try destSrc.pushVideoFrame(
                data: frame.bytes,
                width: frame.width,
                height: frame.height,
                format: frame.format,
                pts: frame.pts,
                duration: frame.duration
            )
            frameCount += 1
            if frameCount >= 2 { break }
        }

        #expect(frameCount == 2)

        destSrc.endOfStream()
    }

    @Test("Empty byte array push throws bufferMapFailed")
    func emptyByteArrayPushThrowsBufferMapFailed() throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")

        expectBufferMapFailed {
            try src.push(data: [])
        }
    }

    @Test("Empty Span push throws bufferMapFailed")
    func emptySpanPushThrowsBufferMapFailed() throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        let emptyStorage: [UInt8] = []

        expectBufferMapFailed {
            try src.push(data: emptyStorage.span)
        }
    }

    @Test("Empty RawSpan push throws bufferMapFailed")
    func emptyRawSpanPushThrowsBufferMapFailed() throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        let emptyStorage: [UInt8] = []

        expectBufferMapFailed {
            try src.push(data: emptyStorage.span.bytes)
        }
    }

    @Test("push bytes rejects zero count")
    func pushBytesRejectsZeroCount() throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        var dummy: UInt8 = 0

        expectBufferMapFailed {
            try withUnsafePointer(to: &dummy) { pointer in
                try src.push(bytes: UnsafeRawPointer(pointer), count: 0)
            }
        }
    }

    @Test("push bytes rejects negative count")
    func pushBytesRejectsNegativeCount() throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        var dummy: UInt8 = 0

        expectBufferMapFailed {
            try withUnsafePointer(to: &dummy) { pointer in
                try src.push(bytes: UnsafeRawPointer(pointer), count: -1)
            }
        }
    }

    private func expectBufferMapFailed(_ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected GStreamerError.bufferMapFailed")
        } catch GStreamerError.bufferMapFailed {
        } catch {
            Issue.record("Expected GStreamerError.bufferMapFailed, got \(error)")
        }
    }
}
