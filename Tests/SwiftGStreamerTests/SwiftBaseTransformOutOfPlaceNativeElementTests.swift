import Foundation
import Synchronization
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Swift BaseTransform Out-of-place Native Element Tests", .serialized, .timeLimit(.minutes(1)))
struct SwiftBaseTransformOutOfPlaceNativeElementTests {
    private static let videoCaps = "video/x-raw,format=RGB,width=2,height=2,framerate=1/1"
    private static let bgraCaps = "video/x-raw,format=BGRA,width=2,height=2,framerate=30/1"

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Swift out-of-place transform can be registered and used from a pipeline string")
    func swiftOutOfPlaceTransformCanBeRegisteredAndUsedFromPipelineString() async throws {
        // Given a Swift out-of-place transform element has valid metadata and matching fixed-size video caps
        let factoryName = "swiftoutofplace_pipeline_copy"
        let recorder = OutOfPlaceTransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestOutOfPlacePipelineCopyTransform",
                sinkCaps: Self.videoCaps,
                srcCaps: Self.videoCaps,
                makeInstance: { CopyingOutOfPlaceTransform(recorder: recorder) }
            )
        )

        // When the user registers the transform as an in-process factory
        #expect(Self.elementFactoryExists(factoryName))

        // Then a pipeline string can create that transform by factory name
        let frames = try await Self.collectFrames(
            from: "videotestsrc num-buffers=3 ! \(Self.videoCaps) ! \(factoryName) ! appsink name=sink sync=false",
            expectedCount: 3,
            waitForEOS: true
        )

        // And a finite video test pipeline reaches end-of-stream
        // And downstream receives the expected number of frames
        #expect(frames.count == 3)

        // And Swift transform is called once for each processed buffer
        #expect(recorder.snapshot().transformCount == 3)
    }

    @Test("Generated out-of-place transform type names are deterministic and distinct")
    func generatedOutOfPlaceTransformTypeNamesAreDeterministicAndDistinct() throws {
        // Given a Swift out-of-place transform element omits its GType name
        let factoryName = "swift-native_outofplace-01"
        let element = Self.makeElement(
            factoryName: factoryName,
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
        )

        // When the user registers it with a factory name that can also be used by an in-place transform
        let sanitized = NativeElementTypeName.sanitizedFactoryNameComponent(factoryName)
        let hash = NativeElementTypeName.fnv1a64Hex(factoryName)
        let inPlaceGenerated = NativeElementTypeName.generatedBaseTransformTypeName(factoryName: factoryName)
        let outOfPlaceGenerated = NativeElementTypeName.generatedBaseTransformOutOfPlaceTypeName(
            factoryName: factoryName
        )
        try GStreamer.register(element)

        // Then the generated out-of-place type name is deterministic
        #expect(sanitized == "swift_native_outofplace_01")
        #expect(hash == NativeElementTypeName.fnv1a64Hex(factoryName))
        #expect(outOfPlaceGenerated == "SwiftGstNativeBaseTransformOutOfPlace_swift_native_outofplace_01_\(hash)")
        #expect(NativeElementTypeName.isValidDynamicGTypeName(outOfPlaceGenerated))
        #expect(Self.elementFactoryExists(factoryName))

        // And it cannot collide with the generated in-place type name for the same factory
        #expect(outOfPlaceGenerated != inPlaceGenerated)
    }

    @Test("Registration preserves out-of-place transform factory rank metadata")
    func registrationPreservesOutOfPlaceTransformFactoryRankMetadata() throws {
        // Given one Swift out-of-place transform element uses default metadata rank
        let defaultFactoryName = "swiftoutofplace_rank_default"
        try GStreamer.register(
            Self.makeElement(
                factoryName: defaultFactoryName,
                typeName: "SwiftGstTestOutOfPlaceDefaultRankTransform",
                makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
            )
        )

        // And another Swift out-of-place transform element uses custom metadata rank
        let customFactoryName = "swiftoutofplace_rank_custom"
        try GStreamer.register(
            Self.makeElement(
                factoryName: customFactoryName,
                typeName: "SwiftGstTestOutOfPlaceCustomRankTransform",
                metadata: Self.metadata(rank: .primary),
                makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
            )
        )

        // When the user registers both transforms
        let defaultRank = try #require(Self.elementFactoryRank(defaultFactoryName))
        let customRank = try #require(Self.elementFactoryRank(customFactoryName))

        // Then the default-rank out-of-place transform factory has rank none
        #expect(defaultRank == ElementRank.none.rawValue)

        // And the custom-rank out-of-place transform factory has the requested rank
        #expect(customRank == ElementRank.primary.rawValue)
    }

    @Test("Invalid out-of-place transform registration input fails before C registration")
    func invalidOutOfPlaceTransformRegistrationInputFailsBeforeCRegistration() throws {
        // Given a Swift out-of-place transform element has invalid caller-supplied registration input
        try Self.expectInvalidRegistration(
            factoryName: "",
            expectedParameter: "factoryName",
            registeredFactoryName: nil
        )
        try Self.expectInvalidRegistration(
            factoryName: "-swiftoutofplace-invalid-start",
            expectedParameter: "factoryName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace invalid character",
            expectedParameter: "factoryName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace_invalid_empty_type",
            typeName: "",
            expectedParameter: "typeName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace_invalid_type_chars",
            typeName: "SwiftGstInvalid-OutOfPlaceType",
            expectedParameter: "typeName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace_invalid_klass",
            metadata: Self.metadata(klass: " "),
            expectedParameter: "metadata.klass"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace_invalid_long_name",
            metadata: Self.metadata(longName: " "),
            expectedParameter: "metadata.longName"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace_invalid_description",
            metadata: Self.metadata(description: " "),
            expectedParameter: "metadata.description"
        )
        try Self.expectInvalidRegistration(
            factoryName: "swiftoutofplace_invalid_author",
            metadata: Self.metadata(author: " "),
            expectedParameter: "metadata.author"
        )

        let invalidCapsScenarios = [
            (
                factoryName: "swiftoutofplace_invalid_sink_caps",
                typeName: "SwiftGstTestOutOfPlaceInvalidSinkCapsTransform",
                sinkCaps: "video/x-raw,format=(string",
                srcCaps: Self.videoCaps,
                expectedParameter: "sinkCaps"
            ),
            (
                factoryName: "swiftoutofplace_empty_sink_caps",
                typeName: "SwiftGstTestOutOfPlaceEmptySinkCapsTransform",
                sinkCaps: "EMPTY",
                srcCaps: Self.videoCaps,
                expectedParameter: "sinkCaps"
            ),
            (
                factoryName: "swiftoutofplace_invalid_src_caps",
                typeName: "SwiftGstTestOutOfPlaceInvalidSrcCapsTransform",
                sinkCaps: Self.videoCaps,
                srcCaps: "video/x-raw,format=(string",
                expectedParameter: "srcCaps"
            ),
            (
                factoryName: "swiftoutofplace_empty_src_caps",
                typeName: "SwiftGstTestOutOfPlaceEmptySrcCapsTransform",
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
                makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
            )

            // When the user registers the transform
            let capture = NativeElementRegistrationTestHooks.captureBaseTransformOutOfPlaceCRegistrationAttempts {
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

    @Test("Duplicate out-of-place transform factory and type names fail diagnostically")
    func duplicateOutOfPlaceTransformFactoryAndTypeNamesFailDiagnostically() async throws {
        // Given a Swift out-of-place transform element has already been registered in the process
        let factoryName = "swiftoutofplace_duplicate_active"
        let typeName = "SwiftGstTestOutOfPlaceDuplicateActiveTransform"
        let recorder = OutOfPlaceTransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: typeName,
                makeInstance: { CopyingOutOfPlaceTransform(recorder: recorder) }
            )
        )

        // When the user registers another out-of-place transform with the same factory or GType name
        let duplicateFactoryError = try #require(Self.captureError {
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestOutOfPlaceDuplicateFactoryTransform",
                    makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
                )
            )
        })
        let duplicateTypeFactoryName = "swiftoutofplace_duplicate_type"
        let duplicateTypeError = try #require(Self.captureError {
            try GStreamer.register(
                Self.makeElement(
                    factoryName: duplicateTypeFactoryName,
                    typeName: typeName,
                    makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
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

    @Test("Public out-of-place transform API is additive")
    func publicOutOfPlaceTransformAPIIsAdditive() throws {
        // Given the package exposes existing in-place BaseTransform API
        _ = SwiftBaseTransformElement.self
        _ = SwiftBaseTransformInstance.self
        _ = SwiftBaseTransformPassthroughOptions.self
        _ = MutableBorrowedBuffer.self

        // When a user looks for Phase 4 out-of-place API
        _ = SwiftBaseTransformOutOfPlaceElement.self
        _ = SwiftBaseTransformOutOfPlaceInstance.self
        let noPropertyElement = SwiftBaseTransformOutOfPlaceElement(
            factoryName: "swiftoutofplace_static_no_property",
            metadata: Self.metadata(),
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
        )
        let propertyReaderElement = SwiftBaseTransformOutOfPlaceElement(
            factoryName: "swiftoutofplace_static_property_reader",
            typeName: nil,
            metadata: Self.metadata(),
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            properties: [],
            makeInstance: { (_: NativeElementPropertyReader) in
                CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder())
            }
        )
        _ = noPropertyElement
        _ = propertyReaderElement
        let registerOutOfPlace: (SwiftBaseTransformOutOfPlaceElement) throws -> Void = GStreamer.register
        let registerInPlace: (SwiftBaseTransformElement) throws -> Void = GStreamer.register
        _ = registerOutOfPlace
        _ = registerInPlace

        let root = try Self.packageRoot()
        let baseTransformSource = try NativeElementSourceLayoutTestSupport.nativeElementSwiftSource()
        let baseShimHeader = try Self.contents(
            of: root.appendingPathComponent("Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        )

        // Then no public out-of-place passthrough options are available
        #expect(!baseTransformSource.contains("SwiftBaseTransformOutOfPlacePassthroughOptions"))
        #expect(!baseTransformSource.contains("outOfPlacePassthroughOptions"))

        // And the C ABI contains mode-specific transform registration hooks
        #expect(baseShimHeader.contains("SwiftGstBaseTransformMode"))
        #expect(baseShimHeader.contains("SwiftGstBaseTransformFunc"))
        #expect(baseShimHeader.contains("SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE"))
        #expect(baseShimHeader.contains("SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE"))
    }

    @Test("Lifecycle callbacks use one Swift out-of-place transform instance per GObject")
    func lifecycleCallbacksUseOneSwiftOutOfPlaceTransformInstancePerGObject() async throws {
        // Given a registered out-of-place transform creates a stateful Swift instance
        let factoryName = "swiftoutofplace_lifecycle"
        let recorder = OutOfPlaceLifecycleRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestOutOfPlaceLifecycleTransform",
                sinkCaps: Self.videoCaps,
                srcCaps: Self.videoCaps,
                makeInstance: { LifecycleOutOfPlaceTransform(recorder: recorder) }
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

        // And transform is called once for each transformed buffer
        #expect(snapshot.transformCount == 2)

        // And stop is called when the transform stops
        #expect(snapshot.stopCount == 1)

        // And the Swift instance context is destroyed exactly once
        #expect(snapshot.destroyCount == 1)
    }

    @Test("Missing native out-of-place transform instance contexts fail deterministically")
    func missingNativeOutOfPlaceTransformInstanceContextsFailDeterministically() {
        // Given the native out-of-place transform bridge cannot create a Swift instance context
        let result = Self.missingInstanceProbe(
            factoryName: "swiftoutofplace_missing_instance",
            typeName: "SwiftGstTestOutOfPlaceMissingInstanceTransform"
        )

        // When GStreamer starts, negotiates caps, transforms, and stops the transform
        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // Then start and set_caps fail without calling Swift instance callbacks
        #expect(result.start_returned_false != 0)
        #expect(result.set_caps_returned_false != 0)
        #expect(result.callback_counts.start_count == 0)
        #expect(result.callback_counts.set_caps_count == 0)

        // And transform returns a GStreamer flow error
        #expect(result.transform_returned_flow_error != 0)
        #expect(result.callback_counts.transform_count == 0)

        // And stop succeeds without calling Swift instance callbacks
        #expect(result.stop_returned_true != 0)
        #expect(result.callback_counts.stop_count == 0)
        #expect(result.callback_counts.create_count == 0)
        #expect(result.callback_counts.destroy_count == 0)
    }

    @Test("C shim allocates a separate fixed-size output buffer")
    func cShimAllocatesSeparateFixedSizeOutputBuffer() {
        // Given a registered out-of-place transform receives an input buffer
        let result = Self.outputAllocationProbe(
            factoryName: "swiftoutofplace_c_output_allocation",
            typeName: "SwiftGstTestOutOfPlaceCOutputAllocationTransform"
        )

        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // When the native bridge prepares the output buffer
        #expect(result.prepare_output_returned_ok != 0)
        #expect(result.transform_returned_ok != 0)

        // Then the output buffer is a fresh allocation
        #expect(result.output_is_distinct_from_input != 0)
        #expect(result.output_is_writable != 0)

        // And the output buffer has exactly the same byte size as the input buffer
        #expect(result.input_size == result.output_size)
        #expect(result.callback_counts.transform_count == 1)
        #expect(result.pts_preserved != 0)
        #expect(result.duration_preserved != 0)
    }

    @Test("Output allocation failure stops before Swift transform runs")
    func outputAllocationFailureStopsBeforeSwiftTransformRuns() {
        // Given the native out-of-place transform output allocator fails
        let result = Self.outputAllocationFailureProbe(
            factoryName: "swiftoutofplace_c_allocation_failure",
            typeName: "SwiftGstTestOutOfPlaceCAllocationFailureTransform"
        )

        #expect(result.registration_succeeded != 0)
        #expect(result.element_created != 0)

        // When the native bridge prepares the output buffer
        // Then prepare_output_buffer returns a GStreamer flow error
        #expect(result.prepare_output_returned_flow_error != 0)

        // And Swift transform is not called
        #expect(result.transform_not_called != 0)
        #expect(result.callback_counts.transform_count == 0)
    }

    @Test("Swift out-of-place transform writes output without mutating input")
    func swiftOutOfPlaceTransformWritesOutputWithoutMutatingInput() async throws {
        // Given a Swift out-of-place transform receives known BGRA input bytes
        let factoryName = "swiftoutofplace_bgra_transform"
        let recorder = OutOfPlaceBufferRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestOutOfPlaceBGRATransform",
                sinkCaps: Self.bgraCaps,
                srcCaps: Self.bgraCaps,
                makeInstance: { RecordingOutOfPlaceTransform(recorder: recorder) }
            )
        )
        let inputBytes: [UInt8] = [
            10, 20, 30, 255,
            40, 50, 60, 255,
            70, 80, 90, 255,
            100, 110, 120, 255,
        ]
        let expectedOutput = Self.invertedBGRA(inputBytes)

        // When the transform writes deterministic output bytes
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            caps: Self.bgraCaps,
            data: inputBytes,
            pts: 100_000_000,
            duration: 33_333_333
        )
        let downstreamBytes = try Self.bytes(in: frame)
        let observation = try #require(recorder.snapshot().observation)

        // Then downstream observes the transformed output bytes
        #expect(downstreamBytes == expectedOutput)
        #expect(observation.outputBytes == expectedOutput)

        // And the recorded input bytes remain unchanged
        #expect(observation.inputBefore == inputBytes)
        #expect(observation.inputAfter == inputBytes)

        // And output byte access is writable only during the scoped callback
        #expect(observation.inputSize == inputBytes.count)
        #expect(observation.outputSize == inputBytes.count)
        #expect(observation.outputPTS == 100_000_000)
        #expect(observation.outputDuration == 33_333_333)
    }

    @Test("Out-of-place transform preserves output timing metadata")
    func outOfPlaceTransformPreservesOutputTimingMetadata() async throws {
        // Given an input buffer has a valid presentation timestamp and duration
        let factoryName = "swiftoutofplace_timing"
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestOutOfPlaceTimingTransform",
                sinkCaps: Self.bgraCaps,
                srcCaps: Self.bgraCaps,
                makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
            )
        )
        let inputBytes: [UInt8] = Array(repeating: 17, count: 16)
        let pts: UInt64 = 222_000_000
        let duration: UInt64 = 33_333_333

        // When the out-of-place transform succeeds
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            caps: Self.bgraCaps,
            data: inputBytes,
            pts: pts,
            duration: duration
        )

        // Then downstream observes the same presentation timestamp
        #expect(frame.pts == pts)

        // And downstream observes the same duration
        #expect(frame.duration == duration)
    }

    @Test("Out-of-place transforms support native element properties")
    func outOfPlaceTransformsSupportNativeElementProperties() async throws {
        // Given a Swift out-of-place transform declares native element properties
        let outOfPlaceFactoryName = "swiftoutofplace_properties"
        let outOfPlaceRecorder = PropertyObservationRecorder()
        try GStreamer.register(
            Self.makePropertyElement(
                factoryName: outOfPlaceFactoryName,
                typeName: "SwiftGstTestOutOfPlacePropertiesTransform",
                recorder: outOfPlaceRecorder
            )
        )
        let element = try Element.make(factory: outOfPlaceFactoryName)

        // When a pipeline string configures those properties
        try await Self.runFiniteVideoPipeline(
            """
            videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \
            \(outOfPlaceFactoryName) enabled=false count=6 strength=0.6 label=out-label mode=quick ! \
            fakesink sync=false
            """
        )

        // Then the generated element exposes readable and writable GObject properties
        for propertyName in PropertySchema.propertyNames {
            let property = try #require(element.property(named: propertyName))
            #expect(property.isReadable)
            #expect(property.isWritable)
        }

        // And transform reads the configured values through its injected property reader
        Self.expectObservation(
            try #require(outOfPlaceRecorder.snapshot().transformObservations.last),
            matches: .configured(
                bool: false,
                int: 6,
                double: 0.6,
                string: "out-label",
                enumCase: "fast"
            )
        )

        // And existing BaseSink and in-place BaseTransform property behavior remains unchanged
        let inPlaceFactoryName = "swiftoutofplace_properties_in_place_control"
        let inPlaceRecorder = PropertyObservationRecorder()
        try GStreamer.register(
            Self.makeInPlacePropertyElement(
                factoryName: inPlaceFactoryName,
                typeName: "SwiftGstTestOutOfPlaceInPlacePropertyControlTransform",
                recorder: inPlaceRecorder
            )
        )
        try await Self.runFiniteVideoPipeline(
            """
            videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \
            \(inPlaceFactoryName) enabled=false count=7 strength=0.7 label=inplace-label mode=fast ! \
            fakesink sync=false
            """
        )
        Self.expectObservation(
            try #require(inPlaceRecorder.snapshot().transformObservations.last),
            matches: .configured(
                bool: false,
                int: 7,
                double: 0.7,
                string: "inplace-label",
                enumCase: "fast"
            )
        )
    }

    @Test("Out-of-place transform callback failures do not cross C")
    func outOfPlaceTransformCallbackFailuresDoNotCrossC() async throws {
        try Self.expectFlowReturnMappings()

        for failureCase in OutOfPlaceCallbackFailureCase.allCases {
            // Given a registered out-of-place transform callback reports failure or throws
            let recorder = OutOfPlaceFailureRecorder()
            let factoryName = "swiftoutofplace_failure_\(failureCase.factorySuffix)"
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestOutOfPlaceFailure\(failureCase.typeSuffix)Transform",
                    sinkCaps: Self.videoCaps,
                    srcCaps: Self.videoCaps,
                    makeInstance: {
                        FailingOutOfPlaceTransform(failureCase: failureCase, recorder: recorder)
                    }
                )
            )

            // When a pipeline drives that failing callback
            let error = try #require(await Self.capturePipelineFailure(factoryName: factoryName))

            // Then GStreamer receives the matching BaseTransform failure return value
            Self.expectGStreamerPipelineFailure(error, context: failureCase.rawValue)

            // And the pipeline reports failure through state change or bus error
            #expect(recorder.snapshot().callbackCount(for: failureCase) > 0)

            // And no Swift error escapes across the C callback boundary
            #expect(!(error is OutOfPlaceCallbackFailureError))
        }
    }

    @Test("Native out-of-place transform registration owns class contexts")
    func nativeOutOfPlaceTransformRegistrationOwnsClassContexts() {
        // Given the native out-of-place transform registration bridge receives a Swift class context
        let result = Self.classContextOwnershipProbe(
            successFactoryName: "swiftoutofplace_c_ownership_success",
            successTypeName: "SwiftGstTestOutOfPlaceCOwnershipSuccessTransform",
            duplicateFactoryTypeName: "SwiftGstTestOutOfPlaceCOwnershipDuplicateFactoryTransform",
            duplicateTypeFactoryName: "swiftoutofplace_c_ownership_duplicate_type"
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

    @Test("Phase 4 transform C ABI supports mode-specific callbacks")
    func phase4TransformCABISupportsModeSpecificCallbacks() throws {
        // Given the BaseTransform C registration ABI supports transform modes
        let root = try Self.packageRoot()
        let baseShimHeader = try Self.contents(
            of: root.appendingPathComponent("Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        )
        #expect(baseShimHeader.contains("SwiftGstBaseTransformMode"))
        #expect(baseShimHeader.contains("SWIFT_GST_BASE_TRANSFORM_MODE_IN_PLACE"))
        #expect(baseShimHeader.contains("SWIFT_GST_BASE_TRANSFORM_MODE_OUT_OF_PLACE"))
        #expect(baseShimHeader.contains("SwiftGstBaseTransformFunc"))
        #expect(baseShimHeader.contains("transform"))

        // When native registrations are validated
        let result = swift_gst_test_base_transform_mode_validation_probe()

        // Then unknown modes fail before GType registration
        #expect(result.unknown_mode_registration_failed != 0)

        // And in-place mode still requires the transform_ip callback
        #expect(result.in_place_without_transform_ip_registration_failed != 0)

        // And in-place mode does not require the transform callback
        #expect(result.in_place_without_transform_registration_succeeded != 0)

        // And out-of-place mode requires the transform callback
        #expect(result.out_of_place_without_transform_registration_failed != 0)

        // And out-of-place mode does not require the transform_ip callback
        #expect(result.out_of_place_without_transform_ip_registration_succeeded != 0)

        // And common lifecycle, caps, context, and property validation remains unchanged
        #expect(result.missing_common_callback_registration_failed != 0)
    }

    private static func makeElement(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = "video/x-raw",
        srcCaps: String = "video/x-raw",
        properties: [NativeElementProperty] = [],
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformOutOfPlaceInstance
    ) -> SwiftBaseTransformOutOfPlaceElement {
        SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.metadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            properties: properties,
            makeInstance: makeInstance
        )
    }

    private static func makePropertyElement(
        factoryName: String,
        typeName: String,
        recorder: PropertyObservationRecorder
    ) -> SwiftBaseTransformOutOfPlaceElement {
        SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.metadata(),
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            properties: PropertySchema.supportedProperties(),
            makeInstance: { reader in
                PropertyRecordingOutOfPlaceTransform(reader: reader, recorder: recorder)
            }
        )
    }

    private static func makeInPlacePropertyElement(
        factoryName: String,
        typeName: String,
        recorder: PropertyObservationRecorder
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.metadata(),
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            passthroughOptions: SwiftBaseTransformPassthroughOptions(
                passthroughOnSameCaps: false,
                transformInPlaceOnPassthrough: false
            ),
            properties: PropertySchema.supportedProperties(),
            makeInstance: { reader in
                PropertyRecordingInPlaceTransform(reader: reader, recorder: recorder)
            }
        )
    }

    private static func metadata(
        klass: String = "Filter/Effect/Video",
        longName: String = "Swift test out-of-place BaseTransform",
        description: String = "Swift test out-of-place BaseTransform element",
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
            makeInstance: { CopyingOutOfPlaceTransform(recorder: OutOfPlaceTransformRecorder()) }
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

    private static func collectFrames(
        from description: String,
        expectedCount: Int,
        waitForEOS: Bool = false
    ) async throws -> [VideoFrame] {
        let pipeline = try Pipeline(description)
        let appSink = try AppSink(pipeline: pipeline, name: "sink")
        try pipeline.play()
        defer { pipeline.stop() }

        return try await Self.withTimeout(.seconds(2)) {
            async let eos: Void = waitForEOS ? pipeline.bus.waitForEOSOrError() : ()
            var frames: [VideoFrame] = []
            for try await frame in appSink.frames() {
                frames.append(frame)
                if frames.count >= expectedCount {
                    break
                }
            }
            try await eos
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
            throw SwiftBaseTransformOutOfPlaceNativeElementTimeoutError(timeout: .seconds(2))
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

    private static func expectObservation(
        _ observation: PropertyObservation,
        matches expected: PropertyExpectedObservation
    ) {
        #expect(observation.boolValue == expected.boolValue)
        #expect(observation.intValue == expected.intValue)
        if let actual = observation.doubleValue, let expected = expected.doubleValue {
            #expect(abs(actual - expected) < 0.000_001)
        } else {
            #expect(observation.doubleValue == expected.doubleValue)
        }
        #expect(observation.stringValue == expected.stringValue)
        #expect(observation.enumValue == expected.enumValue)
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
    ) -> SwiftGstTestBaseTransformOutOfPlaceOwnershipProbeResult {
        successFactoryName.withCString { successFactoryName in
            successTypeName.withCString { successTypeName in
                duplicateFactoryTypeName.withCString { duplicateFactoryTypeName in
                    duplicateTypeFactoryName.withCString { duplicateTypeFactoryName in
                        swift_gst_test_base_transform_out_of_place_class_context_ownership_probe(
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
    ) -> SwiftGstTestBaseTransformOutOfPlaceMissingInstanceProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_transform_out_of_place_missing_instance_probe(factoryName, typeName)
            }
        }
    }

    private static func outputAllocationProbe(
        factoryName: String,
        typeName: String
    ) -> SwiftGstTestBaseTransformOutOfPlaceOutputAllocationProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_transform_out_of_place_output_allocation_probe(factoryName, typeName)
            }
        }
    }

    private static func outputAllocationFailureProbe(
        factoryName: String,
        typeName: String
    ) -> SwiftGstTestBaseTransformOutOfPlaceAllocationFailureProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_transform_out_of_place_allocation_failure_probe(factoryName, typeName)
            }
        }
    }

    private static func bytes(in frame: VideoFrame) throws -> [UInt8] {
        try frame.withUnsafeBytes { bytes in
            Array(bytes)
        }
    }

    fileprivate static func invertedBGRA(_ bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        for index in stride(from: 0, to: result.count, by: 4) {
            guard index + 3 < result.count else { break }
            result[index] = 255 &- result[index]
            result[index + 1] = 255 &- result[index + 1]
            result[index + 2] = 255 &- result[index + 2]
        }
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
                throw SwiftBaseTransformOutOfPlaceNativeElementTimeoutError(timeout: timeout)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw SwiftBaseTransformOutOfPlaceNativeElementTimeoutError(timeout: timeout)
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
                throw StaticOutOfPlaceNativeElementTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

}

private func copyBytes(
    _ input: borrowing BorrowedBuffer,
    into output: borrowing MutableBorrowedBuffer
) throws {
    let inputBytes = try input.withUnsafeBytes { Array($0) }
    try output.withUnsafeMutableBytes { bytes in
        let count = min(bytes.count, inputBytes.count)
        for index in 0..<count {
            bytes[index] = inputBytes[index]
        }
    }
}

private final class OutOfPlaceTransformRecorder: @unchecked Sendable {
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

private final class CopyingOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let recorder: OutOfPlaceTransformRecorder

    init(recorder: OutOfPlaceTransformRecorder) {
        self.recorder = recorder
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        recorder.recordTransform()
        try copyBytes(input, into: output)
        return .ok
    }
}

private final class OutOfPlaceLifecycleRecorder: @unchecked Sendable {
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

private final class LifecycleOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let recorder: OutOfPlaceLifecycleRecorder

    init(recorder: OutOfPlaceLifecycleRecorder) {
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

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        recorder.recordTransform()
        try copyBytes(input, into: output)
        return .ok
    }
}

private final class OutOfPlaceBufferRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var observation: OutOfPlaceBufferObservation?
    }

    func record(_ observation: OutOfPlaceBufferObservation) {
        state.withLock { $0.observation = observation }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private struct OutOfPlaceBufferObservation: Sendable {
    var inputSize: Int
    var outputSize: Int
    var outputPTS: UInt64?
    var outputDuration: UInt64?
    var inputBefore: [UInt8]
    var inputAfter: [UInt8]
    var outputBytes: [UInt8]
}

private final class RecordingOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let recorder: OutOfPlaceBufferRecorder

    init(recorder: OutOfPlaceBufferRecorder) {
        self.recorder = recorder
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        let inputSize = input.size
        let outputSize = output.size
        let outputPTS = output.pts
        let outputDuration = output.duration
        let inputBefore = try input.withUnsafeBytes { Array($0) }
        let outputBytes = SwiftBaseTransformOutOfPlaceNativeElementTests.invertedBGRA(inputBefore)

        try output.withUnsafeMutableBytes { bytes in
            let count = min(bytes.count, outputBytes.count)
            for index in 0..<count {
                bytes[index] = outputBytes[index]
            }
        }

        let inputAfter = try input.withUnsafeBytes { Array($0) }
        recorder.record(
            OutOfPlaceBufferObservation(
                inputSize: inputSize,
                outputSize: outputSize,
                outputPTS: outputPTS,
                outputDuration: outputDuration,
                inputBefore: inputBefore,
                inputAfter: inputAfter,
                outputBytes: outputBytes
            )
        )
        return .ok
    }
}

private enum OutOfPlaceCallbackFailureCase: String, CaseIterable, Sendable {
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

private struct OutOfPlaceCallbackFailureError: Error, Sendable {
    let failureCase: OutOfPlaceCallbackFailureCase
}

private final class OutOfPlaceFailureRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var startCount = 0
        var setCapsCount = 0
        var transformCount = 0

        func callbackCount(for failureCase: OutOfPlaceCallbackFailureCase) -> Int {
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

private final class FailingOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let failureCase: OutOfPlaceCallbackFailureCase
    private let recorder: OutOfPlaceFailureRecorder

    init(failureCase: OutOfPlaceCallbackFailureCase, recorder: OutOfPlaceFailureRecorder) {
        self.failureCase = failureCase
        self.recorder = recorder
    }

    func start() throws {
        recorder.recordStart()
        if failureCase == .startThrows {
            throw OutOfPlaceCallbackFailureError(failureCase: failureCase)
        }
    }

    func setCaps(input: Caps, output: Caps) throws -> Bool {
        recorder.recordSetCaps()
        switch failureCase {
        case .setCapsReturnsFalse:
            return false
        case .setCapsThrows:
            throw OutOfPlaceCallbackFailureError(failureCase: failureCase)
        default:
            return true
        }
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        recorder.recordTransform()
        switch failureCase {
        case .transformThrows:
            throw OutOfPlaceCallbackFailureError(failureCase: failureCase)
        case .transformReturnsError:
            return .error
        case .transformReturnsNotNegotiated:
            return .notNegotiated
        default:
            try copyBytes(input, into: output)
            return .ok
        }
    }
}

private enum PropertySchema {
    static let boolName = "enabled"
    static let intName = "count"
    static let doubleName = "strength"
    static let stringName = "label"
    static let enumName = "mode"
    static let propertyNames = [boolName, intName, doubleName, stringName, enumName]

    static func supportedProperties() -> [NativeElementProperty] {
        [
            .bool(name: boolName, default: true, blurb: "Enable processing"),
            .int(name: intName, default: 3, min: 0, max: 10, blurb: "Processing count"),
            .double(name: doubleName, default: 0.25, min: 0.0, max: 1.0, blurb: "Processing strength"),
            .string(name: stringName, default: nil, blurb: "Optional label"),
            .stringEnum(
                name: enumName,
                default: "balanced",
                cases: [
                    NativeElementEnumCase(name: "balanced", nick: "bal", blurb: "Balanced mode"),
                    NativeElementEnumCase(name: "fast", nick: "quick", blurb: "Fast mode"),
                ],
                blurb: "Processing mode"
            ),
        ]
    }
}

private struct PropertyObservation: Sendable {
    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringValue: String?
    var enumValue: String?

    init(reader: NativeElementPropertyReader) {
        self.boolValue = reader.bool(PropertySchema.boolName)
        self.intValue = reader.int(PropertySchema.intName)
        self.doubleValue = reader.double(PropertySchema.doubleName)
        self.stringValue = reader.string(PropertySchema.stringName)
        self.enumValue = reader.enumCase(PropertySchema.enumName)
    }
}

private struct PropertyExpectedObservation: Sendable {
    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringValue: String?
    var enumValue: String?

    static func configured(
        bool: Bool,
        int: Int,
        double: Double,
        string: String?,
        enumCase: String
    ) -> PropertyExpectedObservation {
        PropertyExpectedObservation(
            boolValue: bool,
            intValue: int,
            doubleValue: double,
            stringValue: string,
            enumValue: enumCase
        )
    }
}

private final class PropertyObservationRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var transformObservations: [PropertyObservation] = []
    }

    func recordTransform(_ observation: PropertyObservation) {
        state.withLock { $0.transformObservations.append(observation) }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class PropertyRecordingOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let reader: NativeElementPropertyReader
    private let recorder: PropertyObservationRecorder

    init(reader: NativeElementPropertyReader, recorder: PropertyObservationRecorder) {
        self.reader = reader
        self.recorder = recorder
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        recorder.recordTransform(PropertyObservation(reader: reader))
        try copyBytes(input, into: output)
        return .ok
    }
}

private final class PropertyRecordingInPlaceTransform: SwiftBaseTransformInstance {
    private let reader: NativeElementPropertyReader
    private let recorder: PropertyObservationRecorder

    init(reader: NativeElementPropertyReader, recorder: PropertyObservationRecorder) {
        self.reader = reader
        self.recorder = recorder
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        recorder.recordTransform(PropertyObservation(reader: reader))
        return .ok
    }
}

private struct SwiftBaseTransformOutOfPlaceNativeElementTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}

private enum StaticOutOfPlaceNativeElementTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not find Package.swift while walking up from \(filePath)"
        }
    }
}
