import Testing
import Synchronization
@testable import GStreamer

@Suite("CI End-to-End Examples", .timeLimit(.minutes(1)))
struct CIEndToEndExampleTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("videotestsrc frames reach appsink")
    func videoTestSourceFramesReachAppSink() async throws {
        // Given the CI runner has the package's GStreamer runtime dependencies
        // And a finite synthetic BGRA video source is connected to an app sink
        let pipeline = try Pipeline(
            """
            videotestsrc num-buffers=3 ! \
            video/x-raw,format=BGRA,width=16,height=16,framerate=30/1 ! \
            appsink name=sink sync=false drop=false max-buffers=3
            """
        )
        let appSink = try AppSink(pipeline: pipeline, name: "sink")
        let eosTask = Task {
            try await pipeline.bus.waitForEOSOrError()
        }
        defer { eosTask.cancel() }

        // When the Swift test runs the pipeline and reads frames from the app sink
        try pipeline.play()
        defer { pipeline.stop() }

        let frames = try await Self.withTimeout(.seconds(5)) {
            var frames: [VideoFrame] = []
            for try await frame in appSink.frames() {
                frames.append(frame)
            }
            return frames
        }

        // Then three video frames are delivered to Swift
        #expect(frames.count == 3)

        // And each delivered frame has the expected BGRA byte size
        let expectedByteCount = 16 * 16 * 4
        for frame in frames {
            let byteCount = try frame.withUnsafeBytes { $0.count }
            #expect(byteCount > 0)
            #expect(byteCount == expectedByteCount)
        }

        // And the delivered stream exposes the expected video dimensions and format
        let parsedFrameCount = frames.filter { frame in
            frame.width == 16 && frame.height == 16 && frame.format == .bgra
        }.count
        #expect(parsedFrameCount >= 1)

        // And the finite pipeline reaches end-of-stream without a bus error
        try await Self.withTimeout(.seconds(2)) {
            try await eosTask.value
        }
    }

    @Test("appsrc frames reach fakesink and EOS")
    func appSourceFramesReachFakeSinkAndEOS() async throws {
        // Given the CI runner has the package's GStreamer runtime dependencies
        // And a Swift app source is connected to a non-rendering GStreamer sink
        let pipeline = try Pipeline(
            """
            appsrc name=src is-live=false format=time ! \
            video/x-raw,format=BGRA,width=2,height=2,framerate=30/1 ! \
            identity name=tap ! \
            fakesink sync=false
            """
        )
        defer { pipeline.stop() }

        let appSource = try AppSource(pipeline: pipeline, name: "src")
        appSource.setCaps("video/x-raw,format=BGRA,width=2,height=2,framerate=30/1")
        appSource.setLive(false)

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let downstreamBufferCount = CIEndToEndProbeCounter()

        srcPad.addProbe(type: .buffer) {
            downstreamBufferCount.increment()
            return .ok
        }

        // When the Swift test pushes deterministic BGRA frames and ends the stream
        try pipeline.play()

        let frameDuration: UInt64 = 33_333_333
        let frames: [[UInt8]] = [
            [
                0, 0, 255, 255,
                0, 255, 0, 255,
                255, 0, 0, 255,
                255, 255, 255, 255,
            ],
            [
                255, 255, 0, 255,
                255, 0, 255, 255,
                0, 255, 255, 255,
                0, 0, 0, 255,
            ],
            [
                32, 64, 96, 255,
                96, 64, 32, 255,
                16, 128, 240, 255,
                240, 128, 16, 255,
            ],
        ]

        for (index, frame) in frames.enumerated() {
            try appSource.push(
                data: frame,
                pts: UInt64(index) * frameDuration,
                duration: frameDuration
            )
        }
        appSource.endOfStream()

        // Then the GStreamer pipeline observes each pushed frame downstream
        try await Self.withTimeout(.seconds(5)) {
            try await pipeline.bus.waitForEOSOrError()
        }
        #expect(downstreamBufferCount.value == 3)

        // And the pipeline reaches end-of-stream without a bus error
    }

    private static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self, returning: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CIEndToEndTimeoutError(timeout: timeout)
            }

            defer {
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw CIEndToEndTimeoutError(timeout: timeout)
            }
            return result
        }
    }
}

private final class CIEndToEndProbeCounter: @unchecked Sendable {
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

private struct CIEndToEndTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}
