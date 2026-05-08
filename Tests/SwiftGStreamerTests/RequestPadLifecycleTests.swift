import Testing
@testable import GStreamer

@Suite("Request Pad Lifecycle Tests", .timeLimit(.minutes(1)))
struct RequestPadLifecycleTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Repeated manual release removes one requested tee pad and records one release")
    func manualReleaseIsIdempotent() throws {
        let tee = try Element.make(factory: "tee", name: "manual-release-tee")
        let initialPadCount = tee.debugPadCount
        let pad = try #require(tee.requestPad("src_%u"))

        #expect(pad.name.hasPrefix("src_"))
        #expect(tee.debugPadCount == initialPadCount + 1)
        #expect(!pad.debugIsRequestPadReleased)
        #expect(pad.debugRequestReleaseCallCount == 0)

        tee.releasePad(pad)
        tee.releasePad(pad)
        tee.releasePad(pad)

        #expect(tee.debugPadCount == initialPadCount)
        #expect(pad.debugIsRequestPadReleased)
        #expect(pad.debugRequestReleaseCallCount == 1)
    }

    @Test("releasePad ignores pads requested by another element")
    func releasePadRejectsWrongOwner() throws {
        let tee1 = try Element.make(factory: "tee", name: "owner-tee")
        let tee2 = try Element.make(factory: "tee", name: "wrong-owner-tee")
        let tee1InitialPadCount = tee1.debugPadCount
        let tee2InitialPadCount = tee2.debugPadCount
        let pad = try #require(tee1.requestPad("src_%u"))

        #expect(tee1.debugPadCount == tee1InitialPadCount + 1)
        #expect(tee2.debugPadCount == tee2InitialPadCount)

        tee2.releasePad(pad)

        #expect(tee1.debugPadCount == tee1InitialPadCount + 1)
        #expect(tee2.debugPadCount == tee2InitialPadCount)
        #expect(!pad.debugIsRequestPadReleased)
        #expect(pad.debugRequestReleaseCallCount == 0)

        tee1.releasePad(pad)

        #expect(tee1.debugPadCount == tee1InitialPadCount)
        #expect(tee2.debugPadCount == tee2InitialPadCount)
        #expect(pad.debugIsRequestPadReleased)
        #expect(pad.debugRequestReleaseCallCount == 1)
    }

    @Test("Manual release breaks owner retention before pad deinit")
    func manualReleaseBreaksOwnerRetentionBeforePadDeinit() throws {
        let ownerBox: WeakBox<Element>
        var retainedPad: Pad?

        do {
            let fixture = try Self.manuallyReleasedPadAfterDroppingAllOwnerReferences()
            ownerBox = fixture.ownerBox
            retainedPad = fixture.pad
        }

        let releaseDiagnostics = try #require(retainedPad?.debugRequestReleaseDiagnostics)
        let releaseCountBeforePadDrop = try #require(retainedPad?.debugRequestReleaseCallCount)

        #expect(ownerBox.value == nil)
        #expect(retainedPad?.debugIsRequestPadReleased == true)
        #expect(releaseCountBeforePadDrop == 1)

        // Deinit uses the same idempotent release path; this verifies a later
        // cleanup attempt cannot record a second per-pad release before drop.
        #expect(retainedPad?.releaseRequestPadIfNeeded() == false)
        #expect(retainedPad?.debugRequestReleaseCallCount == releaseCountBeforePadDrop)

        retainedPad = nil

        #expect(releaseDiagnostics.releaseCallCount == 1)
    }

    @Test("Concurrent release attempts for one requested pad have exactly one winner")
    func concurrentReleaseIsIdempotent() async throws {
        let tee = try Element.make(factory: "tee", name: "concurrent-release-tee")
        let initialPadCount = tee.debugPadCount
        let pad = try #require(tee.requestPad("src_%u"))

        #expect(pad.name.hasPrefix("src_"))
        #expect(tee.debugPadCount == initialPadCount + 1)
        #expect(!pad.debugIsRequestPadReleased)

        let releaseAttemptCount = 64
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<releaseAttemptCount {
                group.addTask {
                    tee.releasePad(pad)
                }
            }
        }

        #expect(tee.debugPadCount == initialPadCount)
        #expect(pad.debugIsRequestPadReleased)
        #expect(pad.debugRequestReleaseCallCount == 1)
    }

    @Test("Request pad keeps owner alive until pad deinit auto-releases once")
    func requestPadKeepsOwnerAliveUntilPadDeinit() throws {
        let ownerBox: WeakBox<Element>
        var retainedPad: Pad?

        do {
            let fixture = try Self.requestPadAfterDroppingAllOwnerReferences()
            ownerBox = fixture.ownerBox
            retainedPad = fixture.pad
        }

        #expect(ownerBox.value != nil)
        #expect(retainedPad?.debugRequestReleaseCallCount == 0)
        #expect(retainedPad?.debugIsRequestPadReleased == false)

        let releaseDiagnostics = try #require(retainedPad?.debugRequestReleaseDiagnostics)
        retainedPad = nil

        #expect(ownerBox.value == nil)
        #expect(releaseDiagnostics.releaseCallCount == 1)
    }

    private static func manuallyReleasedPadAfterDroppingAllOwnerReferences() throws -> (pad: Pad, ownerBox: WeakBox<Element>) {
        let tee = try Element.make(factory: "tee", name: "manual-release-owner-tee")
        let ownerBox = WeakBox<Element>()
        ownerBox.value = tee

        let initialPadCount = tee.debugPadCount
        let pad = try #require(tee.requestPad("src_%u"))

        #expect(pad.name.hasPrefix("src_"))
        #expect(tee.debugPadCount == initialPadCount + 1)

        tee.releasePad(pad)

        #expect(tee.debugPadCount == initialPadCount)
        #expect(pad.debugIsRequestPadReleased)
        #expect(pad.debugRequestReleaseCallCount == 1)

        return (pad, ownerBox)
    }

    private static func requestPadAfterDroppingAllOwnerReferences() throws -> (pad: Pad, ownerBox: WeakBox<Element>) {
        let tee = try Element.make(factory: "tee", name: "auto-release-tee")
        let ownerBox = WeakBox<Element>()
        ownerBox.value = tee

        let initialPadCount = tee.debugPadCount
        let pad = try #require(tee.requestPad("src_%u"))

        #expect(pad.name.hasPrefix("src_"))
        #expect(tee.debugPadCount == initialPadCount + 1)

        return (pad, ownerBox)
    }

}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
}
