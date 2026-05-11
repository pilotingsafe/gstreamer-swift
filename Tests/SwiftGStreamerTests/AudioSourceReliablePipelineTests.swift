import Testing
@testable import GStreamer

@Suite("AudioSource Reliable Delivery Pipelines")
struct AudioSourceReliablePipelineTests {

    @Test("Realtime pipeline keeps lossy appsink when reliable delivery is absent")
    func realtimePipelineKeepsLossyAppsinkWhenReliableDeliveryIsAbsent() throws {
        let pipeline = try AudioSource.microphone()
            .withOpusEncoding(bitrate: 64_000)
            ._pipelineDescriptionForTesting(
                source: "audiotestsrc is-live=true",
                sinkName: "sink",
                queueName: "reliable_delivery_queue"
            )

        #expect(
            pipeline.contains("appsink name=sink sync=false drop=true max-buffers=1 emit-signals=true")
        )
        #expect(!pipeline.contains("queue name=reliable_delivery_queue"))
    }

    @Test("Reliable Opus pipeline inserts named queue between caps and encoder")
    func reliableOpusPipelineInsertsNamedQueueBetweenCapsAndEncoder() throws {
        let pipeline = try AudioSource.microphone()
            .withOpusEncoding(bitrate: 64_000)
            .withReliableDelivery()
            ._pipelineDescriptionForTesting(
                source: "audiotestsrc is-live=true",
                sinkName: "sink",
                queueName: "reliable_delivery_queue"
            )
        let parts = Self.pipelineParts(pipeline)

        let capsIndex = try #require(parts.firstIndex { $0.hasPrefix("audio/x-raw") })
        let queueIndex = try #require(parts.firstIndex { $0.hasPrefix("queue name=reliable_delivery_queue") })
        let encoderIndex = try #require(parts.firstIndex { $0.hasPrefix("opusenc ") })

        #expect(capsIndex < queueIndex)
        #expect(queueIndex < encoderIndex)
    }

    @Test("Reliable AAC pipeline inserts named queue between caps and encoder")
    func reliableAACPipelineInsertsNamedQueueBetweenCapsAndEncoder() throws {
        let pipeline = try AudioSource.microphone()
            .withAACEncoding(bitrate: 96_000)
            .withReliableDelivery()
            ._pipelineDescriptionForTesting(
                source: "audiotestsrc is-live=true",
                sinkName: "sink",
                queueName: "reliable_delivery_queue"
            )
        let parts = Self.pipelineParts(pipeline)

        let capsIndex = try #require(parts.firstIndex { $0.hasPrefix("audio/x-raw") })
        let queueIndex = try #require(parts.firstIndex { $0.hasPrefix("queue name=reliable_delivery_queue") })
        let encoderIndex = try #require(parts.firstIndex { $0.contains("aac") && !$0.hasPrefix("queue ") })

        #expect(capsIndex < queueIndex)
        #expect(queueIndex < encoderIndex)
    }

    @Test("Reliable queue serializes defaults as finite bounds")
    func reliableQueueSerializesDefaultBounds() throws {
        let queue = try Self.reliableQueuePart(
            AudioSource.microphone()
                .withOpusEncoding(bitrate: 64_000)
                .withReliableDelivery()
        )

        #expect(queue.contains("leaky=0"))
        #expect(queue.contains("max-size-buffers=256"))
        #expect(queue.contains("max-size-bytes=0"))
        #expect(queue.contains("max-size-time=2000000000"))
    }

    @Test("Reliable queue serializes nil and zero queue bounds as zero")
    func reliableQueueSerializesNilAndZeroBoundsAsZero() throws {
        let queue = try Self.reliableQueuePart(
            AudioSource.microphone()
                .withOpusEncoding(bitrate: 64_000)
                .withReliableDelivery(
                    leaky: .downstream,
                    maxBuffers: nil,
                    maxBytes: 0,
                    maxTime: nil
                )
        )

        #expect(queue.contains("leaky=2"))
        #expect(queue.contains("max-size-buffers=0"))
        #expect(queue.contains("max-size-bytes=0"))
        #expect(queue.contains("max-size-time=0"))
    }

    @Test("Reliable queue serializes finite byte and time bounds")
    func reliableQueueSerializesFiniteByteAndTimeBounds() throws {
        let queue = try Self.reliableQueuePart(
            AudioSource.microphone()
                .withOpusEncoding(bitrate: 64_000)
                .withReliableDelivery(
                    leaky: .upstream,
                    maxBuffers: 12,
                    maxBytes: 4096,
                    maxTime: .milliseconds(250)
                )
        )

        #expect(queue.contains("leaky=1"))
        #expect(queue.contains("max-size-buffers=12"))
        #expect(queue.contains("max-size-bytes=4096"))
        #expect(queue.contains("max-size-time=250000000"))
    }

    @Test("Reliable appsink has exact non-dropping options")
    func reliableAppsinkHasExactNonDroppingOptions() throws {
        let pipeline = try AudioSource.microphone()
            .withOpusEncoding(bitrate: 64_000)
            .withReliableDelivery()
            ._pipelineDescriptionForTesting(
                source: "audiotestsrc is-live=true",
                sinkName: "sink",
                queueName: "reliable_delivery_queue"
            )
        let appsink = try #require(Self.pipelineParts(pipeline).last)

        #expect(
            appsink
                == "appsink name=sink drop=false sync=false emit-signals=true enable-last-sample=false wait-on-eos=true max-buffers=1"
        )
        #expect(!appsink.contains("max-bytes="))
        #expect(!appsink.contains("max-time="))
        #expect(!appsink.contains("buffer-list="))
    }

    private static func reliableQueuePart(_ builder: AudioSourceBuilder) throws -> String {
        let pipeline = try builder._pipelineDescriptionForTesting(
            source: "audiotestsrc is-live=true",
            sinkName: "sink",
            queueName: "reliable_delivery_queue"
        )
        return try #require(Self.pipelineParts(pipeline).first { $0.hasPrefix("queue name=reliable_delivery_queue") })
    }

    private static func pipelineParts(_ pipeline: String) -> [String] {
        pipeline
            .split(separator: "!")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
