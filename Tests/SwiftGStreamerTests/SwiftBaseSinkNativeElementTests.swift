import Foundation
import Synchronization
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Swift BaseSink Native Element Tests", .serialized, .timeLimit(.minutes(1)))
struct SwiftBaseSinkNativeElementTests {

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Swift sink can be registered and used from a pipeline string")
    func swiftSinkCanBeRegisteredAndUsedFromPipelineString() async throws {
        // Given a Swift sink element has valid metadata and video sink caps
        let factoryName = "swiftbasesink_happy_path"
        let recorder = SinkRecorder()
        let element = Self.makeElement(
            factoryName: factoryName,
            typeName: "SwiftGstTestHappyPathSink",
            makeInstance: { CountingSink(recorder: recorder) }
        )

        // When the user registers the element as an in-process factory
        try GStreamer.register(element)

        // Then a pipeline string can create that factory by name
        #expect(Self.elementFactoryExists(factoryName))

        // And a finite video test pipeline reaches end-of-stream
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=3 ! video/x-raw,format=RGB,width=2,height=2,framerate=1/1 ! \(factoryName)"
        )

        // And the Swift sink renders each incoming buffer
        #expect(recorder.snapshot().renderCount == 3)
    }

    @Test("Generated type names are deterministic and valid")
    func generatedTypeNamesAreDeterministicAndValid() throws {
        // Given a Swift sink element omits its GType name
        let factoryName = "swift-native_sink-01"

        // When the user registers the element with a factory name containing safe punctuation
        let sanitized = NativeElementTypeName.sanitizedFactoryNameComponent(factoryName)
        let hash = NativeElementTypeName.fnv1a64Hex(factoryName)
        let generated = NativeElementTypeName.generatedBaseSinkTypeName(factoryName: factoryName)

        // Then the generated type name uses the sanitized factory name
        #expect(sanitized == "swift_native_sink_01")
        #expect(generated.contains("_swift_native_sink_01_"))

        // And the generated type name includes the FNV-1a 64-bit hash of the original factory name
        #expect(NativeElementTypeName.fnv1a64Hex("") == "cbf29ce484222325")
        #expect(NativeElementTypeName.fnv1a64Hex("a") == "af63dc4c8601ec8c")
        #expect(NativeElementTypeName.fnv1a64Hex("hello") == "a430d84680aabd0b")
        #expect(hash == "755cb400232a39be")
        #expect(generated == "SwiftGstNativeBaseSink_swift_native_sink_01_755cb400232a39be")

        // And the generated type name is valid for dynamic GType registration
        #expect(NativeElementTypeName.isValidDynamicGTypeName(generated))
        #expect(!NativeElementTypeName.isValidDynamicGTypeName(""))
        #expect(!NativeElementTypeName.isValidDynamicGTypeName("SwiftGstNativeBaseSink_bad-name"))
    }

    @Test("Invalid registration input fails before C registration")
    func invalidRegistrationInputFailsBeforeCRegistration() throws {
        // Given a Swift sink element has invalid caller-supplied registration input
        try Self.expectInvalidRegistration(
            factoryName: "",
            expectedParameter: "factoryName",
            registeredFactoryName: nil
        )
        try Self.expectInvalidRegistration(
            factoryName: "-swiftbasesink-invalid-start",
            expectedParameter: "factoryName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink invalid character",
            expectedParameter: "factoryName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink_invalid_empty_type",
            typeName: "",
            expectedParameter: "typeName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink_invalid_type_chars",
            typeName: "SwiftGstInvalid-Type",
            expectedParameter: "typeName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink_invalid_klass",
            metadata: Self.metadata(klass: " "),
            expectedParameter: "metadata.klass"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink_invalid_long_name",
            metadata: Self.metadata(longName: " "),
            expectedParameter: "metadata.longName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink_invalid_description",
            metadata: Self.metadata(description: " "),
            expectedParameter: "metadata.description"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasesink_invalid_author",
            metadata: Self.metadata(author: " "),
            expectedParameter: "metadata.author"
        )

        // When the user registers malformed or empty caps
        for scenario in [
            (factoryName: "swiftbasesink_invalid_caps", typeName: "SwiftGstTestInvalidCapsSink", sinkCaps: "video/x-raw,format=(string"),
            (factoryName: "swiftbasesink_empty_caps", typeName: "SwiftGstTestEmptyCapsSink", sinkCaps: "EMPTY"),
        ] {
            let invalidCapsElement = Self.makeElement(
                factoryName: scenario.factoryName,
                typeName: scenario.typeName,
                sinkCaps: scenario.sinkCaps,
                makeInstance: { CountingSink(recorder: SinkRecorder()) }
            )
            let capture = NativeElementRegistrationTestHooks.captureBaseSinkCRegistrationAttempts {
                try GStreamer.register(invalidCapsElement)
            }

            // Then registration throws a typed invalid argument error
            let error = try #require(capture.error)
            Self.expectInvalidArgument(error, parameter: "sinkCaps")

            // And no process-local factory is registered for that input
            #expect(!Self.elementFactoryExists(scenario.factoryName))

            // And the C registration bridge is not called for invalid sink caps
            #expect(capture.attemptCount == 0)
        }
    }

    @Test("Duplicate factory and type names fail diagnostically")
    func duplicateFactoryAndTypeNamesFailDiagnostically() async throws {
        // Given a Swift sink element has already been registered in the process
        let factoryName = "swiftbasesink_duplicate_active"
        let typeName = "SwiftGstTestDuplicateActiveSink"
        let recorder = SinkRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: typeName,
                makeInstance: { CountingSink(recorder: recorder) }
            )
        )

        // When the user registers another sink with the same factory or GType name
        let duplicateFactoryError = try #require(Self.captureError {
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestDuplicateFactorySink",
                    makeInstance: { CountingSink(recorder: SinkRecorder()) }
                )
            )
        })
        let duplicateTypeFactoryName = "swiftbasesink_duplicate_type"
        let duplicateTypeError = try #require(Self.captureError {
            try GStreamer.register(
                Self.makeElement(
                    factoryName: duplicateTypeFactoryName,
                    typeName: typeName,
                    makeInstance: { CountingSink(recorder: SinkRecorder()) }
                )
            )
        })

        // Then registration throws an initialization failure diagnostic
        Self.expectInitializationFailed(duplicateFactoryError)
        Self.expectInitializationFailed(duplicateTypeError)
        #expect(!Self.elementFactoryExists(duplicateTypeFactoryName))

        // And the existing registration remains the active factory
        try await Self.runFiniteVideoPipeline("videotestsrc num-buffers=1 ! \(factoryName)")
        #expect(recorder.snapshot().renderCount == 1)
    }

    @Test("Class contexts follow registration ownership rules")
    func classContextsFollowRegistrationOwnershipRules() throws {
        // Given the native sink registration bridge receives a Swift class context
        let result = Self.classContextOwnershipProbe(
            successFactoryName: "swiftbasesink_c_ownership_success",
            successTypeName: "SwiftGstTestCOwnershipSuccessSink",
            duplicateFactoryTypeName: "SwiftGstTestCOwnershipDuplicateFactorySink",
            duplicateTypeFactoryName: "swiftbasesink_c_ownership_duplicate_type"
        )

        // When registration succeeds or fails after retaining that context
        #expect(result.success_registration_succeeded != 0)
        #expect(result.duplicate_factory_registration_failed != 0)
        #expect(result.duplicate_type_registration_failed != 0)

        // Then the bridge retains the class context before storing it
        #expect(result.success_context.retain_count == 1)

        // And failed registration releases the retained class context exactly once
        #expect(result.duplicate_factory_context.retain_count == 1)
        #expect(result.duplicate_factory_context.release_count == 1)
        #expect(result.duplicate_type_context.retain_count == 1)
        #expect(result.duplicate_type_context.release_count == 1)

        // And successful registration keeps the retained class context for process lifetime
        #expect(result.success_context.release_count == 0)
    }

    @Test("Lifecycle callbacks use one Swift instance per GObject instance")
    func lifecycleCallbacksUseOneSwiftInstancePerGObjectInstance() async throws {
        // Given a registered Swift sink creates a stateful Swift instance
        let factoryName = "swiftbasesink_lifecycle"
        let recorder = LifecycleRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestLifecycleSink",
                makeInstance: { LifecycleSink(recorder: recorder) }
            )
        )

        // When a finite pipeline starts, negotiates caps, renders buffers, and stops
        do {
            let pipeline = try Pipeline(
                "videotestsrc num-buffers=2 ! video/x-raw,format=RGB,width=2,height=2,framerate=1/1 ! \(factoryName)"
            )
            try pipeline.play()
            defer { pipeline.stop() }
            try await Self.withTimeout(.seconds(2)) {
                try await pipeline.bus.waitForEOSOrError()
            }
        }

        _ = await Self.waitUntil(timeout: .seconds(1)) {
            recorder.snapshot().destroyCount == 1
        }
        let snapshot = recorder.snapshot()

        // Then start is called for that instance
        #expect(snapshot.instanceCreateCount == 1)
        #expect(snapshot.startCount == 1)

        // And setCaps receives storable owned caps
        #expect(snapshot.setCapsCount == 1)
        let negotiatedCaps = try #require(snapshot.storedCapsDescriptions.first)
        #expect(negotiatedCaps.contains("video/x-raw"))
        #expect(negotiatedCaps.contains("format=(string)RGB"))
        #expect(negotiatedCaps.contains("width=(int)2"))
        #expect(negotiatedCaps.contains("height=(int)2"))
        #expect(negotiatedCaps.contains("framerate=(fraction)1/1"))

        // And render is called once for each incoming buffer
        #expect(snapshot.renderCount == 2)

        // And stop is called when the sink stops
        #expect(snapshot.stopCount == 1)

        // And the Swift instance context is destroyed exactly once
        #expect(snapshot.destroyCount == 1)
    }

    @Test("Swift callback failures do not cross C")
    func swiftCallbackFailuresDoNotCrossC() async throws {
        try Self.expectFlowReturnMappings()

        for failureCase in CallbackFailureCase.allCases {
            // Given a registered Swift sink callback reports failure or throws
            let recorder = FailureRecorder()
            let factoryName = "swiftbasesink_failure_\(failureCase.factorySuffix)"
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestFailure\(failureCase.typeSuffix)Sink",
                    makeInstance: { FailingSink(failureCase: failureCase, recorder: recorder) }
                )
            )

            // When a pipeline drives that failing callback
            let error = try #require(await Self.capturePipelineFailure(factoryName: factoryName))

            // Then GStreamer receives the matching BaseSink failure return value
            Self.expectGStreamerPipelineFailure(error, context: failureCase.rawValue)

            // And the pipeline reports failure through state change or bus error
            #expect(recorder.snapshot().callbackCount(for: failureCase) > 0)

            // And no Swift error escapes across the C callback boundary
            #expect(!(error is CallbackFailureError))
        }
    }

    @Test("Borrowed buffers can be inspected or retained safely")
    func borrowedBuffersCanBeInspectedOrRetainedSafely() async throws {
        // Given a Swift sink receives a borrowed incoming buffer
        let factoryName = "swiftbasesink_borrowed_buffer"
        let recorder = BorrowedBufferRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestBorrowedBufferSink",
                makeInstance: { BorrowedBufferSink(recorder: recorder) }
            )
        )

        // When the sink reads bytes, timestamps, and duration inside the render callback
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=1 ! video/x-raw,format=RGB,width=2,height=2,framerate=1/1 ! \(factoryName)"
        )
        let snapshot = recorder.snapshot()
        let observation = try #require(snapshot.observation)

        // Then read access is bounded to the closure scope
        #expect(snapshot.renderCount == 1)
        #expect(observation.size > 0)
        #expect(observation.byteCount == observation.size)
        #expect(observation.pts != nil)
        #expect(observation.duration != nil)

        // And a retained reference can outlive the render callback
        #expect(observation.retainedSize == observation.size)
        #expect(observation.retainedPrefix == observation.prefix)

        // And a deep copy owns independent buffer storage
        #expect(observation.deepCopySize == observation.size)
        #expect(observation.deepCopyPrefix == observation.prefix)
    }

    @Test("Missing internal instance contexts fail deterministically")
    func missingInternalInstanceContextsFailDeterministically() async throws {
        // Given the native sink bridge cannot create a Swift instance context
        let result = Self.missingInstanceProbe(
            factoryName: "swiftbasesink_missing_instance",
            typeName: "SwiftGstTestMissingInstanceSink"
        )

        // When GStreamer starts, renders, and stops the sink
        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // Then start fails without calling Swift instance callbacks
        #expect(result.start_returned_false != 0)
        #expect(result.callback_counts.start_count == 0)

        // And render returns a GStreamer flow error
        #expect(result.render_returned_flow_error != 0)
        #expect(result.callback_counts.render_count == 0)

        // And stop succeeds without calling Swift instance callbacks
        #expect(result.stop_returned_true != 0)
        #expect(result.callback_counts.stop_count == 0)
        #expect(result.callback_counts.create_count == 0)
        #expect(result.callback_counts.destroy_count == 0)
    }

    @Test("Phase 2 transform API coexists with BaseSink API")
    func phase2TransformAPICoexistsWithBaseSinkAPI() throws {
        // Given Phase 2 exposes native transform public symbols
        _ = SwiftBaseTransformPassthroughOptions.self
        _ = SwiftBaseTransformElement.self
        _ = SwiftBaseTransformInstance.self
        _ = MutableBorrowedBuffer.self

        let defaults = SwiftBaseTransformPassthroughOptions.default
        #expect(defaults.passthroughOnSameCaps)
        #expect(!defaults.transformInPlaceOnPassthrough)

        let root = try Self.packageRoot()
        let swiftSources = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let baseShimHeader = try Self.contents(
            of: root.appendingPathComponent("Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        )

        // Then the existing BaseSink API and ABI remain available
        #expect(swiftSources.contains("public protocol SwiftBaseSinkInstance"))
        #expect(swiftSources.contains("public struct SwiftBaseSinkElement"))
        #expect(baseShimHeader.contains("SwiftGstBaseSinkInfo"))
        #expect(baseShimHeader.contains("SwiftGstBaseSinkCallbacks"))
        #expect(baseShimHeader.contains("swift_gst_register_base_sink"))

        // And BaseTransform construction and registration are available
        #expect(swiftSources.contains("public struct SwiftBaseTransformPassthroughOptions"))
        #expect(swiftSources.contains("public protocol SwiftBaseTransformInstance"))
        #expect(swiftSources.contains("public struct MutableBorrowedBuffer"))
        #expect(swiftSources.contains("public struct SwiftBaseTransformElement"))
        #expect(Self.containsRegex(
            #"public\s+static\s+func\s+inPlace\s*\("#,
            in: swiftSources
        ))
        #expect(Self.containsRegex(
            #"public\s+static\s+func\s+register\s*\(\s*_\s+element:\s*SwiftBaseTransformElement\s*\)\s+throws"#,
            in: swiftSources
        ))
        #expect(!swiftSources.contains("Swift-backed BaseTransform is planned for Phase 2"))

        // And the C shim exports the BaseTransform registration and callback ABI
        let requiredCABI = [
            "gstbasetransform",
            "GstBaseTransform",
            "SwiftGstBaseTransform",
            "swift_gst_register_base_transform",
            "BaseTransformCallbacks",
            "BaseTransformInfo",
            "transform_ip",
        ]
        for required in requiredCABI {
            #expect(baseShimHeader.contains(required), "Missing Phase 2 C ABI in Base shim: \(required)")
        }
    }

    private static func makeElement(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = "video/x-raw",
        makeInstance: @escaping @Sendable () -> any SwiftBaseSinkInstance
    ) -> SwiftBaseSinkElement {
        SwiftBaseSinkElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.metadata(),
            sinkCaps: sinkCaps,
            makeInstance: makeInstance
        )
    }

    private static func metadata(
        klass: String = "Sink/Video",
        longName: String = "Swift test BaseSink",
        description: String = "Swift test BaseSink element",
        author: String = "gstreamer-swift-tests",
        rank: ElementRank = .none
    ) -> NativeElementMetadata {
        NativeElementMetadata(
            klass: klass,
            longName: longName,
            description: description,
            author: author,
            rank: rank
        )
    }

    private static func expectInvalidRegistration(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = "video/x-raw",
        expectedParameter: String,
        registeredFactoryName: String? = nil
    ) throws {
        let element = Self.makeElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata,
            sinkCaps: sinkCaps,
            makeInstance: { CountingSink(recorder: SinkRecorder()) }
        )

        let error = try #require(Self.captureError {
            try GStreamer.register(element)
        })
        Self.expectInvalidArgument(error, parameter: expectedParameter)

        if let registeredFactoryName = registeredFactoryName ?? (factoryName.isEmpty ? nil : factoryName) {
            #expect(!Self.elementFactoryExists(registeredFactoryName))
        }
    }

    private static func runFiniteVideoPipeline(_ description: String) async throws {
        let pipeline = try Pipeline(description)
        try pipeline.play()
        defer { pipeline.stop() }
        try await Self.withTimeout(.seconds(2)) {
            try await pipeline.bus.waitForEOSOrError()
        }
    }

    private static func capturePipelineFailure(factoryName: String) async throws -> Error? {
        let pipeline = try Pipeline(
            "videotestsrc num-buffers=1 ! video/x-raw,format=RGB,width=2,height=2,framerate=1/1 ! \(factoryName)"
        )

        do {
            try pipeline.play()
        } catch {
            pipeline.stop()
            return error
        }

        do {
            try await Self.withTimeout(.seconds(2)) {
                try await pipeline.bus.waitForEOSOrError()
            }
            pipeline.stop()
            return nil
        } catch {
            pipeline.stop()
            return error
        }
    }

    private static func expectInvalidArgument(_ error: Error, parameter expectedParameter: String) {
        guard case GStreamerError.invalidArgument(let parameter, let reason) = error else {
            Issue.record("Expected invalidArgument(\(expectedParameter)), got \(error)")
            return
        }

        #expect(parameter == expectedParameter)
        #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func expectInitializationFailed(_ error: Error) {
        guard case GStreamerError.initializationFailed(let reason) = error else {
            Issue.record("Expected initializationFailed, got \(error)")
            return
        }

        #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func expectGStreamerPipelineFailure(_ error: Error, context: String) {
        switch error {
        case GStreamerError.stateChangeFailed:
            break
        case GStreamerError.busError:
            break
        default:
            Issue.record("Expected GStreamer pipeline failure for \(context), got \(error)")
        }
    }

    private static func expectFlowReturnMappings() throws {
        #expect(FlowReturn.ok.gstFlowReturn.rawValue == 0)
        #expect(FlowReturn.error.gstFlowReturn.rawValue == -5)
        #expect(FlowReturn.notNegotiated.gstFlowReturn.rawValue == -4)
        #expect(FlowReturn.flushing.gstFlowReturn.rawValue == -2)
        #expect(FlowReturn.eos.gstFlowReturn.rawValue == -3)
        #expect(FlowReturn.dropped.gstFlowReturn.rawValue == 100)
        #expect(FlowReturn.custom(73).gstFlowReturn.rawValue == 73)
        #expect(FlowReturn.custom(-123).gstFlowReturn.rawValue == -123)
    }

    private static func captureError(_ body: () throws -> Void) -> Error? {
        do {
            try body()
            return nil
        } catch {
            return error
        }
    }

    private static func elementFactoryExists(_ name: String) -> Bool {
        name.withCString { swift_gst_test_element_factory_exists($0) != 0 }
    }

    private static func classContextOwnershipProbe(
        successFactoryName: String,
        successTypeName: String,
        duplicateFactoryTypeName: String,
        duplicateTypeFactoryName: String
    ) -> SwiftGstTestBaseSinkOwnershipProbeResult {
        successFactoryName.withCString { successFactoryName in
            successTypeName.withCString { successTypeName in
                duplicateFactoryTypeName.withCString { duplicateFactoryTypeName in
                    duplicateTypeFactoryName.withCString { duplicateTypeFactoryName in
                        swift_gst_test_base_sink_class_context_ownership_probe(
                            successFactoryName,
                            successTypeName,
                            duplicateFactoryTypeName,
                            duplicateTypeFactoryName
                        )
                    }
                }
            }
        }
    }

    private static func missingInstanceProbe(
        factoryName: String,
        typeName: String
    ) -> SwiftGstTestBaseSinkMissingInstanceProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_sink_missing_instance_probe(factoryName, typeName)
            }
        }
    }

    fileprivate static func bytes(in buffer: Buffer, limit: Int) -> [UInt8] {
        buffer.bytes.withUnsafeBytes { bytes in
            Array(bytes.prefix(limit))
        }
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
                throw SwiftBaseSinkNativeElementTimeoutError(timeout: timeout)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw SwiftBaseSinkNativeElementTimeoutError(timeout: timeout)
            }
            return result
        }
    }

    private static func waitUntil(
        timeout: Duration,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        return condition()
    }

    private static func packageRoot(filePath: String = #filePath) throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while true {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw StaticNativeElementTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private static func combinedSwiftSources(in directory: URL) throws -> String {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true && file.pathExtension == "swift" {
                files.append(file)
            }
        }

        return try files.sorted { $0.path < $1.path }
            .map { try Self.contents(of: $0) }
            .joined(separator: "\n")
    }

    private static func containsRegex(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}

private final class SinkRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var renderCount = 0
    }

    func recordRender() {
        state.withLock { $0.renderCount += 1 }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class CountingSink: SwiftBaseSinkInstance {
    private let recorder: SinkRecorder

    init(recorder: SinkRecorder) {
        self.recorder = recorder
    }

    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        recorder.recordRender()
        return .ok
    }
}

private final class LifecycleRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var instanceCreateCount = 0
        var destroyCount = 0
        var startCount = 0
        var stopCount = 0
        var setCapsCount = 0
        var renderCount = 0
        var storedCapsDescriptions: [String] = []
    }

    func recordInstanceCreated() {
        state.withLock { $0.instanceCreateCount += 1 }
    }

    func recordDestroyed() {
        state.withLock { $0.destroyCount += 1 }
    }

    func recordStart() {
        state.withLock { $0.startCount += 1 }
    }

    func recordStop() {
        state.withLock { $0.stopCount += 1 }
    }

    func recordSetCaps(_ caps: Caps) {
        state.withLock {
            $0.setCapsCount += 1
            $0.storedCapsDescriptions.append(caps.description)
        }
    }

    func recordRender() {
        state.withLock { $0.renderCount += 1 }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class LifecycleSink: SwiftBaseSinkInstance {
    private let recorder: LifecycleRecorder

    init(recorder: LifecycleRecorder) {
        self.recorder = recorder
        recorder.recordInstanceCreated()
    }

    deinit {
        recorder.recordDestroyed()
    }

    func start() throws {
        recorder.recordStart()
    }

    func stop() {
        recorder.recordStop()
    }

    func setCaps(_ caps: Caps) throws -> Bool {
        recorder.recordSetCaps(caps)
        return true
    }

    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        recorder.recordRender()
        return .ok
    }
}

private enum CallbackFailureCase: String, CaseIterable, Sendable {
    case startThrows
    case setCapsReturnsFalse
    case setCapsThrows
    case renderThrows
    case renderReturnsError

    var factorySuffix: String {
        switch self {
        case .startThrows: "start_throws"
        case .setCapsReturnsFalse: "setcaps_false"
        case .setCapsThrows: "setcaps_throws"
        case .renderThrows: "render_throws"
        case .renderReturnsError: "render_error"
        }
    }

    var typeSuffix: String {
        switch self {
        case .startThrows: "StartThrows"
        case .setCapsReturnsFalse: "SetCapsFalse"
        case .setCapsThrows: "SetCapsThrows"
        case .renderThrows: "RenderThrows"
        case .renderReturnsError: "RenderError"
        }
    }
}

private struct CallbackFailureError: Error, Sendable {
    let failureCase: CallbackFailureCase
}

private final class FailureRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var startCount = 0
        var setCapsCount = 0
        var renderCount = 0

        func callbackCount(for failureCase: CallbackFailureCase) -> Int {
            switch failureCase {
            case .startThrows:
                startCount
            case .setCapsReturnsFalse, .setCapsThrows:
                setCapsCount
            case .renderThrows, .renderReturnsError:
                renderCount
            }
        }
    }

    func recordStart() {
        state.withLock { $0.startCount += 1 }
    }

    func recordSetCaps() {
        state.withLock { $0.setCapsCount += 1 }
    }

    func recordRender() {
        state.withLock { $0.renderCount += 1 }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class FailingSink: SwiftBaseSinkInstance {
    private let failureCase: CallbackFailureCase
    private let recorder: FailureRecorder

    init(failureCase: CallbackFailureCase, recorder: FailureRecorder) {
        self.failureCase = failureCase
        self.recorder = recorder
    }

    func start() throws {
        recorder.recordStart()
        if failureCase == .startThrows {
            throw CallbackFailureError(failureCase: failureCase)
        }
    }

    func setCaps(_ caps: Caps) throws -> Bool {
        recorder.recordSetCaps()
        switch failureCase {
        case .setCapsReturnsFalse:
            return false
        case .setCapsThrows:
            throw CallbackFailureError(failureCase: failureCase)
        default:
            return true
        }
    }

    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        recorder.recordRender()
        switch failureCase {
        case .renderThrows:
            throw CallbackFailureError(failureCase: failureCase)
        case .renderReturnsError:
            return .error
        default:
            return .ok
        }
    }
}

private final class BorrowedBufferRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var renderCount = 0
        var observation: BorrowedBufferObservation?
    }

    func record(_ observation: BorrowedBufferObservation) {
        state.withLock {
            $0.renderCount += 1
            $0.observation = observation
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private struct BorrowedBufferObservation: Sendable {
    var size: Int
    var byteCount: Int
    var pts: UInt64?
    var duration: UInt64?
    var prefix: [UInt8]
    var retainedSize: Int
    var retainedPrefix: [UInt8]
    var deepCopySize: Int
    var deepCopyPrefix: [UInt8]
}

private final class BorrowedBufferSink: SwiftBaseSinkInstance {
    private let recorder: BorrowedBufferRecorder

    init(recorder: BorrowedBufferRecorder) {
        self.recorder = recorder
    }

    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        let size = buffer.size
        let byteAccess = try buffer.withUnsafeBytes { bytes in
            (
                byteCount: bytes.count,
                prefix: Array(bytes.prefix(min(bytes.count, 16)))
            )
        }
        let retained = buffer.retainedReference()
        let copied = try buffer.deepCopy()
        let observation = BorrowedBufferObservation(
            size: size,
            byteCount: byteAccess.byteCount,
            pts: buffer.pts,
            duration: buffer.duration,
            prefix: byteAccess.prefix,
            retainedSize: retained.size,
            retainedPrefix: SwiftBaseSinkNativeElementTests.bytes(in: retained, limit: byteAccess.prefix.count),
            deepCopySize: copied.size,
            deepCopyPrefix: SwiftBaseSinkNativeElementTests.bytes(in: copied, limit: byteAccess.prefix.count)
        )
        recorder.record(observation)
        return .ok
    }
}

private struct SwiftBaseSinkNativeElementTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}

private enum StaticNativeElementTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not find Package.swift while walking up from \(filePath)"
        }
    }
}
