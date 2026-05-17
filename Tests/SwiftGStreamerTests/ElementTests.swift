import Testing
import CGStreamerTestSupport
@testable import GStreamer

// MARK: - Test Tags

extension Tag {
    /// Tests related to element factories.
    @Tag static var factory: Self
    /// Tests related to GStreamer element ownership.
    @Tag static var ownership: Self
    /// Tests related to element properties.
    @Tag static var properties: Self
    /// Tests related to pads and linking.
    @Tag static var pads: Self
}

@Suite("Element Tests", .serialized)
struct ElementTests {
    init() throws {
        try GStreamer.initialize()
    }

    @discardableResult
    private static func withFatalGStreamerCriticalTrap<T>(_ body: () throws -> T) rethrows -> T {
        swift_gst_test_lock_glib_log_state()
        let previous = swift_gst_test_enable_fatal_criticals()
        defer {
            swift_gst_test_restore_fatal_mask(previous)
            swift_gst_test_unlock_glib_log_state()
        }

        return try body()
    }

    private static func makeOwnershipPipeline() throws -> Pipeline {
        try Pipeline("fakesrc name=ownership_source ! fakesink name=ownership_sink")
    }

    // MARK: - Factory Tests

    @Test("Create element from various factories", .tags(.factory), arguments: [
        ("queue", "myqueue"),
        ("fakesink", "testsink"),
        ("fakesrc", "testsrc"),
        ("identity", "passthrough"),
        ("tee", "splitter"),
    ])
    func createFromFactory(factory: String, name: String) throws {
        let element = try Element.make(factory: factory, name: name)
        #expect(element.name == name)
    }

    @Test("Create element with auto-generated name", .tags(.factory), arguments: [
        "queue",
        "fakesink",
        "identity",
    ])
    func createWithAutoName(factory: String) throws {
        let element = try Element.make(factory: factory)
        #expect(!element.name.isEmpty)
    }

    @Test("Invalid factory throws error", .tags(.factory), arguments: [
        "nonexistent_element_xyz",
        "not_a_real_plugin",
        "",
    ])
    func invalidFactory(factory: String) throws {
        #expect(throws: GStreamerError.self) {
            _ = try Element.make(factory: factory)
        }
    }

    // MARK: - Pad Tests

    @Test("Get static pad", .tags(.pads))
    func getStaticPad() throws {
        let queue = try Element.make(factory: "queue")

        let sinkPad = queue.staticPad("sink")
        #expect(sinkPad != nil)

        let srcPad = queue.staticPad("src")
        #expect(srcPad != nil)

        let invalidPad = queue.staticPad("nonexistent")
        #expect(invalidPad == nil)
    }

    @Test("Link elements", .tags(.pads))
    func linkElements() throws {
        let src = try Element.make(factory: "videotestsrc")
        let sink = try Element.make(factory: "fakesink")

        let success = src.link(to: sink)
        #expect(success)
    }

    @Test("Add element to pipeline and sync state", .tags(.pads))
    func addToPipeline() throws {
        let pipeline = try Pipeline("videotestsrc ! fakesink")

        let queue = try Element.make(factory: "queue", name: "testqueue")
        let added = pipeline.add(queue)
        #expect(added)

        // Find it by name
        let found = pipeline.element(named: "testqueue")
        #expect(found != nil)
    }

    // MARK: - Ownership Tests

    @Test("Factory element remains in pipeline after wrapper drop", .tags(.ownership))
    func factoryElementAddThenWrapperDropWhilePipelineAlive() throws {
        let pipeline = try Self.makeOwnershipPipeline()
        let name = "ownership_add_drop"

        try Self.withFatalGStreamerCriticalTrap {
            var element: Element? = try Element.make(factory: "queue", name: name)
            #expect(pipeline.add(try #require(element)))

            element = nil

            let found = try #require(pipeline.element(named: name))
            #expect(found.name == name)
        }
    }

    @Test("Failed duplicate add keeps pipeline-owned element alive", .tags(.ownership))
    func duplicateAddFailureKeepsPipelineOwnership() throws {
        let pipeline = try Self.makeOwnershipPipeline()
        let name = "ownership_duplicate_add"

        try Self.withFatalGStreamerCriticalTrap {
            var element: Element? = try Element.make(factory: "queue", name: name)
            #expect(pipeline.add(try #require(element)))
            #expect(!pipeline.add(try #require(element)))

            element = nil

            let found = try #require(pipeline.element(named: name))
            #expect(found.name == name)
        }
    }

    @Test("Unadded factory element wrapper drops cleanly", .tags(.ownership))
    func factoryElementNeverAddedWrapperDrop() throws {
        let name = "ownership_never_added"

        try Self.withFatalGStreamerCriticalTrap {
            var element: Element? = try Element.make(factory: "queue", name: name)
            #expect((try #require(element)).name == name)

            element = nil
        }
    }

    @Test("Removed element stays absent after wrapper drop", .tags(.ownership))
    func addRemoveLookupFailsThenWrapperDrop() throws {
        let pipeline = try Self.makeOwnershipPipeline()
        let name = "ownership_add_remove"

        try Self.withFatalGStreamerCriticalTrap {
            var element: Element? = try Element.make(factory: "queue", name: name)
            #expect(pipeline.add(try #require(element)))
            #expect(pipeline.remove(try #require(element)))
            #expect(pipeline.element(named: name) == nil)

            element = nil
        }
    }

    @Test("Repeated lookups create independent wrappers for pipeline-owned element", .tags(.ownership))
    func repeatedLookupWrappersDropIndependently() throws {
        let name = "ownership_lookup_queue"
        let pipeline = try Pipeline("queue name=\(name) ! fakesink name=ownership_lookup_sink")

        try Self.withFatalGStreamerCriticalTrap {
            var firstLookup = pipeline.element(named: name)
            var secondLookup = pipeline.element(named: name)
            let underlyingAddress: UInt

            do {
                let first = try #require(firstLookup)
                let second = try #require(secondLookup)
                #expect(first !== second)
                underlyingAddress = UInt(bitPattern: first.element)
                #expect(UInt(bitPattern: second.element) == underlyingAddress)
            }

            firstLookup = nil

            var afterFirstDrop = pipeline.element(named: name)
            #expect(UInt(bitPattern: (try #require(afterFirstDrop)).element) == underlyingAddress)

            afterFirstDrop = nil
            secondLookup = nil

            let afterBothDrops = try #require(pipeline.element(named: name))
            #expect(UInt(bitPattern: afterBothDrops.element) == underlyingAddress)
        }
    }

    @Test("Request pad from tee", .tags(.pads))
    func requestPadFromTee() throws {
        let tee = try Element.make(factory: "tee")

        let pad1 = tee.requestPad("src_%u")
        #expect(pad1 != nil)

        let pad2 = tee.requestPad("src_%u")
        #expect(pad2 != nil)

        // Pads should be different
        #expect(pad1!.pad != pad2!.pad)

        // Release pads
        if let p1 = pad1 { tee.releasePad(p1) }
        if let p2 = pad2 { tee.releasePad(p2) }
    }

    // MARK: - Property Tests

    @Test("Boolean property round-trip", .tags(.properties), arguments: [true, false])
    func boolProperty(value: Bool) throws {
        let src = try Element.make(factory: "videotestsrc")
        src.set("is-live", value)
        #expect(src.getBool("is-live") == value)
    }

    @Test("Integer property round-trip", .tags(.properties), arguments: [0, 1, 2, 5, 10])
    func intProperty(pattern: Int) throws {
        let src = try Element.make(factory: "videotestsrc")
        src.set("pattern", pattern)
        #expect(src.getInt("pattern") == pattern)
    }

    @Test("String property round-trip", .tags(.properties), arguments: [
        "/tmp/test.mp4",
        "/var/log/output.mkv",
        "/home/user/video.avi",
    ])
    func stringProperty(location: String) throws {
        let sink = try Element.make(factory: "filesink")
        sink.set("location", location)
        #expect(sink.getString("location") == location)
    }

    @Test("Double property round-trip", .tags(.properties), arguments: [0.0, 0.5, 1.0, 1.5, 2.0])
    func doubleProperty(value: Double) throws {
        let volume = try Element.make(factory: "volume")
        volume.set("volume", value)
        let result = volume.getDouble("volume")
        #expect(abs(result - value) < 0.001)
    }
}
