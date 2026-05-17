import Foundation
import Synchronization
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Swift BaseTransform Native Element Tests", .serialized, .timeLimit(.minutes(1)))
struct SwiftBaseTransformNativeElementTests {
    private static let videoCaps = "video/x-raw,format=RGB,width=2,height=2,framerate=1/1"
    private static let bgraCaps = "video/x-raw,format=BGRA,width=2,height=2,framerate=30/1"

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Swift transform can be registered and used from a pipeline string")
    func swiftTransformCanBeRegisteredAndUsedFromPipelineString() async throws {
        // Given a Swift in-place transform element has valid metadata and matching video caps
        let factoryName = "swiftbasetransform_pipeline_identity"
        let element = Self.makeElement(
            factoryName: factoryName,
            typeName: "SwiftGstTestPipelineIdentityTransform",
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            makeInstance: { CountingTransform(recorder: TransformRecorder()) }
        )

        // When the user registers the transform as an in-process factory
        try GStreamer.register(element)

        // Then a pipeline string can create that transform by factory name
        #expect(Self.elementFactoryExists(factoryName))

        // And a finite video test pipeline reaches end-of-stream
        let frames = try await Self.collectFrames(
            from: "videotestsrc num-buffers=3 ! \(Self.videoCaps) ! \(factoryName) ! appsink name=sink sync=false",
            expectedCount: 3
        )

        // And downstream receives the expected number of frames
        #expect(frames.count == 3)
    }

    @Test("Generated transform type names are deterministic and valid")
    func generatedTransformTypeNamesAreDeterministicAndValid() throws {
        // Given a Swift transform element omits its GType name
        let factoryName = "swift-native_transform-01"
        let element = Self.makeElement(
            factoryName: factoryName,
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            makeInstance: { CountingTransform(recorder: TransformRecorder()) }
        )

        // When the user registers the transform with a factory name containing safe punctuation
        let sanitized = NativeElementTypeName.sanitizedFactoryNameComponent(factoryName)
        let hash = NativeElementTypeName.fnv1a64Hex(factoryName)
        let generated = NativeElementTypeName.generatedBaseTransformTypeName(factoryName: factoryName)
        try GStreamer.register(element)

        // Then the generated type name uses the sanitized factory name
        #expect(sanitized == "swift_native_transform_01")
        #expect(generated.contains("_swift_native_transform_01_"))

        // And the generated type name includes the FNV-1a 64-bit hash of the original factory name
        #expect(NativeElementTypeName.fnv1a64Hex("") == "cbf29ce484222325")
        #expect(NativeElementTypeName.fnv1a64Hex("a") == "af63dc4c8601ec8c")
        #expect(NativeElementTypeName.fnv1a64Hex("hello") == "a430d84680aabd0b")
        #expect(hash == "e6a0a80dfdfa0a19")
        #expect(generated == "SwiftGstNativeBaseTransform_swift_native_transform_01_e6a0a80dfdfa0a19")

        // And the generated type name is valid for dynamic GType registration
        #expect(NativeElementTypeName.isValidDynamicGTypeName(generated))
        #expect(Self.elementFactoryExists(factoryName))
    }

    @Test("Registration preserves transform factory rank metadata")
    func registrationPreservesTransformFactoryRankMetadata() throws {
        // Given one Swift transform element uses default metadata rank
        let defaultFactoryName = "swiftbasetransform_rank_default"
        try GStreamer.register(
            Self.makeElement(
                factoryName: defaultFactoryName,
                typeName: "SwiftGstTestDefaultRankTransform",
                makeInstance: { CountingTransform(recorder: TransformRecorder()) }
            )
        )

        // And another Swift transform element uses custom metadata rank
        let customFactoryName = "swiftbasetransform_rank_custom"
        try GStreamer.register(
            Self.makeElement(
                factoryName: customFactoryName,
                typeName: "SwiftGstTestCustomRankTransform",
                metadata: Self.metadata(rank: .primary),
                makeInstance: { CountingTransform(recorder: TransformRecorder()) }
            )
        )

        // When the user registers both transforms
        let defaultRank = try #require(Self.elementFactoryRank(defaultFactoryName))
        let customRank = try #require(Self.elementFactoryRank(customFactoryName))

        // Then the default-rank transform factory has rank none
        #expect(defaultRank == ElementRank.none.rawValue)

        // And the custom-rank transform factory has the requested rank
        #expect(customRank == ElementRank.primary.rawValue)
    }

    @Test("Invalid transform registration input fails before C registration")
    func invalidTransformRegistrationInputFailsBeforeCRegistration() throws {
        // Given a Swift transform element has invalid caller-supplied registration input
        try Self.expectInvalidRegistration(
            factoryName: "",
            expectedParameter: "factoryName",
            registeredFactoryName: nil
        )
        try Self.expectInvalidRegistration(
            factoryName: "-swiftbasetransform-invalid-start",
            expectedParameter: "factoryName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform invalid character",
            expectedParameter: "factoryName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform_invalid_empty_type",
            typeName: "",
            expectedParameter: "typeName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform_invalid_type_chars",
            typeName: "SwiftGstInvalid-TransformType",
            expectedParameter: "typeName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform_invalid_klass",
            metadata: Self.metadata(klass: " "),
            expectedParameter: "metadata.klass"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform_invalid_long_name",
            metadata: Self.metadata(longName: " "),
            expectedParameter: "metadata.longName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform_invalid_description",
            metadata: Self.metadata(description: " "),
            expectedParameter: "metadata.description"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftbasetransform_invalid_author",
            metadata: Self.metadata(author: " "),
            expectedParameter: "metadata.author"
        )

        let invalidCapsScenarios = [
            (
                factoryName: "swiftbasetransform_invalid_sink_caps",
                typeName: "SwiftGstTestInvalidSinkCapsTransform",
                sinkCaps: "video/x-raw,format=(string",
                srcCaps: Self.videoCaps,
                expectedParameter: "sinkCaps"
            ),
            (
                factoryName: "swiftbasetransform_empty_sink_caps",
                typeName: "SwiftGstTestEmptySinkCapsTransform",
                sinkCaps: "EMPTY",
                srcCaps: Self.videoCaps,
                expectedParameter: "sinkCaps"
            ),
            (
                factoryName: "swiftbasetransform_invalid_src_caps",
                typeName: "SwiftGstTestInvalidSrcCapsTransform",
                sinkCaps: Self.videoCaps,
                srcCaps: "video/x-raw,format=(string",
                expectedParameter: "srcCaps"
            ),
            (
                factoryName: "swiftbasetransform_empty_src_caps",
                typeName: "SwiftGstTestEmptySrcCapsTransform",
                sinkCaps: Self.videoCaps,
                srcCaps: "EMPTY",
                expectedParameter: "srcCaps"
            ),
        ]

        for scenario in invalidCapsScenarios {
            let invalidCapsElement = Self.makeElement(
                factoryName: scenario.factoryName,
                typeName: scenario.typeName,
                sinkCaps: scenario.sinkCaps,
                srcCaps: scenario.srcCaps,
                makeInstance: { CountingTransform(recorder: TransformRecorder()) }
            )

            // When the user registers the transform
            let capture = NativeElementRegistrationTestHooks.captureBaseTransformCRegistrationAttempts {
                try GStreamer.register(invalidCapsElement)
            }
            let error = try #require(capture.error)

            // Then registration throws a typed invalid argument error
            Self.expectInvalidArgument(error, parameter: scenario.expectedParameter)

            // And no process-local factory is registered for that input
            #expect(!Self.elementFactoryExists(scenario.factoryName))

            // And the C registration bridge is not called for invalid sink or src caps
            #expect(capture.attemptCount == 0)
        }
    }

    @Test("Duplicate transform factory and type names fail diagnostically")
    func duplicateTransformFactoryAndTypeNamesFailDiagnostically() async throws {
        // Given a Swift transform element has already been registered in the process
        let factoryName = "swiftbasetransform_duplicate_active"
        let typeName = "SwiftGstTestDuplicateActiveTransform"
        let recorder = TransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: typeName,
                passthroughOptions: Self.transformingOptions,
                makeInstance: { CountingTransform(recorder: recorder) }
            )
        )

        // When the user registers another transform with the same factory or GType name
        let duplicateFactoryError = try #require(Self.captureError {
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestDuplicateFactoryTransform",
                    makeInstance: { CountingTransform(recorder: TransformRecorder()) }
                )
            )
        })
        let duplicateTypeFactoryName = "swiftbasetransform_duplicate_type"
        let duplicateTypeError = try #require(Self.captureError {
            try GStreamer.register(
                Self.makeElement(
                    factoryName: duplicateTypeFactoryName,
                    typeName: typeName,
                    makeInstance: { CountingTransform(recorder: TransformRecorder()) }
                )
            )
        })

        // Then registration throws an initialization failure diagnostic
        Self.expectInitializationFailed(duplicateFactoryError)
        Self.expectInitializationFailed(duplicateTypeError)
        #expect(!Self.elementFactoryExists(duplicateTypeFactoryName))

        // And the existing registration remains the active factory
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \(factoryName) ! fakesink sync=false"
        )
        #expect(recorder.snapshot().transformCount == 1)
    }

    @Test("Lifecycle callbacks use one Swift transform instance per GObject")
    func lifecycleCallbacksUseOneSwiftTransformInstancePerGObject() async throws {
        // Given a registered Swift transform creates a stateful Swift instance
        let factoryName = "swiftbasetransform_lifecycle"
        let recorder = LifecycleRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestLifecycleTransform",
                passthroughOptions: Self.transformingOptions,
                sinkCaps: Self.videoCaps,
                srcCaps: Self.videoCaps,
                makeInstance: { LifecycleTransform(recorder: recorder) }
            )
        )

        // When a finite pipeline starts, negotiates caps, transforms buffers, and stops
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=2 ! \(Self.videoCaps) ! \(factoryName) ! fakesink sync=false"
        )
        _ = await Self.waitUntil(timeout: .seconds(1)) {
            recorder.snapshot().destroyCount == 1
        }
        let snapshot = recorder.snapshot()

        // Then start is called for that instance
        #expect(snapshot.instanceCreateCount == 1)
        #expect(snapshot.startCount == 1)

        // And setCaps receives storable owned input and output caps
        #expect(snapshot.setCapsCount == 1)
        let inputCaps = try #require(snapshot.storedInputCapsDescriptions.first)
        let outputCaps = try #require(snapshot.storedOutputCapsDescriptions.first)
        for capsDescription in [inputCaps, outputCaps] {
            #expect(capsDescription.contains("video/x-raw"))
            #expect(capsDescription.contains("format=(string)RGB"))
            #expect(capsDescription.contains("width=(int)2"))
            #expect(capsDescription.contains("height=(int)2"))
            #expect(capsDescription.contains("framerate=(fraction)1/1"))
        }

        // And transformInPlace is called once for each transformed buffer
        #expect(snapshot.transformCount == 2)

        // And stop is called when the transform stops
        #expect(snapshot.stopCount == 1)

        // And the Swift instance context is destroyed exactly once
        #expect(snapshot.destroyCount == 1)
    }

    @Test("Passthrough options control whether Swift transform callbacks run")
    func passthroughOptionsControlWhetherSwiftTransformCallbacksRun() async throws {
        // Given a registered Swift transform negotiates equivalent sink and src caps
        let defaultFactoryName = "swiftbasetransform_passthrough_default"
        let defaultRecorder = TransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: defaultFactoryName,
                typeName: "SwiftGstTestDefaultPassthroughTransform",
                sinkCaps: Self.videoCaps,
                srcCaps: Self.videoCaps,
                makeInstance: { CountingTransform(recorder: defaultRecorder) }
            )
        )

        // When the transform uses default passthrough options
        let defaultFrames = try await Self.collectFrames(
            from: "videotestsrc num-buffers=2 ! \(Self.videoCaps) ! \(defaultFactoryName) ! appsink name=sink sync=false",
            expectedCount: 2
        )

        // Then downstream buffers pass through
        #expect(defaultFrames.count == 2)

        // And Swift transformInPlace is not called while GStreamer is in passthrough mode
        #expect(defaultRecorder.snapshot().transformCount == 0)

        // When the transform opts into transform callbacks on passthrough
        let callbackFactoryName = "swiftbasetransform_passthrough_callback"
        let callbackRecorder = TransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: callbackFactoryName,
                typeName: "SwiftGstTestPassthroughCallbackTransform",
                passthroughOptions: SwiftBaseTransformPassthroughOptions(
                    passthroughOnSameCaps: true,
                    transformInPlaceOnPassthrough: true
                ),
                sinkCaps: Self.videoCaps,
                srcCaps: Self.videoCaps,
                makeInstance: { CountingTransform(recorder: callbackRecorder) }
            )
        )
        let callbackFrames = try await Self.collectFrames(
            from: "videotestsrc num-buffers=2 ! \(Self.videoCaps) ! \(callbackFactoryName) ! appsink name=sink sync=false",
            expectedCount: 2
        )

        // Then downstream buffers still pass through
        #expect(callbackFrames.count == 2)

        // And Swift transformInPlace is called for the passthrough buffers
        #expect(callbackRecorder.snapshot().transformCount == 2)
    }

    @Test("Mutable borrowed buffers can be mutated retained or copied safely")
    func mutableBorrowedBuffersCanBeMutatedRetainedOrCopiedSafely() async throws {
        // Given a Swift transform receives a writable borrowed buffer
        let factoryName = "swiftbasetransform_mutable_buffer"
        let recorder = MutableBufferRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestMutableBufferTransform",
                passthroughOptions: Self.transformingOptions,
                sinkCaps: Self.bgraCaps,
                srcCaps: Self.bgraCaps,
                makeInstance: { MutableBufferTransform(recorder: recorder) }
            )
        )
        let inputBytes: [UInt8] = [
            10, 20, 30, 255,
            40, 50, 60, 255,
            70, 80, 90, 255,
            100, 110, 120, 255,
        ]
        let expectedBytesAfterFirstMutation = Self.invertedBGRA(inputBytes)
        let expectedBytesAfterSecondMutation = Self.markedFirstBGRA(expectedBytesAfterFirstMutation)

        // When the transform mutates bytes and records buffer metadata inside the callback
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            caps: Self.bgraCaps,
            data: inputBytes,
            pts: 100_000_000,
            duration: 33_333_333
        )
        let downstreamBytes = try Self.bytes(in: frame)
        let snapshot = recorder.snapshot()
        let observation = try #require(snapshot.observation)

        // Then write access is bounded to the withUnsafeMutableBytes closure
        #expect(snapshot.transformCount == 1)
        #expect(observation.size == inputBytes.count)
        #expect(observation.byteCount == inputBytes.count)
        #expect(observation.pts == 100_000_000)
        #expect(observation.duration == 33_333_333)
        #expect(observation.prefixBefore == Array(inputBytes.prefix(observation.prefixBefore.count)))
        #expect(
            observation.prefixAfter == Array(
                expectedBytesAfterFirstMutation.prefix(observation.prefixAfter.count)
            )
        )
        #expect(
            observation.prefixAfterSecondMutation == Array(
                expectedBytesAfterSecondMutation.prefix(observation.prefixAfterSecondMutation.count)
            )
        )
        #expect(downstreamBytes == expectedBytesAfterSecondMutation)

        // And a retained reference can outlive the transform callback
        #expect(observation.retainedSize == inputBytes.count)
        #expect(observation.retainedPrefix == observation.prefixAfterSecondMutation)

        // And a deep copy owns independent buffer storage
        #expect(observation.deepCopySize == inputBytes.count)
        #expect(observation.deepCopyPrefix == observation.prefixAfter)
        #expect(observation.deepCopyPrefix != observation.retainedPrefix)
    }

    @Test("Native transform rejects missing buffers and accepts non-writable buffers safely")
    func nativeTransformRejectsMissingBuffersAndAcceptsNonWritableBuffersSafely() {
        // Given the native transform bridge receives no buffer or a non-writable buffer
        let result = Self.bufferRejectionProbe(
            factoryName: "swiftbasetransform_c_buffer_rejection",
            typeName: "SwiftGstTestCBufferRejectionTransform"
        )

        // When transform_ip is invoked by the low-level bridge
        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // Then transform_ip returns a GStreamer flow error for the missing buffer
        #expect(result.nil_buffer_returned_flow_error != 0)
        #expect(result.nil_buffer_callback_count == 0)

        // And the non-writable buffer reaches the Swift transform callback
        #expect(result.non_writable_buffer_was_not_writable != 0)
        #expect(result.non_writable_buffer_returned_ok != 0)
        #expect(result.non_writable_buffer_callback_count == 1)
        #expect(result.callback_counts.transform_ip_count == 1)

        // And no Swift error escapes across the C callback boundary
        #expect(result.callback_counts.start_count == 0)
        #expect(result.callback_counts.set_caps_count == 0)
    }

    @Test("Swift transform can implement an in-place BGRA pixel effect")
    func swiftTransformCanImplementInPlaceBGRAPixelEffect() async throws {
        // Given a Swift transform is registered for BGRA raw video
        let factoryName = "swiftbasetransform_bgra_invert"
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestBGRAInvertTransform",
                passthroughOptions: Self.transformingOptions,
                sinkCaps: Self.bgraCaps,
                srcCaps: Self.bgraCaps,
                makeInstance: { BGRAInvertTransform() }
            )
        )
        let controlBytes: [UInt8] = [
            0, 32, 64, 255,
            128, 160, 192, 255,
            255, 16, 8, 255,
            10, 20, 30, 255,
        ]
        let expectedBytes = Self.invertedBGRA(controlBytes)

        // When the transform inverts BGRA color channels in place
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            caps: Self.bgraCaps,
            data: controlBytes,
            pts: 200_000_000,
            duration: 33_333_333
        )
        let observedBytes = try Self.bytes(in: frame)

        // Then a downstream appsink observes bytes that differ from an unmodified control frame
        #expect(observedBytes != controlBytes)

        // And the observed color channels match the expected inverted values
        #expect(observedBytes == expectedBytes)
    }

    @Test("Swift transform callback failures do not cross C")
    func swiftTransformCallbackFailuresDoNotCrossC() async throws {
        try Self.expectFlowReturnMappings()

        for failureCase in TransformCallbackFailureCase.allCases {
            // Given a registered Swift transform callback reports failure or throws
            let recorder = FailureRecorder()
            let factoryName = "swiftbasetransform_failure_\(failureCase.factorySuffix)"
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestFailure\(failureCase.typeSuffix)Transform",
                    passthroughOptions: Self.transformingOptions,
                    sinkCaps: Self.videoCaps,
                    srcCaps: Self.videoCaps,
                    makeInstance: { FailingTransform(failureCase: failureCase, recorder: recorder) }
                )
            )

            // When a pipeline drives that failing callback
            let error = try #require(await Self.capturePipelineFailure(factoryName: factoryName))

            // Then GStreamer receives the matching BaseTransform failure return value
            Self.expectGStreamerPipelineFailure(error, context: failureCase.rawValue)

            // And the pipeline reports failure through state change or bus error
            #expect(recorder.snapshot().callbackCount(for: failureCase) > 0)

            // And no Swift error escapes across the C callback boundary
            #expect(!(error is TransformCallbackFailureError))
        }
    }

    @Test("Native transform registration owns class contexts")
    func nativeTransformRegistrationOwnsClassContexts() {
        // Given the native transform registration bridge receives a Swift class context
        let result = Self.classContextOwnershipProbe(
            successFactoryName: "swiftbasetransform_c_ownership_success",
            successTypeName: "SwiftGstTestCOwnershipSuccessTransform",
            duplicateFactoryTypeName: "SwiftGstTestCOwnershipDuplicateFactoryTransform",
            duplicateTypeFactoryName: "swiftbasetransform_c_ownership_duplicate_type"
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

    @Test("Missing native transform instance contexts fail deterministically")
    func missingNativeTransformInstanceContextsFailDeterministically() {
        // Given the native transform bridge cannot create a Swift instance context
        let result = Self.missingInstanceProbe(
            factoryName: "swiftbasetransform_missing_instance",
            typeName: "SwiftGstTestMissingInstanceTransform"
        )

        // When GStreamer starts, negotiates caps, transforms, and stops the transform
        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // Then start and set_caps fail without calling Swift instance callbacks
        #expect(result.start_returned_false != 0)
        #expect(result.set_caps_returned_false != 0)
        #expect(result.callback_counts.start_count == 0)
        #expect(result.callback_counts.set_caps_count == 0)

        // And transform_ip returns a GStreamer flow error
        #expect(result.transform_ip_returned_flow_error != 0)
        #expect(result.callback_counts.transform_ip_count == 0)

        // And stop succeeds without calling Swift instance callbacks
        #expect(result.stop_returned_true != 0)
        #expect(result.callback_counts.stop_count == 0)
        #expect(result.callback_counts.create_count == 0)
        #expect(result.callback_counts.destroy_count == 0)
    }

    @Test("Phase 2 transform ABI and API replace placeholders")
    func phase2TransformABIAndAPIReplacePlaceholders() throws {
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

        // When a user looks for transform-related API and C ABI
        #expect(swiftSources.contains("public struct SwiftBaseTransformPassthroughOptions"))
        #expect(swiftSources.contains("public protocol SwiftBaseTransformInstance"))
        #expect(swiftSources.contains("public struct MutableBorrowedBuffer"))
        #expect(swiftSources.contains("public struct SwiftBaseTransformElement"))
        #expect(Self.containsRegex(#"func\s+start\s*\(\s*\)\s+throws"#, in: swiftSources))
        #expect(Self.containsRegex(#"func\s+stop\s*\(\s*\)"#, in: swiftSources))
        #expect(Self.containsRegex(#"func\s+setCaps\s*\(\s*input:\s*Caps\s*,\s*output:\s*Caps\s*\)\s+throws\s*->\s*Bool"#, in: swiftSources))
        #expect(Self.containsRegex(#"func\s+transformInPlace\s*\(\s*_\s+\w+:\s+borrowing\s+MutableBorrowedBuffer\s*\)\s+throws\s*->\s*FlowReturn"#, in: swiftSources))
        #expect(!swiftSources.contains("Swift-backed BaseTransform is planned for Phase 2"))

        // Then BaseTransform construction and registration are available
        #expect(Self.containsRegex(#"public\s+static\s+func\s+inPlace\s*\("#, in: swiftSources))
        #expect(Self.containsRegex(#"public\s+static\s+func\s+register\s*\(\s*_\s+element:\s*SwiftBaseTransformElement\s*\)\s+throws"#, in: swiftSources))

        // And the C shim exports BaseTransform registration and callback ABI
        for required in [
            "gstbasetransform",
            "GstBaseTransform",
            "SwiftGstBaseTransformSetCapsFunc",
            "SwiftGstBaseTransformIPFunc",
            "SwiftGstBaseTransformInfo",
            "SwiftGstBaseTransformCallbacks",
            "swift_gst_register_base_transform",
            "passthrough_on_same_caps",
            "transform_ip_on_passthrough",
        ] {
            #expect(baseShimHeader.contains(required), "Missing Phase 2 BaseTransform C ABI: \(required)")
        }

        // And the existing BaseSink API and ABI remain available
        #expect(swiftSources.contains("public protocol SwiftBaseSinkInstance"))
        #expect(swiftSources.contains("public struct SwiftBaseSinkElement"))
        #expect(baseShimHeader.contains("SwiftGstBaseSinkInfo"))
        #expect(baseShimHeader.contains("SwiftGstBaseSinkCallbacks"))
        #expect(baseShimHeader.contains("swift_gst_register_base_sink"))
    }

    private static var transformingOptions: SwiftBaseTransformPassthroughOptions {
        SwiftBaseTransformPassthroughOptions(
            passthroughOnSameCaps: false,
            transformInPlaceOnPassthrough: false
        )
    }

    private static func makeElement(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        passthroughOptions: SwiftBaseTransformPassthroughOptions = .default,
        sinkCaps: String = "video/x-raw",
        srcCaps: String = "video/x-raw",
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformInstance
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.metadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            passthroughOptions: passthroughOptions,
            makeInstance: makeInstance
        )
    }

    private static func metadata(
        klass: String = "Filter/Effect/Video",
        longName: String = "Swift test BaseTransform",
        description: String = "Swift test BaseTransform element",
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
        srcCaps: String = "video/x-raw",
        expectedParameter: String,
        registeredFactoryName: String? = nil
    ) throws {
        let element = Self.makeElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata,
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            makeInstance: { CountingTransform(recorder: TransformRecorder()) }
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

    private static func collectFrames(from description: String, expectedCount: Int) async throws -> [VideoFrame] {
        let pipeline = try Pipeline(description)
        let appSink = try AppSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        return try await Self.withTimeout(.seconds(2)) {
            var frames: [VideoFrame] = []
            for try await frame in appSink.frames() {
                frames.append(frame)
                if frames.count >= expectedCount {
                    break
                }
            }
            return frames
        }
    }

    private static func pushAndCollectOneFrame(
        through factoryName: String,
        caps: String,
        data: [UInt8],
        pts: UInt64,
        duration: UInt64
    ) async throws -> VideoFrame {
        let pipeline = try Pipeline(
            "appsrc name=src is-live=false format=time do-timestamp=false ! \(caps) ! \(factoryName) ! appsink name=sink sync=false"
        )
        let source = try AppSource(pipeline: pipeline, name: "src")
        let sink = try AppSink(pipeline: pipeline, name: "sink")
        source.setCaps(caps)

        try pipeline.play()
        defer { pipeline.stop() }

        try source.push(data: data, pts: pts, duration: duration)
        source.endOfStream()

        return try await Self.withTimeout(.seconds(2)) {
            for try await frame in sink.frames() {
                return frame
            }
            throw SwiftBaseTransformNativeElementTimeoutError(timeout: .seconds(2))
        }
    }

    private static func capturePipelineFailure(factoryName: String) async throws -> Error? {
        let pipeline = try Pipeline(
            "videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \(factoryName) ! fakesink sync=false"
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

    private static func elementFactoryRank(_ name: String) -> UInt32? {
        let rank = name.withCString { swift_gst_test_element_factory_rank($0) }
        return rank == UInt32.max ? nil : rank
    }

    private static func classContextOwnershipProbe(
        successFactoryName: String,
        successTypeName: String,
        duplicateFactoryTypeName: String,
        duplicateTypeFactoryName: String
    ) -> SwiftGstTestBaseTransformOwnershipProbeResult {
        successFactoryName.withCString { successFactoryName in
            successTypeName.withCString { successTypeName in
                duplicateFactoryTypeName.withCString { duplicateFactoryTypeName in
                    duplicateTypeFactoryName.withCString { duplicateTypeFactoryName in
                        swift_gst_test_base_transform_class_context_ownership_probe(
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

    private static func missingInstanceProbe(
        factoryName: String,
        typeName: String
    ) -> SwiftGstTestBaseTransformMissingInstanceProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_transform_missing_instance_probe(factoryName, typeName)
            }
        }
    }

    fileprivate static func bytes(in buffer: Buffer, limit: Int) -> [UInt8] {
        buffer.bytes.withUnsafeBytes { bytes in
            Array(bytes.prefix(limit))
        }
    }

    private static func bytes(in frame: VideoFrame) throws -> [UInt8] {
        try frame.withUnsafeBytes { bytes in
            Array(bytes)
        }
    }

    private static func invertedBGRA(_ bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        for index in stride(from: 0, to: result.count, by: 4) {
            guard index + 3 < result.count else { break }
            result[index] = 255 &- result[index]
            result[index + 1] = 255 &- result[index + 1]
            result[index + 2] = 255 &- result[index + 2]
        }
        return result
    }

    private static func markedFirstBGRA(_ bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        guard result.count >= 4 else { return result }
        result[0] = 1
        result[1] = 2
        result[2] = 3
        result[3] = 255
        return result
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
                throw SwiftBaseTransformNativeElementTimeoutError(timeout: timeout)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw SwiftBaseTransformNativeElementTimeoutError(timeout: timeout)
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

private final class TransformRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var transformCount = 0
    }

    func recordTransform() {
        state.withLock { $0.transformCount += 1 }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class CountingTransform: SwiftBaseTransformInstance {
    private let recorder: TransformRecorder

    init(recorder: TransformRecorder) {
        self.recorder = recorder
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        recorder.recordTransform()
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
        var transformCount = 0
        var storedInputCapsDescriptions: [String] = []
        var storedOutputCapsDescriptions: [String] = []
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

    func recordSetCaps(input: Caps, output: Caps) {
        state.withLock {
            $0.setCapsCount += 1
            $0.storedInputCapsDescriptions.append(input.description)
            $0.storedOutputCapsDescriptions.append(output.description)
        }
    }

    func recordTransform() {
        state.withLock { $0.transformCount += 1 }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class LifecycleTransform: SwiftBaseTransformInstance {
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

    func setCaps(input: Caps, output: Caps) throws -> Bool {
        recorder.recordSetCaps(input: input, output: output)
        return true
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        recorder.recordTransform()
        return .ok
    }
}

private final class MutableBufferRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var transformCount = 0
        var observation: MutableBufferObservation?
    }

    func record(_ observation: MutableBufferObservation) {
        state.withLock {
            $0.transformCount += 1
            $0.observation = observation
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private struct MutableBufferObservation: Sendable {
    var size: Int
    var byteCount: Int
    var pts: UInt64?
    var duration: UInt64?
    var prefixBefore: [UInt8]
    var prefixAfter: [UInt8]
    var prefixAfterSecondMutation: [UInt8]
    var retainedSize: Int
    var retainedPrefix: [UInt8]
    var deepCopySize: Int
    var deepCopyPrefix: [UInt8]
}

private final class MutableBufferTransform: SwiftBaseTransformInstance {
    private let recorder: MutableBufferRecorder

    init(recorder: MutableBufferRecorder) {
        self.recorder = recorder
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        let size = buffer.size
        let pts = buffer.pts
        let duration = buffer.duration
        let mutation = try buffer.withUnsafeMutableBytes { bytes in
            let prefixCount = min(bytes.count, 16)
            let before = Array(bytes.prefix(prefixCount))
            Self.invertBGRA(bytes)
            let after = Array(bytes.prefix(prefixCount))
            return (byteCount: bytes.count, before: before, after: after)
        }
        let copied = try buffer.deepCopy()
        let secondMutationPrefix = try buffer.withUnsafeMutableBytes { bytes in
            Self.markFirstBGRA(bytes)
            return Array(bytes.prefix(mutation.after.count))
        }
        let retained = buffer.retainedReference()
        let observation = MutableBufferObservation(
            size: size,
            byteCount: mutation.byteCount,
            pts: pts,
            duration: duration,
            prefixBefore: mutation.before,
            prefixAfter: mutation.after,
            prefixAfterSecondMutation: secondMutationPrefix,
            retainedSize: retained.size,
            retainedPrefix: SwiftBaseTransformNativeElementTests.bytes(in: retained, limit: secondMutationPrefix.count),
            deepCopySize: copied.size,
            deepCopyPrefix: SwiftBaseTransformNativeElementTests.bytes(in: copied, limit: mutation.after.count)
        )
        recorder.record(observation)
        return .ok
    }

    private static func invertBGRA(_ bytes: UnsafeMutableRawBufferPointer) {
        for index in stride(from: 0, to: bytes.count, by: 4) {
            guard index + 3 < bytes.count else { break }
            bytes[index] = 255 &- bytes[index]
            bytes[index + 1] = 255 &- bytes[index + 1]
            bytes[index + 2] = 255 &- bytes[index + 2]
        }
    }

    private static func markFirstBGRA(_ bytes: UnsafeMutableRawBufferPointer) {
        guard bytes.count >= 4 else { return }
        bytes[0] = 1
        bytes[1] = 2
        bytes[2] = 3
        bytes[3] = 255
    }
}

private final class BGRAInvertTransform: SwiftBaseTransformInstance {
    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        try buffer.withUnsafeMutableBytes { bytes in
            for index in stride(from: 0, to: bytes.count, by: 4) {
                guard index + 3 < bytes.count else { break }
                bytes[index] = 255 &- bytes[index]
                bytes[index + 1] = 255 &- bytes[index + 1]
                bytes[index + 2] = 255 &- bytes[index + 2]
            }
        }
        return .ok
    }
}

private enum TransformCallbackFailureCase: String, CaseIterable, Sendable {
    case startThrows
    case setCapsReturnsFalse
    case setCapsThrows
    case transformThrows
    case transformReturnsError
    case transformReturnsNotNegotiated

    var factorySuffix: String {
        switch self {
        case .startThrows: "start_throws"
        case .setCapsReturnsFalse: "setcaps_false"
        case .setCapsThrows: "setcaps_throws"
        case .transformThrows: "transform_throws"
        case .transformReturnsError: "transform_error"
        case .transformReturnsNotNegotiated: "transform_not_negotiated"
        }
    }

    var typeSuffix: String {
        switch self {
        case .startThrows: "StartThrows"
        case .setCapsReturnsFalse: "SetCapsFalse"
        case .setCapsThrows: "SetCapsThrows"
        case .transformThrows: "TransformThrows"
        case .transformReturnsError: "TransformError"
        case .transformReturnsNotNegotiated: "TransformNotNegotiated"
        }
    }
}

private struct TransformCallbackFailureError: Error, Sendable {
    let failureCase: TransformCallbackFailureCase
}

private final class FailureRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var startCount = 0
        var setCapsCount = 0
        var transformCount = 0

        func callbackCount(for failureCase: TransformCallbackFailureCase) -> Int {
            switch failureCase {
            case .startThrows:
                startCount
            case .setCapsReturnsFalse, .setCapsThrows:
                setCapsCount
            case .transformThrows, .transformReturnsError, .transformReturnsNotNegotiated:
                transformCount
            }
        }
    }

    func recordStart() {
        state.withLock { $0.startCount += 1 }
    }

    func recordSetCaps() {
        state.withLock { $0.setCapsCount += 1 }
    }

    func recordTransform() {
        state.withLock { $0.transformCount += 1 }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class FailingTransform: SwiftBaseTransformInstance {
    private let failureCase: TransformCallbackFailureCase
    private let recorder: FailureRecorder

    init(failureCase: TransformCallbackFailureCase, recorder: FailureRecorder) {
        self.failureCase = failureCase
        self.recorder = recorder
    }

    func start() throws {
        recorder.recordStart()
        if failureCase == .startThrows {
            throw TransformCallbackFailureError(failureCase: failureCase)
        }
    }

    func setCaps(input: Caps, output: Caps) throws -> Bool {
        recorder.recordSetCaps()
        switch failureCase {
        case .setCapsReturnsFalse:
            return false
        case .setCapsThrows:
            throw TransformCallbackFailureError(failureCase: failureCase)
        default:
            return true
        }
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        recorder.recordTransform()
        switch failureCase {
        case .transformThrows:
            throw TransformCallbackFailureError(failureCase: failureCase)
        case .transformReturnsError:
            return .error
        case .transformReturnsNotNegotiated:
            return .notNegotiated
        default:
            return .ok
        }
    }
}

private struct SwiftBaseTransformNativeElementTimeoutError: Error, CustomStringConvertible, Sendable {
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
