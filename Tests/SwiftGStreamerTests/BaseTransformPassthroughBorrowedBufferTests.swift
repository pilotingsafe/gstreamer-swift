import Foundation
import Synchronization
import Testing
import CGStreamerShim
import CGStreamerTestSupport
@testable import GStreamer

@Suite("BaseTransform passthrough borrowed buffers", .serialized, .timeLimit(.minutes(1)))
struct BaseTransformPassthroughBorrowedBufferTests {
    init() throws {
        try GStreamer.initialize()
    }

    @Test("Non-writable passthrough buffers can be inspected")
    func nonWritablePassthroughBuffersCanBeInspected() throws {
        // Given a Swift-backed in-place transform is configured to inspect buffers during passthrough
        let factoryName = "swiftbasetransform_passthrough_readonly_inspection"
        let observer = PassthroughReadObserver()
        try GStreamer.register(
            Self.makePassthroughElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestPassthroughReadOnlyInspectionTransform",
                makeInstance: { PassthroughReadTransform(observer: observer) }
            )
        )
        let expectedBytes: [UInt8] = [0, 1, 2, 3, 254, 255, 42, 43]

        // And GStreamer provides a buffer that is not writable
        let result = try expectedBytes.withUnsafeBufferPointer { pointer in
            let baseAddress = try #require(pointer.baseAddress)
            return swift_gst_test_base_transform_invoke_non_writable_transform_ip(
                factoryName,
                baseAddress,
                gsize(expectedBytes.count)
            )
        }

        // When the transform callback reads the borrowed buffer
        #expect(result.element_created != 0)
        #expect(result.transform_ip_on_passthrough != 0)
        #expect(result.non_writable_buffer_was_not_writable != 0)

        // Then the callback can observe the buffer bytes
        #expect(observer.snapshot().observedBytes == expectedBytes)
        #expect(observer.snapshot().callbackCount == 1)

        // And the buffer continues downstream successfully
        #expect(result.transform_ip_returned_ok != 0)
    }

    @Test("Non-writable passthrough buffers are not implicitly mutable")
    func nonWritablePassthroughBuffersAreNotImplicitlyMutable() throws {
        // Given a Swift-backed in-place transform is configured to inspect buffers during passthrough
        let factoryName = "swiftbasetransform_passthrough_write_failure"
        let observer = PassthroughWriteFailureObserver()
        try GStreamer.register(
            Self.makePassthroughElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestPassthroughWriteFailureTransform",
                makeInstance: { PassthroughWriteFailureTransform(observer: observer) }
            )
        )
        let expectedBytes: [UInt8] = [10, 20, 30, 40]

        // And GStreamer provides a buffer that is not writable

        // When the transform callback attempts mutable byte access
        let result = try expectedBytes.withUnsafeBufferPointer { pointer in
            let baseAddress = try #require(pointer.baseAddress)
            return swift_gst_test_base_transform_invoke_non_writable_transform_ip(
                factoryName,
                baseAddress,
                gsize(expectedBytes.count)
            )
        }

        switch observer.snapshot().observedError {
        case .bufferMapFailed:
            break
        case .some(let error):
            Issue.record("Expected bufferMapFailed, got \(error)")
        case nil:
            Issue.record("Expected passthrough transform to record a write-map failure")
        }

        // Then mutable access fails with a buffer map error
        #expect(result.element_created != 0)
        #expect(result.transform_ip_on_passthrough != 0)
        #expect(result.non_writable_buffer_was_not_writable != 0)
        #expect(observer.snapshot().callbackCount == 1)
        #expect(!observer.snapshot().mutableBodyWasCalled)

        // And the transform reports a flow error instead of silently mutating the buffer
        #expect(result.transform_ip_returned_flow_error != 0)
    }

    @Test("Non-writable borrowed buffer write access fails directly")
    func nonWritableBorrowedBufferWriteAccessFailsDirectly() throws {
        let expectedBytes: [UInt8] = [10, 20, 30, 40]
        let buffer = try Buffer(data: expectedBytes)
        _ = swift_gst_buffer_ref(buffer.buffer)
        defer { swift_gst_buffer_unref(buffer.buffer) }
        let borrowed = MutableBorrowedBuffer(buffer: buffer.buffer)

        var mutableBodyWasCalled = false
        do {
            try borrowed.withUnsafeMutableBytes { bytes in
                mutableBodyWasCalled = true
                if !bytes.isEmpty {
                    bytes[0] = 99
                }
            }
            Issue.record("Expected bufferMapFailed, but mutable access succeeded")
        } catch GStreamerError.bufferMapFailed {
        } catch {
            Issue.record("Expected bufferMapFailed, got \(error)")
        }

        #expect(Self.bytes(in: buffer) == expectedBytes)
        #expect(!mutableBodyWasCalled)
    }

    @Test("Low-level transform dispatch accepts non-writable buffers")
    func lowLevelTransformDispatchAcceptsNonWritableBuffers() {
        // Given the native transform bridge receives a non-writable buffer
        let result = Self.bufferRejectionProbe(
            factoryName: "swiftbasetransform_passthrough_nonwritable_dispatch",
            typeName: "SwiftGstTestPassthroughNonWritableDispatchTransform"
        )

        // When the registered transform callback only inspects or ignores the buffer
        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)
        #expect(result.non_writable_buffer_was_not_writable != 0)

        // Then the bridge calls the registered callback
        #expect(result.non_writable_buffer_callback_count == 1)
        #expect(result.callback_counts.transform_ip_count == 1)

        // And the callback result is returned to GStreamer
        #expect(result.non_writable_buffer_returned_ok != 0)
    }

    @Test("Invalid buffers are still rejected")
    func invalidBuffersAreStillRejected() {
        // Given the native transform bridge receives no buffer
        let result = Self.bufferRejectionProbe(
            factoryName: "swiftbasetransform_passthrough_nil_rejection",
            typeName: "SwiftGstTestPassthroughNilRejectionTransform"
        )

        // When GStreamer invokes the transform callback
        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // Then the bridge returns a flow error
        #expect(result.nil_buffer_returned_flow_error != 0)

        // And no Swift transform callback is called
        #expect(result.nil_buffer_callback_count == 0)
    }

    @Test("Borrowed buffer API documents read and conditional write access")
    func borrowedBufferAPIDocumentsReadAndConditionalWriteAccess() throws {
        // Given a Swift transform callback receives a borrowed transform buffer
        let source = try Self.contents(of: "Sources/GStreamer/SwiftBaseSinkElement.swift")
        let documentation = try Self.contents(of: "Sources/GStreamer/Documentation.docc/NativeElements.md")

        // When a user reads the public API documentation
        #expect(source.contains("public struct MutableBorrowedBuffer"))
        #expect(Self.containsRegex(#"public\s+func\s+withUnsafeBytes\s*<\s*R\s*>\s*\(\s*_ body:\s*\(UnsafeRawBufferPointer\)\s*throws\s*->\s*R\s*\)\s*throws\s*->\s*R"#, in: source))
        #expect(source.contains("swift_gst_buffer_map_read(buffer"))

        // Then read-only callback-scoped byte access is documented
        #expect(Self.containsAny(["read-only", "read only"], in: source))
        #expect(documentation.contains("withUnsafeBytes(_:)"))
        #expect(Self.containsAny(["read-only", "read only"], in: documentation))

        // And mutable byte access is documented as available only for writable buffers
        #expect(documentation.contains("withUnsafeMutableBytes(_:)"))
        #expect(Self.containsAny(["non-writable", "not writable"], in: source))
        #expect(Self.containsAny(["non-writable", "not writable"], in: documentation))
    }

    private static func bufferRejectionProbe(
        factoryName: String,
        typeName: String
    ) -> SwiftGstTestBaseTransformBufferRejectionProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_transform_buffer_rejection_probe(factoryName, typeName)
            }
        }
    }

    private static func makePassthroughElement(
        factoryName: String,
        typeName: String,
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: NativeElementMetadata(
                klass: "Filter/Swift",
                longName: "Swift passthrough borrowed buffer test transform",
                description: "Tests passthrough borrowed buffer access",
                author: "gstreamer-swift-tests"
            ),
            sinkCaps: "application/octet-stream",
            srcCaps: "application/octet-stream",
            passthroughOptions: SwiftBaseTransformPassthroughOptions(
                passthroughOnSameCaps: true,
                transformInPlaceOnPassthrough: true
            ),
            makeInstance: makeInstance
        )
    }

    private static func bytes(in buffer: Buffer) -> [UInt8] {
        buffer.bytes.withUnsafeBytes { bytes in
            Array(bytes)
        }
    }

    private static func contents(of relativePath: String) throws -> String {
        try String(contentsOf: try Self.packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func packageRoot(filePath: String = #filePath) throws -> URL {
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        while true {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw BaseTransformPassthroughBorrowedBufferTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func containsRegex(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }

    private static func containsAny(_ needles: [String], in source: String) -> Bool {
        let lowercasedSource = source.lowercased()
        return needles.contains { lowercasedSource.contains($0) }
    }
}

private enum BaseTransformPassthroughBorrowedBufferTestError: Error {
    case packageRootNotFound(String)
}

private final class PassthroughReadObserver: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var callbackCount = 0
        var observedBytes: [UInt8] = []
    }

    func record(_ bytes: [UInt8]) {
        state.withLock {
            $0.callbackCount += 1
            $0.observedBytes = bytes
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class PassthroughReadTransform: SwiftBaseTransformInstance {
    private let observer: PassthroughReadObserver

    init(observer: PassthroughReadObserver) {
        self.observer = observer
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        let bytes = try buffer.withUnsafeBytes { Array($0) }
        observer.record(bytes)
        return .ok
    }
}

private final class PassthroughWriteFailureObserver: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var callbackCount = 0
        var mutableBodyWasCalled = false
        var observedError: GStreamerError?
    }

    func record(mutableBodyWasCalled: Bool, error: GStreamerError?) {
        state.withLock {
            $0.callbackCount += 1
            $0.mutableBodyWasCalled = mutableBodyWasCalled
            $0.observedError = error
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class PassthroughWriteFailureTransform: SwiftBaseTransformInstance {
    private let observer: PassthroughWriteFailureObserver

    init(observer: PassthroughWriteFailureObserver) {
        self.observer = observer
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        var mutableBodyWasCalled = false
        do {
            try buffer.withUnsafeMutableBytes { bytes in
                mutableBodyWasCalled = true
                if !bytes.isEmpty {
                    bytes[0] = 99
                }
            }
            observer.record(mutableBodyWasCalled: mutableBodyWasCalled, error: nil)
            return .ok
        } catch let error as GStreamerError {
            observer.record(mutableBodyWasCalled: mutableBodyWasCalled, error: error)
            throw error
        } catch {
            observer.record(mutableBodyWasCalled: mutableBodyWasCalled, error: nil)
            throw error
        }
    }
}
