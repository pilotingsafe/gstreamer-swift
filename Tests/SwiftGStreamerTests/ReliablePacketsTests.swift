import Foundation
import Testing
import Synchronization
import CGStreamerTestSupport

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import GStreamer

@Suite("Reliable Packets", .timeLimit(.minutes(1)))
struct ReliablePacketsTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Two sequential reliable packet calls are repeatable")
    func sequentialReliablePacketCallsAreRepeatable() async throws {
        let fixture = try await Self.makeAudioFixture()
        let capsProbe = StringProbe()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            ._withFirstSampleCapsProbe { caps in
                Task { await capsProbe.set(caps) }
            }
            .build()

        #expect(await capsProbe.value == nil)

        let first = try await Self.collectTrace(source.reliablePackets())
        let second = try await Self.collectTrace(source.reliablePackets())

        #expect(first.count > 0)
        #expect(first.points == second.points)
        #expect(first.reachedCleanEOS)
        #expect(await capsProbe.value != nil)
    }

    @Test("Two concurrent reliable packet calls on one file source complete independently")
    func concurrentReliablePacketCallsOnOneFileSourceCompleteIndependently() async throws {
        let fixture = try await Self.makeAudioFixture()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()

        async let first = Self.collectTrace(source.reliablePackets())
        async let second = Self.collectTrace(source.reliablePackets())
        let traces = try await (first, second)

        #expect(traces.0.count > 0)
        #expect(traces.0.points == traces.1.points)
        #expect(traces.0.reachedCleanEOS)
        #expect(traces.1.reachedCleanEOS)
    }

    @Test("Two consumers of the same ReliablePackets sequence get the single-consumer error")
    func twoConsumersOfSameReliablePacketsSequenceGetSingleConsumerError() async throws {
        let fixture = try await Self.makeAudioFixture()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()
        let sequence = source.reliablePackets()

        async let first = Self.result { try await Self.collectTrace(sequence) }
        async let second = Self.result { try await Self.collectTrace(sequence) }
        let outcomes = await [first, second]
        let failures = outcomes.compactMap(\.failure)

        #expect(outcomes.contains { ($0.success?.count ?? 0) > 0 })
        #expect(failures.count == 1)
        let error = try #require(failures.first)
        Self.expectSingleConsumerError(error)
    }

    @Test("Copied sequence and iterator can cross tasks and keep single-consumer semantics")
    func copiedSequenceAndIteratorCanCrossTasks() async throws {
        let fixture = try await Self.makeAudioFixture()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()
        let sequence = source.reliablePackets()
        let copiedSequence = sequence

        let detachedTrace = try await Task.detached {
            try await Self.collectTrace(copiedSequence)
        }.value

        #expect(detachedTrace.count > 0)
        Self.expectStrictlyIncreasingPTS(detachedTrace)

        let iterator = source.reliablePackets().makeAsyncIterator()
        async let first = Self.nextResult(from: iterator)
        async let second = Self.nextResult(from: iterator)
        let iteratorOutcomes = await [first, second]
        let iteratorFailures = iteratorOutcomes.compactMap(\.failure)

        #expect(iteratorOutcomes.contains { $0.success != nil })
        #expect(iteratorFailures.count == 1)
        let error = try #require(iteratorFailures.first)
        Self.expectSingleConsumerError(error)
    }

    @MainActor
    @Test("ReliablePackets iteration composes from a MainActor call site")
    func mainActorCallSiteCanAwaitReliablePackets() async throws {
        let fixture = try await Self.makeAudioFixture()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()

        let trace = try await Self.collectTrace(source.reliablePackets(), limit: 3)

        #expect(trace.count == 3)
        Self.expectStrictlyIncreasingPTS(trace)
    }
}

@Suite("Reliable Packet Validation")
struct ReliablePacketValidationTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Audio file builder validation reports structured invalidArgument errors", arguments: InvalidBuildCase.allCases)
    func audioFileBuilderValidationReportsStructuredInvalidArgumentErrors(_ invalidCase: InvalidBuildCase) throws {
        let temporaryDirectory = try ReliablePacketsTests.makeTemporaryDirectory()
        let path = temporaryDirectory.appendingPathComponent(invalidCase.fileName).path
        let cleanup = try invalidCase.prepare(path: path)
        defer { cleanup() }

        let builder = invalidCase.configure(AudioSource.file(path: path))
        let error = try #require(Self.captureError {
            _ = try builder.build()
        })

        Self.expectInvalidArgument(error, parameter: invalidCase.expectedParameter)
    }

    private static func captureError(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private static func expectInvalidArgument(_ error: Error, parameter: String) {
        guard case GStreamerError.invalidArgument(let actualParameter, let reason) = error else {
            Issue.record("Expected GStreamerError.invalidArgument(parameter: \(parameter), reason: non-empty), got \(error)")
            return
        }

        #expect(actualParameter == parameter)
        #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

@Suite("Reliable Packet File Paths", .timeLimit(.minutes(1)))
struct ReliablePacketSafePathTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test(
        "Safe path characters build and drain",
        arguments: [
            "reliable packet space.wav",
            "reliable#packet.wav",
            "reliable%packet.wav",
            "reliable\"packet.wav",
            "reliable'packet.wav",
            "reliable!packet.wav",
        ]
    )
    func safePathCharactersBuildAndDrain(_ fileName: String) async throws {
        let sourceFixture = try await ReliablePacketsTests.makeAudioFixture()
        let directory = try ReliablePacketsTests.makeTemporaryDirectory()
        let copiedFixture = directory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceFixture, to: copiedFixture)

        let source = try AudioSource.file(path: copiedFixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()
        let trace = try await ReliablePacketsTests.collectTrace(source.reliablePackets())

        #expect(trace.count > 0)
        #expect(trace.reachedCleanEOS)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(trace)
    }
}

@Suite("Reliable Packet Lazy Startup", .timeLimit(.minutes(1)))
struct ReliablePacketLazyStartupTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("build validates but first iteration starts the candidate pipeline")
    func buildValidatesButFirstIterationStartsCandidatePipeline() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let capsProbe = StringProbe()

        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            ._withFirstSampleCapsProbe { caps in
                Task { await capsProbe.set(caps) }
            }
            .build()

        #expect(await capsProbe.value == nil)

        let trace = try await ReliablePacketsTests.collectTrace(source.reliablePackets(), limit: 1)
        let observedCaps = await ReliablePacketsTests.waitUntil(timeout: .seconds(5)) {
            await capsProbe.value != nil
        }

        #expect(trace.count > 0)
        #expect(observedCaps)
    }
}

@Suite("Reliable Packet Encoding Matrix", .timeLimit(.minutes(1)))
struct ReliablePacketEncodingMatrixTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Raw and Opus reliable packet streams are complete and ordered", arguments: ReliableEncodingSpec.coreEncodings)
    func rawAndOpusReliablePacketStreamsAreCompleteAndOrdered(_ encoding: ReliableEncodingSpec) async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let source = try encoding.apply(to: AudioSource.file(path: fixture.path)).build()

        let fast = try await ReliablePacketsTests.collectTrace(source.reliablePackets())
        let slow = try await ReliablePacketsTests.collectTrace(
            source.reliablePackets(),
            delay: .milliseconds(5)
        )

        #expect(encoding.expectedCountRange.contains(fast.count))
        #expect(slow.count == fast.count)
        #expect(slow.points == fast.points)
        #expect(fast.reachedCleanEOS)
        #expect(slow.reachedCleanEOS)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(fast)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(slow)
    }

    @Test("AAC reliable packet stream is complete and ordered when AAC is available")
    func aacReliablePacketStreamIsCompleteAndOrderedWhenAvailable() async throws {
        guard ReliableEncodingSpec.aac.isAvailable else {
            return
        }

        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let source = try ReliableEncodingSpec.aac.apply(to: AudioSource.file(path: fixture.path)).build()

        let trace = try await ReliablePacketsTests.collectTrace(source.reliablePackets())

        #expect(ReliableEncodingSpec.aac.expectedCountRange.contains(trace.count))
        #expect(trace.reachedCleanEOS)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(trace)
    }
}

@Suite("Reliable Packet Negotiated Caps", .timeLimit(.minutes(1)))
struct ReliablePacketNegotiatedCapsTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Raw default negotiated caps are S16LE 48000 Hz stereo")
    func rawDefaultNegotiatedCapsAreS16LE48000Stereo() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let capsProbe = StringProbe()
        let source = try AudioSource.file(path: fixture.path)
            .withEncoding(.raw)
            ._withFirstSampleCapsProbe { caps in
                Task { await capsProbe.set(caps) }
            }
            .build()

        _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets(), limit: 1)
        let observedCaps = await ReliablePacketsTests.waitUntil(timeout: .seconds(5)) {
            await capsProbe.value != nil
        }
        let caps = try #require(await capsProbe.value, "Expected first-sample caps probe to fire")

        #expect(observedCaps)
        #expect(caps.contains("S16LE"))
        #expect(caps.contains("rate=(int)48000") || caps.contains("rate=48000"))
        #expect(caps.contains("channels=(int)2") || caps.contains("channels=2"))
    }

    @Test("Raw custom format rate and channels appear in first sample caps")
    func rawCustomFormatRateAndChannelsAppearInFirstSampleCaps() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(sampleRate: 44_100, channels: 1)
        let capsProbe = StringProbe()
        let source = try AudioSource.file(path: fixture.path)
            .withEncoding(.raw)
            .withFormat(.s16le)
            .withSampleRate(44_100)
            .withChannels(1)
            ._withFirstSampleCapsProbe { caps in
                Task { await capsProbe.set(caps) }
            }
            .build()

        _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets(), limit: 1)
        let observedCaps = await ReliablePacketsTests.waitUntil(timeout: .seconds(5)) {
            await capsProbe.value != nil
        }
        let caps = try #require(await capsProbe.value, "Expected first-sample caps probe to fire")

        #expect(observedCaps)
        #expect(caps.contains("S16LE"))
        #expect(caps.contains("rate=(int)44100") || caps.contains("rate=44100"))
        #expect(caps.contains("channels=(int)1") || caps.contains("channels=1"))
    }
}

@Suite("Reliable Packet Semantic Contrast", .timeLimit(.minutes(1)))
struct ReliablePacketSemanticContrastTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Lossy packets and reliable packets keep distinct slow-consumer semantics")
    func lossyPacketsAndReliablePacketsKeepDistinctSlowConsumerSemantics() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 240)
        let referenceSource = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()
        let lossySource = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()
        let reliableSource = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()

        let reference = try await ReliablePacketsTests.collectTrace(referenceSource.reliablePackets())
        async let lossy = ReliablePacketsTests.collectLossyTrace(
            lossySource.lossyPacketsForTesting(),
            delay: .milliseconds(8)
        )
        async let reliable = ReliablePacketsTests.collectTrace(
            reliableSource.reliablePackets(),
            delay: .milliseconds(8)
        )
        let comparison = try await (lossy, reliable)

        #expect(reference.count > 0)
        #expect(comparison.0.count < reference.count)
        #expect(comparison.1.count == reference.count)
        #expect(comparison.1.points == reference.points)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(comparison.1)
    }
}

@Suite("Reliable Packet Multi-Stream Containers", .timeLimit(.minutes(1)))
struct ReliablePacketMultiStreamTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Audio plus video container selects audio branch and drains packets")
    func audioPlusVideoContainerSelectsAudioBranchAndDrainsPackets() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioVideoFixture()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()

        let trace = try await ReliablePacketsTests.collectTrace(source.reliablePackets())

        #expect(trace.count > 0)
        #expect(trace.reachedCleanEOS)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(trace)
    }
}

@Suite("Reliable Packet Candidate Fallback", .timeLimit(.minutes(1)))
struct ReliablePacketCandidateFallbackTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Pre-first-packet candidate failures try the next candidate")
    func preFirstPacketCandidateFailuresTryNextCandidate() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let attempts = CounterProbe()
        let candidates = [
            "not a parseable pipeline !!!",
            "definitely_missing_element_for_reliable_packets ! appsink name=\(sinkName)",
            "audiotestsrc num-buffers=1 ! fakesink",
            "audiotestsrc num-buffers=1 ! video/x-raw,format=BGRA ! appsink name=\(sinkName)",
            Self.emptyEOSCandidateDescription(sinkName: sinkName),
            try ReliablePacketsTests.reliableCandidateDescription(for: fixture, sinkName: sinkName),
        ]

        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketCandidateDescriptionsForTesting(candidates, sinkName: sinkName)
            .withReliablePacketOnCandidateStartForTesting { _, _ in
                Task { await attempts.increment() }
            }
            .build()

        let trace = try await ReliablePacketsTests.collectTrace(source.reliablePackets())

        #expect(trace.count > 0)
        #expect(await attempts.value == candidates.count)
        #expect(trace.reachedCleanEOS)
    }

    @Test("Exhaustion with any non-EOS failure throws the last non-EOS error")
    func exhaustionWithAnyNonEOSFailureThrowsLastNonEOSError() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketCandidateDescriptionsForTesting(
                [
                    Self.emptyEOSCandidateDescription(sinkName: sinkName),
                    "not a parseable reliable candidate A",
                    "not a parseable reliable candidate B",
                ],
                sinkName: sinkName
            )
            .build()

        let error = try #require(await ReliablePacketsTests.captureAsyncError {
            _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets())
        })

        guard case GStreamerError.parsePipeline(let message) = error else {
            Issue.record("Expected final parsePipeline error, got \(error)")
            return
        }
        #expect(message.contains("candidate B"))
    }

    @Test("All pre-first-packet EOS candidates throw the no-decodable-packets error")
    func allPreFirstPacketEOSCandidatesThrowNoDecodablePacketsError() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketCandidateDescriptionsForTesting(
                [
                    Self.emptyEOSCandidateDescription(sinkName: sinkName),
                    Self.emptyEOSCandidateDescription(sinkName: sinkName),
                ],
                sinkName: sinkName
            )
            .build()

        let error = try #require(await ReliablePacketsTests.captureAsyncError {
            _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets())
        })

        ReliablePacketsTests.expectNoDecodableAudioPacketsError(error)
    }

    @Test("First packet disables fallback and post-first bus error throws")
    func firstPacketDisablesFallbackAndPostFirstBusErrorThrows() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 40)
        let sinkName = "reliable_sink"
        let probeBag = TestProbeBag()
        let candidates = [
            try ReliablePacketsTests.reliableCandidateDescription(for: fixture, sinkName: sinkName),
            try ReliablePacketsTests.reliableCandidateDescription(for: fixture, sinkName: sinkName),
        ]
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketCandidateDescriptionsForTesting(candidates, sinkName: sinkName)
            .withReliablePacketOnCandidateStartForTesting { pipeline, sinkName in
                if let probe = swift_gst_test_install_bus_error_after_buffers(
                    pipeline._element,
                    sinkName,
                    "sink",
                    2,
                    "Injected post-first reliable packet error",
                    "post-first"
                ) {
                    probeBag.append(probe)
                }
            }
            .withReliablePacketOnCleanupForTesting {
                probeBag.freeAll()
            }
            .build()

        let error = try #require(await ReliablePacketsTests.captureAsyncError {
            _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets())
        })

        ReliablePacketsTests.expectBusError(
            error,
            message: "Injected post-first reliable packet error",
            source: nil,
            debug: "post-first"
        )
    }

    static func emptyEOSCandidateDescription(sinkName: String) -> String {
        """
        audiotestsrc num-buffers=0 ! \
        audio/x-raw,format=S16LE,rate=48000,channels=2 ! \
        appsink name=\(sinkName) sync=false drop=false max-buffers=32 emit-signals=true
        """
    }
}

@Suite("Reliable Packet Startup Timeout", .timeLimit(.minutes(1)))
struct ReliablePacketStartupTimeoutTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Startup timeout throws the exact structured error")
    func startupTimeoutThrowsExactStructuredError() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            ._withReliablePacketStartupTimeoutNanoseconds(25_000_000)
            .withReliablePacketCandidateDescriptionsForTesting(
                [Self.neverProducesCandidateDescription(sinkName: sinkName)],
                sinkName: sinkName
            )
            .build()

        let error = try #require(await ReliablePacketsTests.captureAsyncError {
            _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets())
        })

        ReliablePacketsTests.expectStartupTimeoutError(error)
    }

    @Test("Startup timeout falls back when later candidates exist")
    func startupTimeoutFallsBackWhenLaterCandidatesExist() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            ._withReliablePacketStartupTimeoutNanoseconds(25_000_000)
            .withReliablePacketCandidateDescriptionsForTesting(
                [
                    Self.neverProducesCandidateDescription(sinkName: sinkName),
                    try ReliablePacketsTests.reliableCandidateDescription(for: fixture, sinkName: sinkName),
                ],
                sinkName: sinkName
            )
            .build()

        let trace = try await ReliablePacketsTests.collectTrace(source.reliablePackets())

        #expect(trace.count > 0)
        #expect(trace.reachedCleanEOS)
    }

    @Test("Startup timeout is inactive after the first packet")
    func startupTimeoutIsInactiveAfterFirstPacket() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 12)
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            ._withReliablePacketStartupTimeoutNanoseconds(250_000_000)
            .build()

        let trace = try await ReliablePacketsTests.collectTrace(
            source.reliablePackets(),
            delay: .milliseconds(20)
        )

        #expect(trace.count > 0)
        #expect(trace.reachedCleanEOS)
    }

    static func neverProducesCandidateDescription(sinkName: String) -> String {
        """
        appsrc name=src is-live=true format=time ! \
        audio/x-raw,format=S16LE,rate=48000,channels=2 ! \
        appsink name=\(sinkName) sync=false drop=false max-buffers=32 emit-signals=true
        """
    }
}

@Suite("Reliable Packet EOS Semantics", .timeLimit(.minutes(1)))
struct ReliablePacketEOSSemanticsTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("EOS after queued packets drains one packet per next then nil")
    func eosAfterQueuedPacketsDrainsOnePacketPerNextThenNil() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 5)
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .build()
        let iterator = source.reliablePackets().makeAsyncIterator()
        var packets: [PacketPoint] = []

        while let packet = try await iterator.next() {
            packets.append(try PacketPoint(packet: packet))
        }

        #expect(packets.count > 0)
        #expect(try await iterator.next() == nil)
        ReliablePacketsTests.expectStrictlyIncreasingPTS(PacketTrace(points: packets, reachedCleanEOS: true))
    }

    @Test("Pre-first EOS follows exhaustion rules")
    func preFirstEOSFollowsExhaustionRules() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketCandidateDescriptionsForTesting(
                [ReliablePacketCandidateFallbackTests.emptyEOSCandidateDescription(sinkName: sinkName)],
                sinkName: sinkName
            )
            .build()

        let error = try #require(await ReliablePacketsTests.captureAsyncError {
            _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets())
        })

        ReliablePacketsTests.expectNoDecodableAudioPacketsError(error)
    }
}

@Suite("Reliable Packet Cancellation", .timeLimit(.minutes(1)))
struct ReliablePacketCancellationTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Suspended next returns CancellationError under 100 ms independent of marker ack")
    func suspendedNextReturnsCancellationErrorUnder100Milliseconds() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture()
        let sinkName = "reliable_sink"
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            ._withReliablePacketStartupTimeoutNanoseconds(30_000_000_000)
            .withReliablePacketCandidateDescriptionsForTesting(
                [ReliablePacketStartupTimeoutTests.neverProducesCandidateDescription(sinkName: sinkName)],
                sinkName: sinkName
            )
            .build()
        let sequence = source.reliablePackets()
        let task = Task {
            let iterator = sequence.makeAsyncIterator()
            _ = try await iterator.next()
        }

        try await Task.sleep(for: .milliseconds(20))
        let clock = ContinuousClock()
        let started = clock.now
        task.cancel()
        let taskResult = await task.result
        let error = try #require(taskResult.failure)
        let elapsed = started.duration(to: clock.now)

        #expect(error is CancellationError)
        #expect(elapsed < .milliseconds(100))
    }

    @Test("Cancellation after N packets and early break clean up without EOS")
    func cancellationAfterNPacketsAndEarlyBreakCleanUpWithoutEOS() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 400)
        let cleanup = CounterProbe()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketOnCleanupForTesting {
                Task { await cleanup.increment() }
            }
            .build()

        let consumed = CounterProbe()
        let sequence = source.reliablePackets()
        let task = Task {
            for try await _ in sequence {
                await consumed.increment()
                if await consumed.value >= 8 {
                    try await Task.sleep(for: .seconds(30))
                }
            }
        }

        let reachedEight = await ReliablePacketsTests.waitUntil(timeout: .seconds(5)) {
            await consumed.value >= 8
        }
        try #require(reachedEight, "Expected cancellation test to consume eight packets before cancelling")
        task.cancel()
        _ = await task.result

        let cancellationCleanup = await ReliablePacketsTests.waitUntil(timeout: .seconds(5)) {
            await cleanup.value >= 1
        }
        #expect(cancellationCleanup)

        let breakSource = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketOnCleanupForTesting {
                Task { await cleanup.increment() }
            }
            .build()
        var breakCount = 0
        for try await _ in breakSource.reliablePackets() {
            breakCount += 1
            if breakCount == 3 {
                break
            }
        }

        let breakCleanup = await ReliablePacketsTests.waitUntil(timeout: .seconds(5)) {
            await cleanup.value >= 2
        }
        #expect(breakCount == 3)
        #expect(breakCleanup)
    }

    @Test("Handler, continuation, cleanup ack, and same-pipeline bus drainability are observable after cleanup")
    func lifecycleProbesAreCleanAfterReliableCleanup() async throws {
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 20)
        let pipelineCapture = PipelineCapture()
        let source = try AudioSource.file(path: fixture.path)
            .withOpusEncoding(bitrate: 64_000)
            .withReliablePacketOnCandidateStartForTesting { pipeline, _ in
                pipelineCapture.record(pipeline)
            }
            .build()

        _ = try await ReliablePacketsTests.collectTrace(source.reliablePackets(), limit: 4)
        let snapshot = await source.reliablePacketRuntimeSnapshotForTesting()

        #expect(snapshot.newSampleHandlerCount == 0)
        #expect(snapshot.pendingContinuationCount == 0)
        #expect(snapshot.cleanupAcknowledgementCount >= 1)
        #expect(await source.reliablePacketPipelineForTesting() == nil)

        let pipeline = try #require(pipelineCapture.pipeline())
        #expect(swift_gst_test_post_element_marker(pipeline._element, "after-reliable-cleanup") != 0)

        var sawElementMessage = false
        for await message in pipeline.bus.messages(filter: [.element, .error]) {
            if case .element = message {
                sawElementMessage = true
                break
            }
            if case .error(let message, let debug) = message {
                throw GStreamerError.busError(message, source: "ReliablePacketsTests", debug: debug)
            }
        }
        #expect(sawElementMessage)
    }
}

@Suite("Reliable Packet Memory Bound", .timeLimit(.minutes(1)))
struct ReliablePacketMemoryBoundTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Slow reliable consumer memory stays bounded relative to packet size")
    func slowReliableConsumerMemoryStaysBoundedRelativeToPacketSize() async throws {
        #if canImport(Darwin)
        let fixture = try await ReliablePacketsTests.makeAudioFixture(packetCount: 6_000)
        let fastSource = try AudioSource.file(path: fixture.path)
            .withEncoding(.raw)
            .build()
        let slowSource = try AudioSource.file(path: fixture.path)
            .withEncoding(.raw)
            .build()

        let fast = try await ReliablePacketsTests.measurePeakResidentSet {
            try await ReliablePacketsTests.collectTrace(fastSource.reliablePackets())
        }
        let slow = try await ReliablePacketsTests.measurePeakResidentSet {
            try await ReliablePacketsTests.collectTrace(
                slowSource.reliablePackets(),
                delay: .milliseconds(1)
            )
        }
        let maxObservedPacketSize = max(fast.value.maxPacketSize, slow.value.maxPacketSize)
        let allowedGrowth = max(12 * maxObservedPacketSize, UInt64(16 * 1024 * 1024))
        let observedGrowth = slow.peakResidentSetBytes >= fast.peakResidentSetBytes
            ? slow.peakResidentSetBytes - fast.peakResidentSetBytes
            : 0

        #expect(fast.value.count == slow.value.count)
        #expect(observedGrowth <= allowedGrowth)
        #else
        return
        #endif
    }
}

extension ReliablePacketsTests {
    static func makeAudioFixture(
        sampleRate: Int = 48_000,
        channels: Int = 2,
        packetCount: Int = 96
    ) async throws -> URL {
        let directory = try makeTemporaryDirectory()
        let fixture = directory.appendingPathComponent("fixture-\(sampleRate)-\(channels)-\(packetCount).wav")
        let description = """
        audiotestsrc num-buffers=\(packetCount) samplesperbuffer=960 wave=sine freq=440 ! \
        audio/x-raw,format=S16LE,rate=\(sampleRate),channels=\(channels) ! \
        wavenc ! filesink location=\(launchQuoted(fixture.path))
        """
        try await runPipelineToEOS(description)
        return fixture
    }

    static func makeAudioVideoFixture() async throws -> URL {
        try #require(elementFactoryExists("matroskamux"), "matroskamux is required")
        try #require(elementFactoryExists("vp8enc"), "vp8enc is required")
        try #require(elementFactoryExists("opusenc"), "opusenc is required")

        let directory = try makeTemporaryDirectory()
        let fixture = directory.appendingPathComponent("audio-video.mkv")
        let description = """
        matroskamux name=mux ! filesink location=\(launchQuoted(fixture.path)) \
        audiotestsrc num-buffers=80 samplesperbuffer=960 wave=sine freq=440 ! \
        audio/x-raw,format=S16LE,rate=48000,channels=2 ! opusenc bitrate=64000 ! queue ! mux. \
        videotestsrc num-buffers=20 pattern=ball ! video/x-raw,width=32,height=32,framerate=10/1 ! \
        vp8enc deadline=1 ! queue ! mux.
        """
        try await runPipelineToEOS(description)
        return fixture
    }

    static func reliableCandidateDescription(for fixture: URL, sinkName: String) throws -> String {
        let uri = fixture.standardizedFileURL.absoluteString
        return """
        uridecodebin uri=\(launchQuoted(uri)) ! \
        audioconvert ! audioresample ! audio/x-raw,format=S16LE,rate=48000,channels=2 ! \
        opusenc bitrate=64000 ! \
        appsink name=\(sinkName) sync=false drop=false max-buffers=32 emit-signals=true
        """
    }

    static func runPipelineToEOS(_ description: String) async throws {
        let pipeline = try Pipeline(description)
        try pipeline.play()
        defer { pipeline.stop() }

        for await message in pipeline.bus.messages(filter: [.eos, .error]) {
            switch message {
            case .eos:
                return
            case .error(let message, let debug):
                throw GStreamerError.busError(message, source: "ReliablePacketsTests", debug: debug)
            default:
                continue
            }
        }
    }

    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gstreamer-swift-reliable-packets")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func launchQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func elementFactoryExists(_ name: String) -> Bool {
        name.withCString { swift_gst_test_element_factory_exists($0) != 0 }
    }

    static func collectTrace(
        _ sequence: ReliablePackets<Buffer>,
        delay: Duration? = nil,
        limit: Int? = nil
    ) async throws -> PacketTrace {
        var points: [PacketPoint] = []

        for try await packet in sequence {
            points.append(try PacketPoint(packet: packet))
            if let delay {
                try await Task.sleep(for: delay)
            }
            if let limit, points.count >= limit {
                return PacketTrace(points: points, reachedCleanEOS: false)
            }
        }

        return PacketTrace(points: points, reachedCleanEOS: true)
    }

    static func collectLossyTrace(
        _ stream: AsyncStream<Buffer>,
        delay: Duration? = nil
    ) async throws -> PacketTrace {
        var points: [PacketPoint] = []

        for await packet in stream {
            points.append(try PacketPoint(packet: packet))
            if let delay {
                try await Task.sleep(for: delay)
            }
        }

        return PacketTrace(points: points, reachedCleanEOS: true)
    }

    static func nextResult(
        from iterator: ReliablePackets<Buffer>.AsyncIterator
    ) async -> Result<Buffer?, Error> {
        do {
            let iterator = iterator
            return .success(try await iterator.next())
        } catch {
            return .failure(error)
        }
    }

    static func result<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }

    static func captureAsyncError(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    static func expectStrictlyIncreasingPTS(_ trace: PacketTrace) {
        let pts = trace.points.map(\.pts)
        #expect(zip(pts, pts.dropFirst()).allSatisfy { $0 < $1 })
    }

    static func expectSingleConsumerError(_ error: Error) {
        guard case GStreamerError.invalidArgument(let parameter, let reason) = error else {
            Issue.record("Expected single-consumer invalidArgument error, got \(error)")
            return
        }

        #expect(parameter == "ReliablePackets")
        #expect(reason == "ReliablePackets supports a single active iterator")
    }

    static func expectNoDecodableAudioPacketsError(_ error: Error) {
        expectBusError(
            error,
            message: "No decodable audio packets",
            source: "ReliablePackets",
            debug: nil
        )
    }

    static func expectStartupTimeoutError(_ error: Error) {
        expectBusError(
            error,
            message: "Reliable packet startup timed out",
            source: "ReliablePackets",
            debug: "No decodable audio packet arrived before startup timeout"
        )
    }

    static func expectBusError(
        _ error: Error,
        message expectedMessage: String,
        source expectedSource: String?,
        debug expectedDebug: String?
    ) {
        guard case GStreamerError.busError(let message, let source, let debug) = error else {
            Issue.record("Expected busError(\(expectedMessage)), got \(error)")
            return
        }

        #expect(message == expectedMessage)
        if let expectedSource {
            #expect(source == expectedSource)
        }
        #expect(debug == expectedDebug)
    }

    static func waitUntil(
        timeout: Duration,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        return await condition()
    }

    #if canImport(Darwin)
    static func measurePeakResidentSet<T: Sendable>(
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> (value: T, peakResidentSetBytes: UInt64) {
        let sampler = Task {
            var peak = currentResidentSetBytes()
            while !Task.isCancelled {
                peak = max(peak, currentResidentSetBytes())
                try? await Task.sleep(for: .milliseconds(5))
            }
            return peak
        }

        let value = try await body()
        sampler.cancel()
        let peak = await sampler.value
        return (value, peak)
    }

    static func currentResidentSetBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<natural_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return 0
        }

        return UInt64(info.resident_size)
    }
    #endif
}

enum ReliableEncodingSpec: String, Sendable, CustomTestStringConvertible {
    case raw
    case opus
    case aac

    static let coreEncodings: [ReliableEncodingSpec] = [.raw, .opus]

    var testDescription: String {
        rawValue
    }

    var expectedCountRange: ClosedRange<Int> {
        switch self {
        case .raw:
            return 16...512
        case .opus:
            return 8...512
        case .aac:
            return 8...768
        }
    }

    var isAvailable: Bool {
        switch self {
        case .raw:
            return true
        case .opus:
            return ReliablePacketsTests.elementFactoryExists("opusenc")
        case .aac:
            return ["avenc_aac", "faac", "voaacenc"].contains {
                ReliablePacketsTests.elementFactoryExists($0)
            }
        }
    }

    func apply(to builder: AudioFileSourceBuilder) -> AudioFileSourceBuilder {
        switch self {
        case .raw:
            return builder.withEncoding(.raw)
        case .opus:
            return builder.withOpusEncoding(bitrate: 64_000)
        case .aac:
            return builder.withAACEncoding(bitrate: 96_000)
        }
    }
}

enum InvalidBuildCase: CaseIterable, Sendable, CustomTestStringConvertible {
    case missingPath
    case directory
    case specialFile
    case unreadableFile
    case invalidSampleRate
    case invalidChannels
    case invalidOpusBitrate
    case invalidAACBitrate

    var testDescription: String {
        switch self {
        case .missingPath: "missing path"
        case .directory: "directory path"
        case .specialFile: "special file"
        case .unreadableFile: "unreadable file"
        case .invalidSampleRate: "invalid sample rate"
        case .invalidChannels: "invalid channels"
        case .invalidOpusBitrate: "invalid Opus bitrate"
        case .invalidAACBitrate: "invalid AAC bitrate"
        }
    }

    var fileName: String {
        switch self {
        case .missingPath: "missing.wav"
        case .directory: "directory"
        case .specialFile: "fifo.wav"
        case .unreadableFile: "unreadable.wav"
        case .invalidSampleRate: "invalid-sample-rate.wav"
        case .invalidChannels: "invalid-channels.wav"
        case .invalidOpusBitrate: "invalid-opus.wav"
        case .invalidAACBitrate: "invalid-aac.wav"
        }
    }

    var expectedParameter: String {
        switch self {
        case .missingPath, .directory, .specialFile, .unreadableFile:
            return "path"
        case .invalidSampleRate:
            return "sampleRate"
        case .invalidChannels:
            return "channels"
        case .invalidOpusBitrate:
            return "opusBitrate"
        case .invalidAACBitrate:
            return "aacBitrate"
        }
    }

    func prepare(path: String) throws -> () -> Void {
        switch self {
        case .missingPath:
            return {}

        case .directory:
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return {}

        case .specialFile:
            #if canImport(Darwin)
            _ = Darwin.mkfifo(path, mode_t(0o600))
            #elseif canImport(Glibc)
            _ = Glibc.mkfifo(path, mode_t(0o600))
            #endif
            return {
                try? FileManager.default.removeItem(atPath: path)
            }

        case .unreadableFile:
            FileManager.default.createFile(atPath: path, contents: Data([0, 1, 2, 3]))
            #if canImport(Darwin)
            _ = Darwin.chmod(path, 0)
            #elseif canImport(Glibc)
            _ = Glibc.chmod(path, 0)
            #endif
            return {
                #if canImport(Darwin)
                _ = Darwin.chmod(path, mode_t(0o600))
                #elseif canImport(Glibc)
                _ = Glibc.chmod(path, mode_t(0o600))
                #endif
                try? FileManager.default.removeItem(atPath: path)
            }

        case .invalidSampleRate, .invalidChannels, .invalidOpusBitrate, .invalidAACBitrate:
            FileManager.default.createFile(atPath: path, contents: Data([0, 1, 2, 3]))
            return {}
        }
    }

    func configure(_ builder: AudioFileSourceBuilder) -> AudioFileSourceBuilder {
        switch self {
        case .missingPath, .directory, .specialFile, .unreadableFile:
            return builder
        case .invalidSampleRate:
            return builder.withSampleRate(0)
        case .invalidChannels:
            return builder.withChannels(0)
        case .invalidOpusBitrate:
            return builder.withOpusEncoding(bitrate: 0)
        case .invalidAACBitrate:
            return builder.withAACEncoding(bitrate: 0)
        }
    }
}

struct PacketTrace: Equatable, Sendable {
    var points: [PacketPoint]
    var reachedCleanEOS: Bool

    var count: Int {
        points.count
    }

    var maxPacketSize: UInt64 {
        points.map(\.size).max() ?? 0
    }
}

struct PacketPoint: Equatable, Sendable {
    var pts: UInt64
    var size: UInt64

    init(packet: Buffer) throws {
        self.pts = try #require(packet.pts, "Reliable packets must preserve PTS for ordering assertions")
        self.size = UInt64(packet.size)
    }
}

private actor CounterProbe {
    private var count = 0

    var value: Int {
        count
    }

    func increment() {
        count += 1
    }
}

private actor StringProbe {
    private var storage: String?

    var value: String? {
        storage
    }

    func set(_ value: String) {
        storage = value
    }
}

private final class PipelineCapture: @unchecked Sendable {
    private let storage = Mutex<Pipeline?>(nil)

    func record(_ pipeline: Pipeline) {
        storage.withLock { $0 = pipeline }
    }

    func pipeline() -> Pipeline? {
        storage.withLock { $0 }
    }
}

private final class TestProbeBag: @unchecked Sendable {
    private let lock = NSLock()
    private var probes: [OpaquePointer] = []

    func append(_ probe: OpaquePointer) {
        lock.withLock {
            probes.append(probe)
        }
    }

    func freeAll() {
        let current = lock.withLock {
            let current = probes
            probes.removeAll()
            return current
        }
        for probe in current {
            swift_gst_test_probe_free(probe)
        }
    }

    deinit {
        freeAll()
    }
}

private extension Result {
    var success: Success? {
        guard case .success(let value) = self else {
            return nil
        }
        return value
    }

    var failure: Failure? {
        guard case .failure(let error) = self else {
            return nil
        }
        return error
    }
}
