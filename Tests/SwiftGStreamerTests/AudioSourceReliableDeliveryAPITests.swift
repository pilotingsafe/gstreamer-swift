import Testing
@testable import GStreamer

@Suite("AudioSource Reliable Delivery API", .timeLimit(.minutes(1)))
struct AudioSourceReliableDeliveryAPITests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Reliable raw live delivery rejects at build with exact error")
    func reliableRawLiveDeliveryRejectsAtBuild() throws {
        let error = try #require(Self.captureError {
            _ = try AudioSource.microphone()
                .withReliableDelivery()
                .build()
        })

        Self.expectAudioSourceInvalidConfiguration(
            error,
            "Reliable live packet delivery requires encoded audio output; configure Opus or AAC encoding before build"
        )
    }

    @Test("Reliable live delivery rejects negative maxTime with exact error")
    func reliableLiveDeliveryRejectsNegativeMaxTime() throws {
        let error = try #require(Self.captureError {
            _ = try AudioSource.microphone()
                .withOpusEncoding(bitrate: 64_000)
                .withReliableDelivery(maxTime: .nanoseconds(-1))
                .build()
        })

        Self.expectAudioSourceInvalidConfiguration(
            error,
            "Reliable delivery maxTime must be non-negative"
        )
    }

    @Test("Reliable live delivery requires at least one finite non-zero queue bound")
    func reliableLiveDeliveryRejectsAllNilOrZeroBounds() throws {
        let error = try #require(Self.captureError {
            _ = try AudioSource.microphone()
                .withOpusEncoding(bitrate: 64_000)
                .withReliableDelivery(maxBuffers: 0, maxBytes: 0, maxTime: nil)
                .build()
        })

        Self.expectAudioSourceInvalidConfiguration(
            error,
            "Reliable delivery requires at least one finite non-zero queue bound"
        )
    }

    @Test("Encoded AudioSource built without reliable opt-in rejects reliablePackets with exact error")
    func encodedAudioSourceWithoutReliableOptInRejectsReliablePackets() throws {
        try #require(
            ReliablePacketsTests.elementFactoryExists("opusenc"),
            "opusenc is required to construct an encoded synthetic live source"
        )

        let source = try AudioSource.microphone()
            .withOpusEncoding(bitrate: 64_000)
            ._withSourcePipelineCandidatesForTesting([
                "audiotestsrc is-live=true num-buffers=1"
            ])
            .build()

        let error = try #require(Self.captureError {
            _ = try source.reliablePackets()
        })

        Self.expectInvalidArgument(
            error,
            parameter: "AudioSource.reliablePackets",
            reason: "Reliable delivery is not configured; call withReliableDelivery(...) before build()."
        )
    }

    private static func captureError(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private static func expectAudioSourceInvalidConfiguration(_ error: Error, _ message: String) {
        guard case AudioSource.AudioSourceError.invalidConfiguration(let actualMessage) = error else {
            Issue.record("Expected AudioSourceError.invalidConfiguration(\(message)), got \(error)")
            return
        }

        #expect(actualMessage == message)
    }

    private static func expectInvalidArgument(
        _ error: Error,
        parameter expectedParameter: String,
        reason expectedReason: String
    ) {
        guard case GStreamerError.invalidArgument(let parameter, let reason) = error else {
            Issue.record("Expected invalidArgument(\(expectedParameter), \(expectedReason)), got \(error)")
            return
        }

        #expect(parameter == expectedParameter)
        #expect(reason == expectedReason)
    }
}
