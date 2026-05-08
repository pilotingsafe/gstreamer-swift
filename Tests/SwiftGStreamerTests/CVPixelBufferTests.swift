#if canImport(CoreVideo)
import Testing
import CoreVideo
@testable import GStreamer

@Suite("CVPixelBuffer Tests", .timeLimit(.minutes(1)))
struct CVPixelBufferTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Convert BGRA frame to CVPixelBuffer")
    func convertBGRAFrame() async throws {
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=1 ! \
            video/x-raw,format=BGRA,width=64,height=64 ! \
            appsink name=sink
            """
        )

        let sink = try pipeline.appSink(named: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected one BGRA frame")
        let pixelBuffer = try frame.toCVPixelBuffer()
        let pb = try #require(pixelBuffer, "Expected BGRA frame to convert to CVPixelBuffer")

        #expect(CVPixelBufferGetWidth(pb) == 64)
        #expect(CVPixelBufferGetHeight(pb) == 64)
        #expect(CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA)
    }

    @Test("Convert NV12 frame to CVPixelBuffer")
    func convertNV12Frame() async throws {
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=1 ! \
            video/x-raw,format=NV12,width=64,height=64 ! \
            appsink name=sink
            """
        )

        let sink = try pipeline.appSink(named: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected one NV12 frame")
        let pixelBuffer = try frame.toCVPixelBuffer()
        let pb = try #require(pixelBuffer, "Expected NV12 frame to convert to CVPixelBuffer")

        #expect(CVPixelBufferGetWidth(pb) == 64)
        #expect(CVPixelBufferGetHeight(pb) == 64)
        #expect(CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        #expect(CVPixelBufferIsPlanar(pb))
    }

    @Test("Convert I420 frame to CVPixelBuffer")
    func convertI420Frame() async throws {
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=1 ! \
            video/x-raw,format=I420,width=64,height=64 ! \
            appsink name=sink
            """
        )

        let sink = try pipeline.appSink(named: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstFrame: VideoFrame?
        for try await frame in sink.frames() {
            firstFrame = frame
            break
        }

        let frame = try #require(firstFrame, "Expected one I420 frame")
        let pixelBuffer = try frame.toCVPixelBuffer()
        let pb = try #require(pixelBuffer, "Expected I420 frame to convert to CVPixelBuffer")

        #expect(CVPixelBufferGetWidth(pb) == 64)
        #expect(CVPixelBufferGetHeight(pb) == 64)
        #expect(CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8Planar)
    }

    @Test("PixelFormat cvPixelFormat mapping")
    func pixelFormatMapping() {
        #expect(PixelFormat.bgra.cvPixelFormat == kCVPixelFormatType_32BGRA)
        #expect(PixelFormat.rgba.cvPixelFormat == kCVPixelFormatType_32RGBA)
        #expect(PixelFormat.nv12.cvPixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        #expect(PixelFormat.i420.cvPixelFormat == kCVPixelFormatType_420YpCbCr8Planar)
        #expect(PixelFormat.gray8.cvPixelFormat == kCVPixelFormatType_OneComponent8)
    }
}
#endif
