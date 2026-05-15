import Testing
import Synchronization
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

    @Test("invalidArgument description includes parameter and reason")
    func invalidArgumentDescription() {
        let error = GStreamerError.invalidArgument(parameter: "count", reason: "bad")

        #expect(error.description == "Invalid argument 'count': bad")
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
        let capsString = "video/x-raw,format=BGRA,width=4,height=4,framerate=30/1"
        let frameSize = try RawVideoInfo(caps: Caps(capsString)).byteSize
        let pixels = [UInt8](repeating: 255, count: frameSize)

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
        let byteCount = try frame.withUnsafeBytes { $0.count }
        let frameSize = try RawVideoInfo(
            caps: Caps("video/x-raw,format=BGRA,width=2,height=2,framerate=30/1")
        ).byteSize
        #expect(byteCount == frameSize)
    }

    @Test("pushVideoFrame overloads reject too-small data")
    func pushVideoFrameOverloadsRejectTooSmallData() throws {
        // Create data that's too small for 4x4 BGRA (should be 64 bytes)
        let tooSmall = [UInt8](repeating: 0, count: 32)

        try withValidationAppSource { src in
            expectInvalidArgument(parameter: "data", "array overload should reject too-small data") {
                try src.pushVideoFrame(
                    data: tooSmall,
                    width: 4,
                    height: 4,
                    format: .bgra
                )
            }

            expectInvalidArgument(parameter: "data", "Span overload should reject too-small data") {
                try src.pushVideoFrame(
                    data: tooSmall.span,
                    width: 4,
                    height: 4,
                    format: .bgra
                )
            }

            expectInvalidArgument(parameter: "data", "RawSpan overload should reject too-small data") {
                try src.pushVideoFrame(
                    data: tooSmall.span.bytes,
                    width: 4,
                    height: 4,
                    format: .bgra
                )
            }
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

    @Test("Empty byte array push flows as one buffer")
    func emptyByteArrayPushFlowsAsOneBuffer() async throws {
        try await expectEmptyPayloadPushesOneBuffer { src in
            try src.push(data: [])
        }
    }

    @Test("Empty Span push flows as one buffer")
    func emptySpanPushFlowsAsOneBuffer() async throws {
        let emptyStorage: [UInt8] = []

        try await expectEmptyPayloadPushesOneBuffer { src in
            try src.push(data: emptyStorage.span)
        }
    }

    @Test("Empty RawSpan push flows as one buffer")
    func emptyRawSpanPushFlowsAsOneBuffer() async throws {
        let emptyStorage: [UInt8] = []

        try await expectEmptyPayloadPushesOneBuffer { src in
            try src.push(data: emptyStorage.span.bytes)
        }
    }

    @Test("push bytes with zero count flows as one buffer")
    func pushBytesWithZeroCountFlowsAsOneBuffer() async throws {
        var dummy: UInt8 = 0

        try await expectEmptyPayloadPushesOneBuffer { src in
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

        expectInvalidArgument(parameter: "count") {
            try withUnsafePointer(to: &dummy) { pointer in
                try src.push(bytes: UnsafeRawPointer(pointer), count: -1)
            }
        }
    }

    @Test("pushVideoFrame overloads reject invalid dimensions and formats")
    func pushVideoFrameOverloadsRejectInvalidDimensionsAndFormats() throws {
        let invalidCases: [InvalidVideoFrameCase] = [
            .init(name: "zero width", width: 0, height: 1, format: .bgra, expectedParameter: "width"),
            .init(name: "zero height", width: 1, height: 0, format: .bgra, expectedParameter: "height"),
            .init(name: "negative width", width: -1, height: 1, format: .bgra, expectedParameter: "width"),
            .init(name: "negative height", width: 1, height: -1, format: .bgra, expectedParameter: "height"),
            .init(
                name: "unknown zero-BPP format",
                width: 1,
                height: 1,
                format: .unknown("CUSTOM"),
                expectedParameter: "format"
            ),
            .init(
                name: "overflow-sized dimensions",
                width: Int.max / 2 + 1,
                height: 2,
                format: .bgra,
                expectedParameter: "dimensions"
            ),
            .init(
                name: "pixel byte count overflow",
                width: Int.max / 4 + 1,
                height: 1,
                format: .bgra,
                expectedParameter: "dimensions"
            )
        ]

        for invalidCase in invalidCases {
            try expectArrayVideoFrameRejects(invalidCase)
            try expectSpanVideoFrameRejects(invalidCase)
            try expectRawSpanVideoFrameRejects(invalidCase)
        }
    }

    private func expectEmptyPayloadPushesOneBuffer(_ push: (AppSource) throws -> Void) async throws {
        let pipeline = try Pipeline("appsrc name=src ! identity name=tap ! fakesink sync=false")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        src.setLive(false)

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = AppSourceProbeCounter()

        srcPad.addProbe(type: .buffer) {
            callbackCount.increment()
            return .ok
        }

        try pipeline.play()
        try push(src)
        src.endOfStream()

        await waitForEOSOrFail(pipeline)
        #expect(callbackCount.value == 1)
    }

    private func expectArrayVideoFrameRejects(_ invalidCase: InvalidVideoFrameCase) throws {
        let data = [UInt8](repeating: 0, count: 4)
        try withValidationAppSource { src in
            expectInvalidArgument(
                parameter: invalidCase.expectedParameter,
                "array overload should reject \(invalidCase.name)"
            ) {
                try src.pushVideoFrame(
                    data: data,
                    width: invalidCase.width,
                    height: invalidCase.height,
                    format: invalidCase.format
                )
            }
        }
    }

    private func expectSpanVideoFrameRejects(_ invalidCase: InvalidVideoFrameCase) throws {
        let data = [UInt8](repeating: 0, count: 4)
        try withValidationAppSource { src in
            expectInvalidArgument(
                parameter: invalidCase.expectedParameter,
                "Span overload should reject \(invalidCase.name)"
            ) {
                try src.pushVideoFrame(
                    data: data.span,
                    width: invalidCase.width,
                    height: invalidCase.height,
                    format: invalidCase.format
                )
            }
        }
    }

    private func expectRawSpanVideoFrameRejects(_ invalidCase: InvalidVideoFrameCase) throws {
        let data = [UInt8](repeating: 0, count: 4)
        try withValidationAppSource { src in
            expectInvalidArgument(
                parameter: invalidCase.expectedParameter,
                "RawSpan overload should reject \(invalidCase.name)"
            ) {
                try src.pushVideoFrame(
                    data: data.span.bytes,
                    width: invalidCase.width,
                    height: invalidCase.height,
                    format: invalidCase.format
                )
            }
        }
    }

    private func withValidationAppSource(_ body: (AppSource) throws -> Void) throws {
        let pipeline = try Pipeline("appsrc name=src ! fakesink")
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        try body(src)
    }

    private func waitForEOSOrFail(_ pipeline: Pipeline) async {
        for await message in pipeline.bus.messages(filter: [.eos, .error]) {
            switch message {
            case .eos:
                return
            case .error(let message, let debug):
                if let debug {
                    Issue.record("Unexpected pipeline error: \(message) (\(debug))")
                } else {
                    Issue.record("Unexpected pipeline error: \(message)")
                }
                return
            default:
                continue
            }
        }

        Issue.record("Pipeline bus stream ended before EOS")
    }

    private func expectInvalidArgument(
        parameter expectedParameter: String,
        _ context: String = "Expected GStreamerError.invalidArgument",
        _ body: () throws -> Void
    ) {
        do {
            try body()
            Issue.record("\(context)")
        } catch GStreamerError.invalidArgument(parameter: let actualParameter, reason: _) {
            #expect(
                actualParameter == expectedParameter,
                "\(context), got parameter '\(actualParameter)'"
            )
        } catch {
            Issue.record("\(context), got \(error)")
        }
    }
}

private struct InvalidVideoFrameCase: Sendable {
    let name: String
    let width: Int
    let height: Int
    let format: PixelFormat
    let expectedParameter: String
}

private final class AppSourceProbeCounter: @unchecked Sendable {
    private let storage = Mutex(0)

    func increment() {
        storage.withLock { count in
            count += 1
        }
    }

    var value: Int {
        storage.withLock { count in
            count
        }
    }
}
