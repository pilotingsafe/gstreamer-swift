import Testing
import Synchronization
import CGStreamer
@testable import GStreamer

@Suite("Pad Probe Tests", .timeLimit(.minutes(1)))
struct PadProbeTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Buffer probe callback fires")
    func bufferProbeCallbackFires() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = CallbackCounter()

        srcPad.addProbe(type: .buffer) {
            callbackCount.increment()
            return .ok
        }

        try pipeline.play()
        await waitForEOSOrFail(pipeline)

        #expect(callbackCount.value > 0)
    }

    @Test("Manual remove before playback suppresses callback")
    func manualRemoveBeforePlaybackSuppressesCallback() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=1 ! identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = CallbackCounter()

        let handle = srcPad.addProbe(type: .buffer) {
            callbackCount.increment()
            return .ok
        }
        srcPad.removeProbe(handle)

        try pipeline.play()
        await waitForEOSOrFail(pipeline)

        #expect(callbackCount.value == 0)
    }

    @Test("Zero probe handle removal is no-op")
    func zeroProbeHandleRemovalIsNoOp() throws {
        let pipeline = try Pipeline("identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))

        srcPad.removeProbe(Pad.ProbeHandle(id: 0))
    }

    @Test("Empty probe type returns invalid handle without invoking callback")
    func emptyProbeTypeReturnsInvalidHandle() throws {
        let pipeline = try Pipeline("identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = CallbackCounter()

        let handle = srcPad.addProbe(type: []) {
            callbackCount.increment()
            return .ok
        }

        #expect(handle.id == 0)
        #expect(callbackCount.value == 0)
    }

    @Test("Idle probe fires synchronously on idle pad and remove is safe")
    func idleProbeFiresSynchronouslyOnIdlePadAndRemoveIsSafe() throws {
        let pipeline = try Pipeline("identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = CallbackCounter()

        let handle = srcPad.addProbe(type: [.idle, .blocking]) {
            callbackCount.increment()
            return .remove
        }

        #expect(callbackCount.value == 1)
        #expect(handle.id == 0)

        srcPad.removeProbe(handle)

        #expect(callbackCount.value == 1)
    }

    @Test("Repeated immediate idle remove probes do not crash or double release")
    func repeatedImmediateIdleRemoveProbesDoNotCrashOrDoubleRelease() throws {
        let pipeline = try Pipeline("identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = CallbackCounter()
        var lastHandle = Pad.ProbeHandle(id: 0)

        for _ in 0..<1000 {
            let handle = srcPad.addProbe(type: [.idle, .blocking]) {
                callbackCount.increment()
                return .remove
            }

            #expect(handle.id == 0)
            lastHandle = handle
        }

        #expect(callbackCount.value == 1000)

        srcPad.removeProbe(lastHandle)
    }

    @Test("ProbeReturn maps to CGStreamer constants")
    func probeReturnMappingCoverage() {
        #expect(Pad.mapProbeReturn(.ok).rawValue == GST_PAD_PROBE_OK.rawValue)
        #expect(Pad.mapProbeReturn(.pass).rawValue == GST_PAD_PROBE_PASS.rawValue)
        #expect(Pad.mapProbeReturn(.drop).rawValue == GST_PAD_PROBE_DROP.rawValue)
        #expect(Pad.mapProbeReturn(.handled).rawValue == GST_PAD_PROBE_HANDLED.rawValue)
        #expect(Pad.mapProbeReturn(.remove).rawValue == GST_PAD_PROBE_REMOVE.rawValue)
    }

    @Test("Remove return removes probe after first callback")
    func removeReturnRemovesProbeAfterFirstCallback() async throws {
        let pipeline = try Pipeline("videotestsrc num-buffers=5 ! identity name=tap ! fakesink")
        defer { pipeline.stop() }

        let tap = try #require(pipeline.element(named: "tap"))
        let srcPad = try #require(tap.staticPad("src"))
        let callbackCount = CallbackCounter()

        srcPad.addProbe(type: .buffer) {
            callbackCount.increment()
            return .remove
        }

        try pipeline.play()
        await waitForEOSOrFail(pipeline)

        #expect(callbackCount.value == 1)
    }
}

private final class CallbackCounter: @unchecked Sendable {
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

private func waitForEOSOrFail(_ pipeline: Pipeline) async {
    for await message in pipeline.bus.messages(filter: [.eos, .error]) {
        switch message {
        case .eos:
            return
        case .error(let message, let debug):
            if let debug {
                Issue.record("Unexpected pipeline error: \(message) (\(debug))")
            } else {
                Issue.record("Unexpected pipeline error: \(message)")
            }
            return
        default:
            continue
        }
    }

    Issue.record("Pipeline bus stream ended before EOS")
}
