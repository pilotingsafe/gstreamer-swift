import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("AudioSource Reliable Live Behavior", .timeLimit(.minutes(1)))
struct AudioSourceReliableLiveBehaviorTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Nominal synthetic live flow yields packets without prior discontinuity")
    func nominalSyntheticLiveFlowYieldsPacketsWithoutPriorDiscontinuity() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence)
        }

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.emit(.packet(Self.buffer(pts: 20, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await collected.value
        #expect(packets.count == 2)
        #expect(packets.dropFirst().allSatisfy { $0.priorDiscontinuity == nil })
    }

    @Test("GAP event annotates the next reliable packet")
    func gapEventAnnotatesNextReliablePacket() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence)
        }

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await Task.sleep(for: .milliseconds(10))
        try await harness.emit(.gap(pts: 1_000, duration: 250))
        try await harness.emit(.packet(Self.buffer(pts: 1_250, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await collected.value
        let discontinuity = try #require(packets.last?.priorDiscontinuity)
        #expect(discontinuity.kind == .gap)
        #expect(discontinuity.priorPTS == 0)
        #expect(discontinuity.priorDuration == 20)
        #expect(discontinuity.nextPTS == 1_250)
        #expect(discontinuity.duration == 1_230)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("GAP buffer flag annotates the current reliable packet")
    func gapBufferFlagAnnotatesCurrentReliablePacket() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()
        var buffer = try Self.buffer(pts: 20, duration: 20)
        buffer.setReliableLiveGapFlagForTesting()

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.emit(.packet(buffer))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        let discontinuity = try #require(packets.last?.priorDiscontinuity)
        #expect(discontinuity.kind == .gap)
        #expect(discontinuity.nextPTS == 20)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("DISCONT event annotates the next reliable packet")
    func discontEventAnnotatesNextReliablePacket() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.discont)
        try await harness.emit(.packet(Self.buffer(pts: 2_000, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        let discontinuity = try #require(packets.first?.priorDiscontinuity)
        #expect(discontinuity.kind == .discont)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("DISCONT buffer flag annotates the current reliable packet")
    func discontBufferFlagAnnotatesCurrentReliablePacket() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()
        var buffer = try Self.buffer(pts: 2_000, duration: 20)
        buffer.setReliableLiveDiscontFlagForTesting()

        try await harness.emit(.packet(buffer))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        let discontinuity = try #require(packets.first?.priorDiscontinuity)
        #expect(discontinuity.kind == .discont)
        #expect(discontinuity.nextPTS == 2_000)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("Format change annotates the next reliable packet")
    func formatChangeAnnotatesNextReliablePacket() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.formatChange)
        try await harness.emit(.packet(Self.buffer(pts: 3_000, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        let discontinuity = try #require(packets.first?.priorDiscontinuity)
        #expect(discontinuity.kind == .formatChange)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("PTS gap infers dropped discontinuity with duration formula")
    func ptsGapInfersDroppedDiscontinuityWithDurationFormula() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 100)))
        try await harness.emit(.packet(Self.buffer(pts: 350, duration: 100)))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        let discontinuity = try #require(packets.last?.priorDiscontinuity)
        #expect(discontinuity.kind == .dropped)
        #expect(discontinuity.priorPTS == 0)
        #expect(discontinuity.priorDuration == 100)
        #expect(discontinuity.nextPTS == 350)
        #expect(discontinuity.duration == 250)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("Explicit discontinuities take precedence over inferred PTS drops")
    func explicitDiscontinuitiesTakePrecedenceOverInferredPTSDrops() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 100)))
        try await harness.emit(.gap(pts: 100, duration: 100))
        try await harness.emit(.discont)
        try await harness.emit(.formatChange)
        try await harness.emit(.packet(Self.buffer(pts: 400, duration: 100)))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        let discontinuity = try #require(packets.last?.priorDiscontinuity)
        #expect(discontinuity.kind == .formatChange)
        #expect(discontinuity.droppedCount == nil)
    }

    @Test("Non-leaky slow consumer receives all synthetic reliable packets")
    func nonLeakySlowConsumerReceivesAllSyntheticReliablePackets() async throws {
        let harness = try Self.makeHarness(leaky: .none, maxBuffers: 2)
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence, delay: .milliseconds(2))
        }

        for index in 0..<20 {
            try await harness.emit(.packet(Self.buffer(pts: UInt64(index * 20), duration: 20)))
        }
        try await harness.emit(.eos)

        let packets = try await collected.value
        #expect(packets.count == 20)
    }

    @Test("Downstream-leaky slow consumer remains bounded without exact drop assertions")
    func downstreamLeakySlowConsumerRemainsBoundedWithoutExactDropAssertions() async throws {
        let harness = try Self.makeHarness(leaky: .downstream, maxBuffers: 2)
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence, delay: .milliseconds(2))
        }

        for index in 0..<20 {
            try await harness.emit(.packet(Self.buffer(pts: UInt64(index * 20), duration: 20)))
        }
        try await harness.emit(.eos)

        let packets = try await collected.value
        #expect((1...20).contains(packets.count))
    }

    @Test("Clean EOS completes reliable packet iteration")
    func cleanEOSCompletesReliablePacketIteration() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await Self.collect(sequence)
        #expect(packets.count == 1)
        try await Self.expectCleanEOSCleanup(for: harness)
    }

    @Test("Packet and EOS before reliable subscription drains packet then completes")
    func packetAndEOSBeforeReliableSubscriptionDrainsPacketThenCompletes() async throws {
        let harness = try Self.makeHarness()

        try await harness.emit(.packet(Self.buffer(pts: 100, duration: 20)))
        try await harness.emit(.eos)

        let sequence = try harness.source.reliablePackets()
        let packets = try await Self.withTimeout(.seconds(1)) {
            try await Self.collect(sequence)
        }

        #expect(packets.count == 1)
        let packet = try #require(packets.first)
        #expect(packet.pts == 100)
        #expect(packet.duration == 20)
        try await Self.expectCleanEOSCleanup(for: harness)
    }

    @Test("Zero-size live marker before queued packet drains packet before EOS")
    func zeroSizeLiveMarkerBeforeQueuedPacketDrainsPacketBeforeEOS() async throws {
        let harness = try Self.makeHarness(appSinkMaxBuffers: 4)
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.packet(Self.liveMarker(pts: 80, duration: 20)))
        try await harness.emit(.packet(Self.buffer(pts: 100, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await Self.withTimeout(.seconds(1)) {
            try await Self.collect(sequence)
        }

        #expect(packets.count == 1)
        let packet = try #require(packets.first)
        #expect(packet.pts == 100)
        #expect(packet.duration == 20)
        #expect(packet.payload.size == 4)
        try await Self.expectCleanEOSCleanup(for: harness)
    }

    @Test("EOS before reliable subscription completes empty")
    func eosBeforeReliableSubscriptionCompletesEmpty() async throws {
        let harness = try Self.makeHarness()

        try await harness.emit(.eos)

        let sequence = try harness.source.reliablePackets()
        let packets = try await Self.withTimeout(.seconds(1)) {
            try await Self.collect(sequence)
        }

        #expect(packets.isEmpty)
        try await Self.expectCleanEOSCleanup(for: harness)
    }

    @Test("Bus error before reliable subscription throws")
    func busErrorBeforeReliableSubscriptionThrows() async throws {
        let harness = try Self.makeHarness()
        let pipeline = try #require(harness.source.reliablePacketPipelineForTesting())

        #expect(swift_gst_test_post_bus_error(
            pipeline._element,
            "Injected pre-subscription bus error",
            "pre-subscription"
        ) != 0)

        let sequence = try harness.source.reliablePackets()
        let error = try #require(await Self.captureAsyncError {
            _ = try await Self.withTimeout(.seconds(1)) {
                try await Self.collect(sequence)
            }
        })
        let fields = try #require(Self.busErrorFields(error))

        #expect(fields.message == "Injected pre-subscription bus error")
        #expect(fields.debug == "pre-subscription")
        #expect(fields.source?.isEmpty == false)
    }

    @Test("Appsink EOS state completes when EOS callbacks are suppressed")
    func appsinkEOSStateCompletesWhenEOSCallbacksAreSuppressed() async throws {
        let harness = try Self.makeHarness(suppressEOSCallbacksForTesting: true)

        try await harness.emit(.eos)

        let sequence = try harness.source.reliablePackets()
        let packets = try await Self.withTimeout(.seconds(1)) {
            try await Self.collect(sequence)
        }

        #expect(packets.isEmpty)
        try await Self.expectCleanEOSCleanup(for: harness)
    }

    @Test("Clean EOS releases retained caps after format change")
    func cleanEOSReleasesRetainedCapsAfterFormatChange() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence)
        }

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.emit(.formatChange)
        try await harness.emit(.packet(Self.buffer(pts: 20, duration: 20)))
        try await harness.emit(.eos)

        let packets = try await collected.value
        #expect(packets.compactMap(\.pts) == [0, 20])
        let discontinuity = try #require(packets.last?.priorDiscontinuity)
        #expect(discontinuity.kind == .formatChange)
        try await Self.expectCleanEOSCleanup(for: harness)
    }

    @Test("Bus error fails reliable packet iteration")
    func busErrorFailsReliablePacketIteration() async throws {
        let harness = try Self.makeHarness()
        let sequence = try harness.source.reliablePackets()

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.emit(.busError(message: "Injected reliable live bus error", source: "test", debug: "debug"))

        let error = try #require(await Self.captureAsyncError {
            _ = try await Self.collect(sequence)
        })
        Self.expectBusError(
            error,
            message: "Injected reliable live bus error",
            source: "test",
            debug: "debug"
        )
    }

    @Test("Finalize sends EOS and drains tail packets")
    func finalizeSendsEOSAndDrainsTailPackets() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .emitEOSOnSendEOS)
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence)
        }

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.emit(.packet(Self.buffer(pts: 20, duration: 20)))
        try await harness.source.finalize(timeout: .seconds(1))

        let packets = try await collected.value
        let snapshot = await harness.snapshot()
        #expect(packets.compactMap(\.pts) == [0, 20])
        #expect(snapshot.sentEOSCount == 1)
        #expect(snapshot.activeSequenceID == nil)
    }

    @Test("Finalize surfaces bus errors")
    func finalizeSurfacesBusErrors() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .emitBusErrorOnSendEOS(
            message: "Injected finalize bus error",
            source: "test",
            debug: "finalize"
        ))

        let error = try #require(await Self.captureAsyncError {
            try await harness.source.finalize(timeout: .seconds(1))
        })
        Self.expectBusError(
            error,
            message: "Injected finalize bus error",
            source: "test",
            debug: "finalize"
        )
    }

    @Test("Finalize timeout fails when EOS never arrives")
    func finalizeTimeoutFailsWhenEOSNeverArrives() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .ignoreSendEOS)

        let error = try #require(await Self.captureAsyncError {
            try await harness.source.finalize(timeout: .milliseconds(20))
        })

        Self.expectBusError(
            error,
            message: "Timed out waiting for EOS during live reliable finalization",
            source: "AudioSource.finalize",
            debug: "timeout=20000000"
        )
    }

    @Test("Finalize reports failed sendEOS hook")
    func finalizeReportsFailedSendEOSHook() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .failSendEOS)

        let error = try #require(await Self.captureAsyncError {
            try await harness.source.finalize(timeout: .seconds(1))
        })

        Self.expectBusError(
            error,
            message: "Failed to send EOS event",
            source: "AudioSource.finalize",
            debug: nil
        )
    }

    @Test("Concurrent failing finalize attempts replay the same failure")
    func concurrentFailingFinalizeAttemptsReplayTheSameFailure() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .ignoreSendEOS)
        let timeout: Duration = .milliseconds(100)

        let first = Task {
            await Self.asyncResult {
                try await harness.source.finalize(timeout: timeout)
            }
        }
        let sentEOS = await ReliablePacketsTests.waitUntil(timeout: .seconds(1)) {
            let snapshot = await harness.snapshot()
            return snapshot.sentEOSCount == 1
        }
        try #require(sentEOS, "Expected first finalize to send EOS before starting the replaying finalize")

        let second = Task {
            await Self.asyncResult {
                try await harness.source.finalize(timeout: timeout)
            }
        }

        let results = await [first.value, second.value]
        let errors = results.compactMap(\.failure)
        #expect(errors.count == 2)
        let firstError = try #require(errors.first)
        let firstFields = try #require(Self.busErrorFields(firstError))
        #expect(firstFields.message == "Timed out waiting for EOS during live reliable finalization")
        #expect(firstFields.source == "AudioSource.finalize")
        #expect(firstFields.debug == "timeout=100000000")

        let secondError = try #require(errors.dropFirst().first)
        let secondFields = try #require(Self.busErrorFields(secondError))
        #expect(secondFields == firstFields)

        let snapshot = await harness.snapshot()
        #expect(snapshot.sentEOSCount == 1)
    }

    @Test("Late finalize attempts replay prior failure")
    func lateFinalizeAttemptsReplayPriorFailure() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .emitBusErrorOnSendEOS(
            message: "Injected replay finalize bus error",
            source: "test",
            debug: "replay"
        ))

        let firstError = try #require(await Self.captureAsyncError {
            try await harness.source.finalize(timeout: .seconds(1))
        })
        let firstFields = try #require(Self.busErrorFields(firstError))
        #expect(firstFields.message == "Injected replay finalize bus error")
        #expect(firstFields.source == "test")
        #expect(firstFields.debug == "replay")

        let firstSnapshot = await harness.snapshot()
        #expect(firstSnapshot.sentEOSCount == 1)

        let secondError = try #require(await Self.captureAsyncError {
            try await harness.source.finalize(timeout: .seconds(1))
        })
        let secondFields = try #require(Self.busErrorFields(secondError))
        #expect(secondFields == firstFields)

        let secondSnapshot = await harness.snapshot()
        #expect(secondSnapshot.sentEOSCount == 1)
    }

    @Test("Stop racing with in-flight failing finalize replays failure")
    func stopRacingWithInFlightFailingFinalizeReplaysFailure() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .ignoreSendEOS)
        let timeout: Duration = .milliseconds(50)

        let first = Task {
            await Self.asyncResult {
                try await harness.source.finalize(timeout: timeout)
            }
        }
        let sentEOS = await ReliablePacketsTests.waitUntil(timeout: .seconds(1)) {
            let snapshot = await harness.snapshot()
            return snapshot.sentEOSCount == 1
        }
        try #require(sentEOS, "Expected first finalize to send EOS before stop races it")

        await harness.source.stop()

        let second = Task {
            await Self.asyncResult {
                try await harness.source.finalize(timeout: timeout)
            }
        }

        let results = await [first.value, second.value]
        let errors = results.compactMap(\.failure)
        #expect(errors.count == 2)
        let firstError = try #require(errors.first)
        let firstFields = try #require(Self.busErrorFields(firstError))
        #expect(firstFields.message == "Timed out waiting for EOS during live reliable finalization")
        #expect(firstFields.source == "AudioSource.finalize")
        #expect(firstFields.debug == "timeout=50000000")

        let secondError = try #require(errors.dropFirst().first)
        let secondFields = try #require(Self.busErrorFields(secondError))
        #expect(secondFields == firstFields)

        let snapshot = await harness.snapshot()
        #expect(snapshot.sentEOSCount == 1)
    }

    @Test("Duplicate finalize attempts are idempotent")
    func duplicateFinalizeAttemptsAreIdempotent() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .emitEOSOnSendEOS)

        async let first = Self.asyncResult {
            try await harness.source.finalize(timeout: .seconds(1))
        }
        async let second = Self.asyncResult {
            try await harness.source.finalize(timeout: .seconds(1))
        }
        let results = await [first, second]

        #expect(results.filter(\.isSuccess).count == 2)
        let snapshot = await harness.snapshot()
        #expect(snapshot.sentEOSCount == 1)
    }

    @Test("Stop before finalize leaves reliable delivery inactive")
    func stopBeforeFinalizeLeavesReliableDeliveryInactive() async throws {
        let harness = try Self.makeHarness()

        await harness.source.stop()
        try await harness.source.finalize(timeout: .milliseconds(20))

        let snapshot = await harness.snapshot()
        #expect(snapshot.activeSequenceID == nil)
        #expect(snapshot.sentEOSCount == 0)
    }

    @Test("Finalize before stop completes and stop remains harmless")
    func finalizeBeforeStopCompletesAndStopRemainsHarmless() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .emitEOSOnSendEOS)

        try await harness.source.finalize(timeout: .seconds(1))
        await harness.source.stop()

        let snapshot = await harness.snapshot()
        #expect(snapshot.activeSequenceID == nil)
        #expect(snapshot.stopCount >= 1)
    }

    @Test("One active reliable sequence is enforced per AudioSource")
    func oneActiveReliableSequenceIsEnforcedPerAudioSource() async throws {
        let harness = try Self.makeHarness()
        _ = try harness.source.reliablePackets()

        let error = try #require(Self.captureError {
            _ = try harness.source.reliablePackets()
        })

        Self.expectInvalidArgument(
            error,
            parameter: "AudioSource.reliablePackets",
            reason: "Reliable delivery already has an active sequence"
        )
    }

    @Test("Reliable source packets stream is empty and cannot compete for appsink samples")
    func reliableSourcePacketsStreamIsEmptyAndCannotCompeteForAppSinkSamples() async throws {
        let harness = try Self.makeHarness()

        var packetsIterator = harness.source.packets().makeAsyncIterator()
        let lossyPacket = await packetsIterator.next()

        #expect(lossyPacket == nil)
    }

    @Test("Concurrent reliable sequence attempts reject one caller")
    func concurrentReliableSequenceAttemptsRejectOneCaller() async throws {
        let harness = try Self.makeHarness()

        async let first = Self.asyncResult {
            try harness.source.reliablePackets()
        }
        async let second = Self.asyncResult {
            try harness.source.reliablePackets()
        }
        let results = await [first, second]

        #expect(results.filter(\.isSuccess).count == 1)
        let error = try #require(results.compactMap(\.failure).first)
        Self.expectInvalidArgument(
            error,
            parameter: "AudioSource.reliablePackets",
            reason: "Reliable delivery already has an active sequence"
        )
    }

    @Test("Successful finalize clears active reliable sequence")
    func successfulFinalizeClearsActiveReliableSequence() async throws {
        let harness = try Self.makeHarness(finalizeBehavior: .emitEOSOnSendEOS)
        let sequence = try harness.source.reliablePackets()
        let collected = Task {
            try await Self.collect(sequence)
        }

        try await harness.emit(.packet(Self.buffer(pts: 0, duration: 20)))
        try await harness.source.finalize(timeout: .seconds(1))
        _ = try await collected.value

        let snapshot = await harness.snapshot()
        #expect(snapshot.activeSequenceID == nil)
    }

    @Test("Cancellation cleanup clears handler and pending continuation counts")
    func cancellationCleanupClearsHandlerAndPendingContinuationCounts() async throws {
        let harness = try Self.makeHarness()
        let task = Task<ReliablePacket<Buffer>?, Error> {
            let sequence = try harness.source.reliablePackets()
            let iterator = sequence.makeAsyncIterator()
            return try await iterator.next()
        }

        let becamePending = await ReliablePacketsTests.waitUntil(timeout: .seconds(1)) {
            let snapshot = await harness.snapshot()
            return snapshot.pendingContinuationCount == 1
        }
        #expect(becamePending)

        task.cancel()
        _ = await Self.asyncResult {
            try await task.value
        }

        let cleanedUp = await ReliablePacketsTests.waitUntil(timeout: .seconds(1)) {
            let snapshot = await harness.snapshot()
            return snapshot.newSampleHandlerCount == 0 && snapshot.pendingContinuationCount == 0
        }
        #expect(cleanedUp)
    }

    private static func makeHarness(
        leaky: QueueLeaky = .none,
        maxBuffers: UInt? = 4,
        maxBytes: UInt? = nil,
        maxTime: Duration? = .seconds(2),
        finalizeBehavior: ReliableLiveFinalizeBehaviorForTesting = .emitEOSOnSendEOS,
        suppressEOSCallbacksForTesting: Bool = false,
        appSinkMaxBuffers: UInt = 1
    ) throws -> ReliableLiveAudioSourceHarnessForTesting {
        try ReliableLiveAudioSourceHarnessForTesting(
            encoding: .opus(bitrate: 64_000),
            delivery: ReliableLiveDeliveryConfigurationForTesting(
                leaky: leaky,
                maxBuffers: maxBuffers,
                maxBytes: maxBytes,
                maxTime: maxTime
            ),
            finalizeBehavior: finalizeBehavior,
            suppressEOSCallbacksForTesting: suppressEOSCallbacksForTesting,
            appSinkMaxBuffers: appSinkMaxBuffers
        )
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
                throw AsyncTestTimeoutError(timeout: timeout)
            }

            defer {
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw AsyncTestTimeoutError(timeout: timeout)
            }
            return result
        }
    }

    private static func collect(
        _ sequence: ReliablePackets<ReliablePacket<Buffer>>,
        delay: Duration? = nil
    ) async throws -> [ReliablePacket<Buffer>] {
        var packets: [ReliablePacket<Buffer>] = []
        for try await packet in sequence {
            packets.append(packet)
            if let delay {
                try await Task.sleep(for: delay)
            }
        }
        return packets
    }

    private static func buffer(pts: UInt64, duration: UInt64) throws -> Buffer {
        try Buffer(data: [0, 1, 2, 3], pts: pts, duration: duration)
    }

    private static func liveMarker(pts: UInt64, duration: UInt64) throws -> Buffer {
        try Buffer(data: [], pts: pts, duration: duration)
    }

    private static func captureError(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private static func captureAsyncError(_ body: () async throws -> Void) async -> Error? {
        do {
            try await body()
            return nil
        } catch {
            return error
        }
    }

    private static func asyncResult<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async -> AsyncTestResult<T> {
        do {
            return .success(try await body())
        } catch {
            return .failure(error)
        }
    }

    private static func expectCleanEOSCleanup(
        for harness: ReliableLiveAudioSourceHarnessForTesting
    ) async throws {
        let cleanedUp = await ReliablePacketsTests.waitUntil(timeout: .seconds(1)) {
            let snapshot = await harness.snapshot()
            let runtime = harness.source.reliablePacketRuntimeSnapshotForTesting()
            return snapshot.newSampleHandlerCount == 0
                && snapshot.pendingContinuationCount == 0
                && snapshot.cleanupAcknowledgementCount >= 1
                && snapshot.activeSequenceID == nil
                && runtime.activePipeline == nil
        }
        try #require(cleanedUp, "Expected natural EOS cleanup to clear reliable runtime state")

        let snapshot = await harness.snapshot()
        #expect(snapshot.newSampleHandlerCount == 0)
        #expect(snapshot.pendingContinuationCount == 0)
        #expect(snapshot.cleanupAcknowledgementCount >= 1)
        #expect(snapshot.activeSequenceID == nil)
        #expect(harness.source.reliablePacketRuntimeSnapshotForTesting().activePipeline == nil)
    }

    private static func busErrorFields(_ error: Error) -> BusErrorFields? {
        guard case GStreamerError.busError(let message, let source, let debug) = error else {
            return nil
        }

        return BusErrorFields(message: message, source: source, debug: debug)
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

    private static func expectBusError(
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
        #expect(source == expectedSource)
        #expect(debug == expectedDebug)
    }
}

private struct BusErrorFields: Equatable, Sendable {
    let message: String
    let source: String?
    let debug: String?
}

private struct AsyncTestTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}

private enum AsyncTestResult<Success: Sendable>: @unchecked Sendable {
    case success(Success)
    case failure(Error)

    var isSuccess: Bool {
        guard case .success = self else { return false }
        return true
    }

    var failure: Error? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
