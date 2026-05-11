import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Bus Message Sequence Tests", .timeLimit(.minutes(1)))
struct BusMessageSequenceTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Pull sequence receives EOS from finite pipeline")
    func messageSequenceReceivesEOSFromFinitePipeline() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        try pipeline.play()
        defer { pipeline.stop() }

        let message = try #require(
            try await Self.firstMessage(
                in: pipeline.bus.messageSequence(filter: [.eos, .error]),
                timeout: .seconds(2)
            )
        )

        switch message {
        case .eos:
            break
        case .error(let message, let debug):
            Issue.record("Unexpected pipeline error: \(message), debug: \(String(describing: debug))")
        default:
            Issue.record("Expected EOS, got \(String(describing: message))")
        }
    }

    @Test("Pull sequence receives injected bus errors")
    func messageSequenceReceivesInjectedBusError() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        #expect(swift_gst_test_post_bus_error(
            pipeline._element,
            "ADR-002 injected bus error",
            "bus-sequence-test"
        ) != 0)

        let message = try #require(
            try await Self.firstMessage(
                in: pipeline.bus.messageSequence(filter: .error),
                timeout: .seconds(2)
            )
        )

        guard case .error(let errorMessage, let debug) = message else {
            Issue.record("Expected injected error, got \(String(describing: message))")
            return
        }

        #expect(errorMessage == "ADR-002 injected bus error")
        #expect(debug == "bus-sequence-test")
    }

    @Test("Pull sequence receives state changes")
    func messageSequenceReceivesStateChanges() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")
        var iterator = pipeline.bus.messageSequence(filter: [.stateChanged, .eos, .error])
            .makeAsyncIterator()

        try pipeline.play()
        defer { pipeline.stop() }

        var stateChangeCount = 0
        while true {
            let step = try await Self.nextWithTimeout(iterator, timeout: .seconds(2))
            iterator = step.iterator

            guard let message = step.message else {
                break
            }

            switch message {
            case .stateChanged:
                stateChangeCount += 1
            case .eos:
                #expect(stateChangeCount > 0)
                return
            case .error(let message, let debug):
                Issue.record("Unexpected pipeline error: \(message), debug: \(String(describing: debug))")
                return
            default:
                continue
            }
        }

        #expect(stateChangeCount > 0)
    }

    @Test("Pull sequence cancellation before a matching message returns nil")
    func messageSequenceCancellationBeforeMatchingMessageReturnsNil() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")
        let iterator = pipeline.bus.messageSequence(filter: .error).makeAsyncIterator()
        let nextTask = Task {
            await Self.nextMessage(from: iterator)
        }

        nextTask.cancel()

        let message = try await Self.withTimeout(.milliseconds(500)) {
            await nextTask.value
        }

        #expect(Self.isNil(message))
    }

    @Test("Pull sequence does not terminate after EOS")
    func messageSequenceDoesNotTerminateAfterEOS() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")
        var iterator = pipeline.bus.messageSequence(filter: [.eos, .error]).makeAsyncIterator()

        try pipeline.play()
        defer { pipeline.stop() }

        let firstStep = try await Self.nextWithTimeout(iterator, timeout: .seconds(2))
        iterator = firstStep.iterator
        let firstMessage = try #require(firstStep.message)

        switch firstMessage {
        case .eos:
            break
        case .error(let message, let debug):
            Issue.record("Unexpected pipeline error: \(message), debug: \(String(describing: debug))")
            return
        default:
            Issue.record("Expected EOS, got \(String(describing: firstMessage))")
            return
        }

        let secondIterator = iterator
        let completion = BusMessageTaskCompletion()
        let secondNext = Task {
            await Self.nextMessage(from: secondIterator)
        }
        let watcher = Task {
            await completion.finish(secondNext.value)
        }

        try await Task.sleep(for: .milliseconds(180))
        #expect(
            await !completion.isCompleted,
            "Expected second next() to remain pending after EOS"
        )

        secondNext.cancel()
        let completedAfterCancel = await Self.waitUntil(timeout: .milliseconds(500)) {
            await completion.isCompleted
        }

        #expect(completedAfterCancel, "Expected cancellation to complete pending next() within 500 ms")
        if !completedAfterCancel {
            #expect(swift_gst_test_post_bus_error(
                pipeline._element,
                "ADR-002 cancellation cleanup error",
                "bus-sequence-cleanup"
            ) != 0)
            _ = await Self.waitUntil(timeout: .seconds(1)) {
                await completion.isCompleted
            }
        }

        if await completion.isCompleted {
            await watcher.value
            let cancelledMessage = await completion.message
            #expect(Self.isNil(cancelledMessage))
        } else {
            Issue.record("Pending next() did not complete after cancellation")
            watcher.cancel()
        }
    }

    @Test("Existing AsyncStream messages still finishes after EOS")
    func messagesAsyncStreamStillFinishesAfterEOS() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        try pipeline.play()
        defer { pipeline.stop() }

        let result = try await Self.withTimeout(.seconds(2)) {
            var iterator = pipeline.bus.messages(filter: [.eos, .error]).makeAsyncIterator()
            let first = await iterator.next()
            let second = await iterator.next()
            return StreamEOSResult(first: first, second: second)
        }
        let first = try #require(result.first)

        switch first {
        case .eos:
            break
        case .error(let message, let debug):
            Issue.record("Unexpected pipeline error: \(message), debug: \(String(describing: debug))")
        default:
            Issue.record("Expected EOS, got \(String(describing: first))")
        }
        #expect(Self.isNil(result.second))
    }

    @Test("waitForEOS returns for finite pipeline")
    func waitForEOSReturnsForFinitePipeline() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        try pipeline.play()
        defer { pipeline.stop() }

        try await Self.withTimeout(.seconds(2)) {
            await pipeline.bus.waitForEOS()
        }
    }

    @Test("waitForEOSOrError returns for finite EOS")
    func waitForEOSOrErrorReturnsForFiniteEOS() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        try pipeline.play()
        defer { pipeline.stop() }

        try await Self.withTimeout(.seconds(2)) {
            try await pipeline.bus.waitForEOSOrError()
        }
    }

    @Test("waitForEOSOrError throws exact injected bus error")
    func waitForEOSOrErrorThrowsExactInjectedBusError() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")
        let message = "ADR-002 waitForEOSOrError injected bus error"
        let debug = "wait-for-eos-or-error"

        #expect(swift_gst_test_post_bus_error(pipeline._element, message, debug) != 0)

        let error = try #require(await Self.captureAsyncError {
            try await Self.withTimeout(.seconds(2)) {
                try await pipeline.bus.waitForEOSOrError()
            }
        })

        Self.expectBusError(
            error,
            message: message,
            source: nil,
            debug: debug
        )
    }

    @Test("waitForEOSOrError throws CancellationError when cancelled before EOS or ERROR")
    func waitForEOSOrErrorThrowsCancellationErrorWhenCancelledBeforeEOSOrError() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")
        let task = Task {
            try await pipeline.bus.waitForEOSOrError()
        }
        defer { task.cancel() }

        await Task.yield()
        task.cancel()

        let error = try #require(await Self.captureAsyncError {
            try await Self.withTimeout(.milliseconds(500)) {
                try await task.value
            }
        })

        #expect(error is CancellationError)
    }

    @Test("Deprecated waitForEOS returns on ERROR before EOS")
    func deprecatedWaitForEOSReturnsOnErrorBeforeEOS() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! fakesink")

        #expect(swift_gst_test_post_bus_error(
            pipeline._element,
            "ADR-002 deprecated waitForEOS injected bus error",
            "deprecated-wait-for-eos"
        ) != 0)

        try await Self.withTimeout(.seconds(2)) {
            await pipeline.bus.waitForEOS()
        }
    }

    private static func firstMessage(
        in sequence: Bus.Messages,
        timeout: Duration
    ) async throws -> BusMessage? {
        try await withTimeout(timeout) {
            var iterator = sequence.makeAsyncIterator()
            return await iterator.next()
        }
    }

    private static func nextWithTimeout(
        _ iterator: Bus.Messages.AsyncIterator,
        timeout: Duration
    ) async throws -> BusMessageIteratorStep {
        try await withTimeout(timeout) {
            await Self.next(from: iterator)
        }
    }

    private static func next(from iterator: Bus.Messages.AsyncIterator) async -> BusMessageIteratorStep {
        var iterator = iterator
        let message = await iterator.next()
        return BusMessageIteratorStep(message: message, iterator: iterator)
    }

    private static func nextMessage(from iterator: Bus.Messages.AsyncIterator) async -> BusMessage? {
        var iterator = iterator
        return await iterator.next()
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
                throw BusSequenceTimeoutError(timeout: timeout)
            }

            defer {
                group.cancelAll()
            }

            guard let result = try await group.next() else {
                throw BusSequenceTimeoutError(timeout: timeout)
            }
            return result
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

    private static func isNil(_ message: BusMessage?) -> Bool {
        guard case nil = message else {
            return false
        }
        return true
    }

    private static func waitUntil(
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
}

private struct BusMessageIteratorStep: Sendable {
    let message: BusMessage?
    let iterator: Bus.Messages.AsyncIterator
}

private struct StreamEOSResult: Sendable {
    let first: BusMessage?
    let second: BusMessage?
}

private struct BusSequenceTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}

private actor BusMessageTaskCompletion {
    private(set) var isCompleted = false
    private(set) var message: BusMessage?

    func finish(_ message: BusMessage?) {
        self.message = message
        isCompleted = true
    }
}
