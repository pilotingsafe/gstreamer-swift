import Testing
import Synchronization
@testable import GStreamer

@Suite("QueueLeakyBehaviorTests", .timeLimit(.minutes(1)), .serialized)
struct QueueLeakyBehaviorTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Queue leaky direction matches GStreamer behavior")
    private func queueLeakyDirection() async throws {
        let upstream = try await runScenario(.upstream)
        let downstream = try await runScenario(.downstream)

        assertScenario(upstream)
        assertScenario(downstream)

        let upstreamPushedSet = Set(upstream.pushedTags)
        let downstreamPushedSet = Set(downstream.pushedTags)
        #expect(
            upstreamPushedSet == downstreamPushedSet,
            "Expected both scenarios to push the same tag set; upstream: \(upstream.diagnostics); downstream: \(downstream.diagnostics)"
        )

        let queuePushedTags = upstream.queuePushedTags
        try #require(
            queuePushedTags == downstream.queuePushedTags,
            "Expected both scenarios to share the same post-boundary pushed tags; upstream: \(upstream.diagnostics); downstream: \(downstream.diagnostics)"
        )

        let sortedQueuePushedTags = queuePushedTags.sorted()
        let earlyWindow = Set(sortedQueuePushedTags.prefix(upstream.maxBufferCount))
        let lateWindow = Set(sortedQueuePushedTags.suffix(downstream.maxBufferCount))
        let meanGap = try meanAdjacentGap(in: sortedQueuePushedTags)

        #expect(
            upstream.survivorTags.contains { earlyWindow.contains($0) },
            "Expected upstream leaky queue to retain an early post-exclusion survivor; \(upstream.diagnostics)"
        )
        #expect(
            downstream.survivorTags.contains { lateWindow.contains($0) },
            "Expected downstream leaky queue to retain a late post-exclusion survivor; \(downstream.diagnostics)"
        )
        #expect(
            upstream.mean + meanGap < downstream.mean,
            "Expected downstream survivor mean to exceed upstream survivor mean by more than one pushed-tag gap; upstream: \(upstream.diagnostics); downstream: \(downstream.diagnostics)"
        )
        #expect(
            upstream.median < downstream.median,
            "Expected downstream survivor median to exceed upstream survivor median; upstream: \(upstream.diagnostics); downstream: \(downstream.diagnostics)"
        )

        let upstreamCore = upstream.survivorTags.sorted().dropLast()
        let downstreamCore = downstream.survivorTags.sorted().dropFirst()
        let upstreamCoreMax = try #require(
            upstreamCore.max(),
            "Expected at least one upstream survivor after trimming largest; \(upstream.diagnostics)"
        )
        let downstreamCoreMin = try #require(
            downstreamCore.min(),
            "Expected at least one downstream survivor after trimming smallest; \(downstream.diagnostics)"
        )

        #expect(
            upstreamCoreMax < downstreamCoreMin,
            "Expected trimmed upstream survivors to precede trimmed downstream survivors; upstream: \(upstream.diagnostics); downstream: \(downstream.diagnostics)"
        )
    }

    private func runScenario(_ scenario: QueueLeakyScenario) async throws -> QueueLeakObservation {
        let maxBuffers = 3
        let pushed = (0..<32).map { UInt8($0) }
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

        let ingressProbeHandle = queueSinkPad.addProbe(type: .buffer) {
            ingressCounter.increment()
            return .ok
        }
        try #require(ingressProbeHandle.id != 0, "Expected q.sink ingress probe to remain installed")

        try pipeline.play()

        // Prime stream-start/segment flow before the idle blocker is installed.
        // The first measured tag is allowed to reach the blocked q.src boundary before the rest are pushed.
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
        try #require(blockHandle.id != 0, "Expected q.src blocking probe to remain installed")

        let gateActivated = await waitUntil(timeout: .seconds(5)) {
            gate.isActive
        }
        try #require(gateActivated, "Expected q.src idle/blocking probe to become active before pushing")

        let possibleInFlightTag = try #require(pushed.first)
        try src.push(data: [possibleInFlightTag], pts: frameDuration, duration: frameDuration)

        let firstBufferReachedBoundary = await waitUntil(timeout: .seconds(5)) {
            ingressCounter.value >= 1 && queue.getInt("current-level-buffers") == 0
        }
        try #require(
            firstBufferReachedBoundary,
            "Expected first pushed buffer to leave queue storage before flooding remaining buffers"
        )

        for index in pushed.indices.dropFirst() {
            let tag = pushed[index]
            let pts = UInt64(index + 1) * frameDuration
            try src.push(data: [tag], pts: pts, duration: frameDuration)
        }

        let allBuffersReachedQueue = await waitUntil(timeout: .seconds(10)) {
            ingressCounter.value >= pushed.count
        }
        try #require(
            allBuffersReachedQueue,
            """
            Expected q.sink ingress probe to observe all pushed buffers while q.src remained blocked; \
            observed \(ingressCounter.value) of \(pushed.count)
            """
        )

        try? await ContinuousClock().sleep(for: .milliseconds(50))
        let ingressCount = ingressCounter.value
        #expect(ingressCount >= pushed.count)

        queueSrcPad.removeProbe(blockHandle)
        src.endOfStream()

        var survivorTags: [UInt8] = []
        while let frame = try await iterator.next() {
            survivorTags.append(try readTag(from: frame))
        }

        let queuePushedTags = Array(pushed.dropFirst())
        let postExclusionSurvivorTags = survivorTags.filter { $0 != possibleInFlightTag }
        let diagnostics = """
        \(scenario.testDescription), pushed: \(pushed), post-boundary pushed: \(queuePushedTags), \
        raw survivors: \(survivorTags), post-exclusion survivors: \(postExclusionSurvivorTags), \
        excluded possible q.src in-flight tag: \(possibleInFlightTag), ingress: \(ingressCount), \
        max-buffers: \(maxBuffers)
        """

        try #require(
            postExclusionSurvivorTags.count >= 2,
            "Expected at least two post-exclusion survivors for directional comparison; \(diagnostics)"
        )

        return QueueLeakObservation(
            scenario: scenario,
            survivorTags: postExclusionSurvivorTags,
            rawSurvivorTags: survivorTags,
            mean: mean(of: postExclusionSurvivorTags),
            median: median(of: postExclusionSurvivorTags),
            pushedTags: pushed,
            maxBufferCount: maxBuffers,
            ingressCount: ingressCount,
            diagnostics: diagnostics
        )
    }

    private func assertScenario(_ observation: QueueLeakObservation) {
        let queuePushedTags = observation.queuePushedTags
        let queuePushedSet = Set(queuePushedTags)
        let survivorSet = Set(observation.survivorTags)

        #expect(
            observation.ingressCount >= observation.pushedTags.count,
            "Expected all pushed buffers to reach q.sink; \(observation.diagnostics)"
        )
        #expect(
            observation.survivorTags.count < queuePushedTags.count,
            "Expected leaky queue overflow to reduce post-exclusion survivors; \(observation.diagnostics)"
        )
        #expect(
            observation.rawSurvivorTags.count <= observation.maxBufferCount + 1,
            "Expected raw survivors to be bounded by max-buffers plus one possible q.src boundary buffer; \(observation.diagnostics)"
        )
        #expect(
            observation.survivorTags.count <= observation.maxBufferCount,
            "Expected post-exclusion survivors to be bounded by max-buffers; \(observation.diagnostics)"
        )
        #expect(
            survivorSet.isSubset(of: queuePushedSet),
            "Expected post-exclusion survivor tags to be within post-boundary pushed tags; \(observation.diagnostics)"
        )
    }

    private func mean(of tags: [UInt8]) -> Double {
        let sum = tags.reduce(0.0) { partialResult, tag in
            partialResult + Double(tag)
        }

        return sum / Double(tags.count)
    }

    private func median(of tags: [UInt8]) -> Double {
        let sortedTags = tags.sorted()
        let midpoint = sortedTags.count / 2

        if sortedTags.count.isMultiple(of: 2) {
            return (Double(sortedTags[midpoint - 1]) + Double(sortedTags[midpoint])) / 2
        }

        return Double(sortedTags[midpoint])
    }

    private func meanAdjacentGap(in sortedTags: [UInt8]) throws -> Double {
        try #require(sortedTags.count >= 2, "Expected at least two pushed tags to derive a mean gap")

        let gaps = zip(sortedTags, sortedTags.dropFirst()).map { lower, upper in
            Double(Int(upper) - Int(lower))
        }
        let total = gaps.reduce(0.0, +)

        return total / Double(gaps.count)
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

    static let upstream = QueueLeakyScenario(
        name: "upstream",
        leaky: 1
    )

    static let downstream = QueueLeakyScenario(
        name: "downstream",
        leaky: 2
    )

    var testDescription: String {
        "\(name) leaky=\(leaky)"
    }
}

private struct QueueLeakObservation: Sendable {
    let scenario: QueueLeakyScenario
    let survivorTags: [UInt8]
    let rawSurvivorTags: [UInt8]
    let mean: Double
    let median: Double
    let pushedTags: [UInt8]
    let maxBufferCount: Int
    let ingressCount: Int
    let diagnostics: String

    var queuePushedTags: [UInt8] {
        Array(pushedTags.dropFirst())
    }
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
