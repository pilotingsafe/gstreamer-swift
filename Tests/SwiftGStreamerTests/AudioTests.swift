import Testing
@testable import GStreamer

@Suite("Audio Tests", .timeLimit(.minutes(1)))
struct AudioTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("AudioFormat initialization")
    func audioFormatInit() {
        #expect(AudioFormat(string: "S16LE") == .s16le)
        #expect(AudioFormat(string: "F32LE") == .f32le)
        #expect(AudioFormat(string: "s16le") == .s16le)  // Case insensitive
        #expect(AudioFormat(string: "CUSTOM").formatString == "CUSTOM")
    }

    @Test("AudioFormat bytes per sample")
    func audioFormatBytesPerSample() {
        #expect(AudioFormat.s16le.bytesPerSample == 2)
        #expect(AudioFormat.s32le.bytesPerSample == 4)
        #expect(AudioFormat.f32le.bytesPerSample == 4)
        #expect(AudioFormat.f64le.bytesPerSample == 8)
        #expect(AudioFormat.u8.bytesPerSample == 1)
    }

    @Test("Create AudioBufferSink from pipeline")
    func createAudioBufferSink() throws {
        let pipeline = try Pipeline("audiotestsrc ! appsink name=sink")
        let audioSink = try AudioBufferSink(pipeline: pipeline, name: "sink")
        _ = audioSink
    }

    @Test("AudioBufferSink not found throws error")
    func audioSinkNotFound() throws {
        let pipeline = try Pipeline("audiotestsrc ! fakesink")

        #expect(throws: GStreamerError.self) {
            _ = try AudioBufferSink(pipeline: pipeline, name: "sink")
        }
    }

    @Test("Pull audio buffers from AudioBufferSink")
    func pullAudioBuffers() async throws {
        let pipeline = try Pipeline(
            """
            audiotestsrc num-buffers=5 wave=silence ! \
            audio/x-raw,format=S16LE,rate=44100,channels=2 ! \
            appsink name=sink
            """
        )

        let audioSink = try AudioBufferSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var bufferCount = 0
        for await buffer in audioSink.buffers() {
            bufferCount += 1

            // After first buffer, audio info should be parsed
            if bufferCount > 1 {
                #expect(buffer.sampleRate == 44100)
                #expect(buffer.channels == 2)
                #expect(buffer.format == .s16le)
            }

            // Access buffer data
            #expect(buffer.bytes.byteCount > 0)

            if bufferCount >= 3 { break }
        }

        #expect(bufferCount >= 3)
    }

    @Test("AudioBuffer has timestamps")
    func audioBufferHasTimestamps() async throws {
        let pipeline = try Pipeline(
            """
            audiotestsrc num-buffers=2 ! \
            audio/x-raw,format=S16LE,rate=44100,channels=1 ! \
            appsink name=sink
            """
        )

        let audioSink = try AudioBufferSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstBuffer: AudioBuffer?
        for await buffer in audioSink.buffers() {
            firstBuffer = buffer
            break
        }

        let buffer = try #require(firstBuffer, "Expected audiotestsrc to yield one buffer")
        _ = try #require(buffer.pts, "audiotestsrc buffers should include PTS")
    }

    @Test("AudioBuffer sample count calculation")
    func audioBufferSampleCount() async throws {
        let pipeline = try Pipeline(
            """
            audiotestsrc num-buffers=1 samplesperbuffer=1024 ! \
            audio/x-raw,format=S16LE,rate=44100,channels=2 ! \
            appsink name=sink
            """
        )

        let audioSink = try AudioBufferSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        var firstBuffer: AudioBuffer?
        for await buffer in audioSink.buffers() {
            firstBuffer = buffer
            break
        }

        let buffer = try #require(firstBuffer, "Expected audiotestsrc to yield one buffer")
        try #require(buffer.format == .s16le, "Expected S16LE caps to be parsed before sample count")
        try #require(buffer.channels == 2, "Expected channel count to be parsed before sample count")
        #expect(buffer.sampleRate == 44100)
        // samplesperbuffer=1024, format=S16LE (2 bytes), channels=2
        // Total bytes should be 1024 * 2 * 2 = 4096
        // Sample count (per channel) should be 1024
        #expect(buffer.sampleCount == 1024)
    }
}
