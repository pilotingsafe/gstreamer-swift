import Testing
import Synchronization
@testable import GStreamer

@Suite("QueueLeakyBehaviorTests", .timeLimit(.minutes(1)), .serialized)
struct QueueLeakyBehaviorTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test(
        "Queue leaky direction matches GStreamer behavior",
        arguments: [
            QueueLeakyScenario.upstream,
            .downstream,
        ]
    )
    private func queueLeakyDirection(_ scenario: QueueLeakyScenario) async throws {
        try await runScenario(scenario)
    }

    private func runScenario(_ scenario: QueueLeakyScenario) async throws {
        let maxBuffers = 3
        let pushed = (0..<8).map { UInt8($0) }
        let frameDuration: UInt64 = 1_000_000
        let pipeline = try Pipeline(
            """
            appsrc name=src format=time is-live=false block=false max-bytes=0 ! \
            queue name=q max-size-buffers=\(maxBuffers) max-size-bytes=0 max-size-time=0 leaky=\(scenario.leaky) ! \
            appsink name=sink sync=false drop=false max-buffers=0
            """
        )
        defer { pipeline.stop() }

        let src = try AppSource(pipeline: pipeline, name: "src")
        let sink = try AppSink(pipeline: pipeline, name: "sink")
        let queue = try #require(pipeline.element(named: "q"))
        let queueSrcPad = try #require(queue.staticPad("src"))
        let queueSinkPad = try #require(queue.staticPad("sink"))
        let gate = ProbeGate()
        let ingressCounter = ProbeCounter()

        queueSinkPad.addProbe(type: .buffer) {
            ingressCounter.increment()
            return .ok
        }

        try pipeline.play()

        // Prime stream-start/segment flow before the idle blocker is installed.
        // The measured tags below are still pushed only after q.src is idle-blocked.
        let primingTag = UInt8.max
        let iterator = sink.frames().makeAsyncIterator()
        try src.push(data: [primingTag], pts: 0, duration: frameDuration)
        let primingFrame = try #require(try await iterator.next(), "Expected priming frame to drain")
        let drainedPrimingTag = try readTag(from: primingFrame)
        #expect(drainedPrimingTag == primingTag)

        ingressCounter.reset()

        let blockHandle = queueSrcPad.addProbe(type: [.idle, .blocking]) {
            gate.activate()
            return .ok
        }
        #expect(blockHandle.id != 0, "Expected q.src blocking probe to remain installed")
        guard blockHandle.id != 0 else { return }

        let gateActivated = await waitUntil(timeout: .seconds(5)) {
            gate.isActive
        }
        #expect(gateActivated, "Expected q.src idle/blocking probe to become active before pushing")
        guard gateActivated else { return }

        let possibleInFlightTag = try #require(pushed.first)

        for (index, tag) in pushed.enumerated() {
            let pts = UInt64(index + 1) * frameDuration
            try src.push(data: [tag], pts: pts, duration: frameDuration)
        }

        let allBuffersReachedQueue = await waitUntil(timeout: .seconds(10)) {
            ingressCounter.value >= pushed.count
        }
        #expect(
            allBuffersReachedQueue,
            """
            Expected q.sink ingress probe to observe all pushed buffers while q.src remained blocked; \
            observed \(ingressCounter.value) of \(pushed.count)
            """
        )
        guard allBuffersReachedQueue else { return }

        try? await ContinuousClock().sleep(for: .milliseconds(50))
        #expect(ingressCounter.value >= pushed.count)

        queueSrcPad.removeProbe(blockHandle)
        src.endOfStream()

        var survivorTags: [UInt8] = []
        while let frame = try await iterator.next() {
            survivorTags.append(try readTag(from: frame))
        }

        let queuePushedTags = Array(pushed.dropFirst())
        let queueSurvivorTags = survivorTags.filter { $0 != possibleInFlightTag }
        let queueSurvivorSet = Set(queueSurvivorTags)
        let minQueuePushed = try #require(queuePushedTags.min())
        let maxQueuePushed = try #require(queuePushedTags.max())
        let survivorDiagnostics = "raw survivors: \(survivorTags), queue survivors: \(queueSurvivorTags)"

        #expect(pushed.count > maxBuffers)
        #expect(ingressCounter.value >= pushed.count)
        #expect(queuePushedTags.count > maxBuffers)
        #expect(
            queueSurvivorTags.count < queuePushedTags.count,
            "Expected queue-owned survivors to show overflow; \(survivorDiagnostics)"
        )

        switch scenario.expectedSurvivorEdge {
        case .oldest:
            #expect(
                queueSurvivorSet.contains(minQueuePushed),
                "Upstream leaky queue should keep the oldest queue-owned tag; \(survivorDiagnostics)"
            )
            #expect(
                !queueSurvivorSet.contains(maxQueuePushed),
                "Upstream leaky queue should drop the newest queue-owned tag; \(survivorDiagnostics)"
            )
        case .newest:
            #expect(
                queueSurvivorSet.contains(maxQueuePushed),
                "Downstream leaky queue should keep the newest queue-owned tag; \(survivorDiagnostics)"
            )
            #expect(
                !queueSurvivorSet.contains(minQueuePushed),
                "Downstream leaky queue should not include the oldest queue-owned tag; \(survivorDiagnostics)"
            )
        }
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await clock.sleep(for: pollInterval)
        }

        return condition()
    }

    private func readTag(from frame: VideoFrame) throws -> UInt8 {
        try frame.withUnsafeBytes { bytes in
            try #require(bytes.first, "Expected frame to contain a tag byte")
        }
    }
}

private struct QueueLeakyScenario: Sendable, CustomTestStringConvertible {
    let name: String
    let leaky: Int
    let expectedSurvivorEdge: SurvivorEdge

    static let upstream = QueueLeakyScenario(
        name: "upstream",
        leaky: 1,
        expectedSurvivorEdge: .oldest
    )

    static let downstream = QueueLeakyScenario(
        name: "downstream",
        leaky: 2,
        expectedSurvivorEdge: .newest
    )

    var testDescription: String {
        "\(name) leaky=\(leaky)"
    }
}

private enum SurvivorEdge: Sendable {
    case oldest
    case newest
}

private final class ProbeGate: @unchecked Sendable {
    private let storage = Mutex(false)

    func activate() {
        storage.withLock { isActive in
            isActive = true
        }
    }

    var isActive: Bool {
        storage.withLock { isActive in
            isActive
        }
    }
}

private final class ProbeCounter: @unchecked Sendable {
    private let storage = Mutex(0)

    func increment() {
        storage.withLock { count in
            count += 1
        }
    }

    func reset() {
        storage.withLock { count in
            count = 0
        }
    }

    var value: Int {
        storage.withLock { count in
            count
        }
    }
}
