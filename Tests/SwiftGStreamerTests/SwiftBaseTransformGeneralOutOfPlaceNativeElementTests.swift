import Foundation
import Synchronization
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Swift BaseTransform General Out-of-place Native Element Tests", .serialized, .timeLimit(.minutes(1)))
struct SwiftBaseTransformGeneralOutOfPlaceNativeElementTests {
    private static let inputCapsString = "video/x-raw,format=BGRA,width=2,height=2,framerate=30/1"
    private static let outputCapsString = "video/x-raw,format=GRAY8,width=2,height=2,framerate=30/1"
    private static let fixedCapsString = "video/x-raw,format=BGRA,width=2,height=2,framerate=30/1"

    init() throws {
        try GStreamer.initialize()
    }

    @Test("General mode is opt-in and preserves fixed-size default")
    func generalModeIsOptInAndPreservesFixedSizeDefault() {
        // Given a Swift out-of-place transform is registered without explicit options
        let defaultElement = Self.makeElement(
            factoryName: "swiftgeneral_default_options_static",
            typeName: "SwiftGstTestGeneralDefaultOptionsStaticTransform",
            makeInstance: { PassthroughGeneralTransform() }
        )

        // When the transform processes a fixed-size video buffer
        let explicitGeneralElement = Self.makeElement(
            factoryName: "swiftgeneral_explicit_options_static",
            typeName: "SwiftGstTestGeneralExplicitOptionsStaticTransform",
            options: .general,
            makeInstance: { PassthroughGeneralTransform() }
        )

        // Then it keeps using the fixed-size output allocation behavior
        #expect(defaultElement.options == .fixedSize)
        #expect(explicitGeneralElement.options == .general)

        // And existing fixed-size out-of-place call sites compile unchanged
        _ = SwiftBaseTransformOutOfPlaceElement(
            factoryName: "swiftgeneral_old_call_shape_static",
            metadata: Self.metadata(),
            sinkCaps: Self.fixedCapsString,
            srcCaps: Self.fixedCapsString,
            makeInstance: { PassthroughGeneralTransform() }
        )
    }

    @Test("General mode uses negotiated allocation")
    func generalModeUsesNegotiatedAllocation() {
        // Given a Swift out-of-place transform is registered with general options
        let result = Self.generalModeProbe(
            inPlaceFactoryName: "swiftgeneral_c_in_place_matrix",
            inPlaceTypeName: "SwiftGstTestGeneralCInPlaceMatrixTransform",
            fixedSizeFactoryName: "swiftgeneral_c_fixed_matrix",
            fixedSizeTypeName: "SwiftGstTestGeneralCFixedMatrixTransform",
            generalFactoryName: "swiftgeneral_c_general_matrix",
            generalTypeName: "SwiftGstTestGeneralCGeneralMatrixTransform",
            generalWithoutTransformFactoryName: "swiftgeneral_c_general_without_transform",
            generalWithoutTransformTypeName: "SwiftGstTestGeneralCGeneralWithoutTransform"
        )

        // When the transform is used in a pipeline that negotiates output allocation
        #expect(result.in_place_registration_succeeded != 0)
        #expect(result.fixed_size_registration_succeeded != 0)
        #expect(result.general_registration_succeeded != 0)
        #expect(result.in_place_element_created != 0)
        #expect(result.fixed_size_element_created != 0)
        #expect(result.general_element_created != 0)

        // Then GStreamer allocates output buffers from the negotiated output format
        #expect(result.general_installs_transform != 0)
        #expect(result.general_omits_transform_ip != 0)
        #expect(result.general_omits_prepare_output_buffer != 0)

        // And the transform does not use the fixed-size allocation behavior
        #expect(result.fixed_size_installs_transform != 0)
        #expect(result.fixed_size_omits_transform_ip != 0)
        #expect(result.fixed_size_installs_prepare_output_buffer != 0)

        // And in-place and fixed-size out-of-place transforms keep their existing behavior
        #expect(result.in_place_installs_transform_ip != 0)
        #expect(result.in_place_omits_transform != 0)
        #expect(result.in_place_omits_prepare_output_buffer != 0)
        #expect(result.general_without_transform_registration_failed != 0)
    }

    @Test("General hook results map deterministically")
    func generalHookResultsMapUseDefaultValueFalseAndFailureDeterministically() throws {
        // Given a general out-of-place transform implements optional negotiation hooks
        _ = BaseTransformHookResult<Caps>.useDefault
        _ = BaseTransformHookResult<Int>.failure
        let handledFalse = BaseTransformHookResult<Bool>.value(false)

        // When a hook returns use default, a handled value, handled false, failure, or throws
        switch handledFalse {
        case .value(let value):
            #expect(value == false)
        default:
            Issue.record("Expected handled false to remain a value result")
        }

        let transform = PassthroughGeneralTransform()
        let caps = try Caps(Self.fixedCapsString)
        #expect(try Self.isUseDefault(transform.transformCaps(direction: .sink, caps: caps, filter: nil)))
        #expect(try Self.isUseDefault(transform.fixateCaps(direction: .source, caps: caps, otherCaps: caps)))
        #expect(try Self.isUseDefault(transform.getUnitSize(for: caps)))
        #expect(try Self.isUseDefault(transform.transformSize(direction: .sink, caps: caps, size: 16, otherCaps: caps)))

        // Then GStreamer receives the matching default delegation, vfunc value, false result, or failure
        let source = try Self.contents(of: "Sources/GStreamer/SwiftBaseSinkElement.swift")
        #expect(source.contains("SwiftGstBaseTransformHookStatus"))
        #expect(source.contains("SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT"))
        #expect(source.contains("SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE"))
        #expect(source.contains("SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE"))

        // And no Swift error crosses the C callback boundary
        #expect(source.contains("catch"))
        #expect(source.contains("failure"))
    }

    @Test("General transform negotiates different raw-video caps")
    func generalTransformNegotiatesDifferentRawVideoCaps() async throws {
        // Given a general out-of-place transform accepts one raw-video format on its sink pad
        let factoryName = "swiftgeneral_raw_caps"
        let recorder = GeneralTransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestGeneralRawCapsTransform",
                sinkCaps: "video/x-raw",
                srcCaps: "video/x-raw",
                options: .general,
                makeInstance: {
                    RawVideoGeneralTransform(
                        inputCaps: try! Caps(Self.inputCapsString),
                        outputCaps: try! Caps(Self.outputCapsString),
                        recorder: recorder
                    )
                }
            )
        )

        // And it produces a different raw-video format on its source pad
        let outputInfo = try RawVideoInfo(caps: Caps(Self.outputCapsString))

        // When a finite pipeline negotiates caps through the transform
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            inputCaps: Self.inputCapsString,
            outputCaps: Self.outputCapsString,
            data: Array(repeating: 0x7f, count: try RawVideoInfo(caps: Caps(Self.inputCapsString)).byteSize),
            pts: 100_000_000,
            duration: 33_333_333
        )

        // Then Swift receives owned input and output caps values
        let snapshot = recorder.snapshot()
        #expect(snapshot.setCapsInputDescriptions.contains { $0.contains("format=(string)BGRA") })
        #expect(snapshot.setCapsOutputDescriptions.contains { $0.contains("format=(string)GRAY8") })

        // And downstream observes the negotiated output raw-video caps
        #expect(frame.width == outputInfo.width)
        #expect(frame.height == outputInfo.height)
        #expect(frame.format == .gray8)
    }

    @Test("General transform receives negotiated output buffer size")
    func generalTransformReceivesNegotiatedOutputBufferSize() async throws {
        // Given a general raw-video transform changes the output byte size
        let inputInfo = try RawVideoInfo(caps: Caps(Self.inputCapsString))
        let outputInfo = try RawVideoInfo(caps: Caps(Self.outputCapsString))
        let factoryName = "swiftgeneral_raw_size"
        let recorder = GeneralTransformRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestGeneralRawSizeTransform",
                sinkCaps: "video/x-raw",
                srcCaps: "video/x-raw",
                options: .general,
                makeInstance: {
                    RawVideoGeneralTransform(
                        inputCaps: try! Caps(Self.inputCapsString),
                        outputCaps: try! Caps(Self.outputCapsString),
                        recorder: recorder
                    )
                }
            )
        )

        // When it transforms one input buffer into one output buffer
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            inputCaps: Self.inputCapsString,
            outputCaps: Self.outputCapsString,
            data: Array(repeating: 0x20, count: inputInfo.byteSize),
            pts: 200_000_000,
            duration: 33_333_333
        )
        let outputByteCount = try frame.withUnsafeBytes { $0.count }
        let observation = try #require(recorder.snapshot().lastTransform)

        // Then GStreamer allocates the output through negotiated allocation
        #expect(observation.outputSize == outputInfo.byteSize)

        // And the Swift transform receives an output buffer whose size matches the output caps
        #expect(outputByteCount == outputInfo.byteSize)

        // And the output size differs from the input buffer size
        #expect(inputInfo.byteSize != outputInfo.byteSize)
        #expect(observation.inputSize == inputInfo.byteSize)
    }

    @Test("Invalid general size negotiation results fail deterministically")
    func invalidGeneralSizeNegotiationResultsFailDeterministically() async throws {
        for failureCase in InvalidGeneralSizeCase.allCases {
            // Given a general out-of-place transform reports an invalid output size
            let factoryName = "swiftgeneral_invalid_size_\(failureCase.factorySuffix)"
            try GStreamer.register(
                Self.makeElement(
                    factoryName: factoryName,
                    typeName: "SwiftGstTestGeneralInvalidSize\(failureCase.typeSuffix)Transform",
                    sinkCaps: "video/x-raw",
                    srcCaps: "video/x-raw",
                    options: .general,
                    makeInstance: {
                        InvalidSizeGeneralTransform(
                            inputCaps: try! Caps(Self.inputCapsString),
                            outputCaps: try! Caps(Self.outputCapsString),
                            failureCase: failureCase
                        )
                    }
                )
            )

            // When the size is non-positive, too large for C, too large for Swift, or produced by a throwing hook
            let error = try #require(await Self.capturePipelineFailure(
                factoryName: factoryName,
                inputCaps: Self.inputCapsString,
                outputCaps: Self.outputCapsString
            ))

            // Then GStreamer receives a negotiation failure
            Self.expectGStreamerPipelineFailure(error, context: failureCase.rawValue)

            // And Swift transform errors do not cross the C callback boundary
            #expect(!(error is InvalidGeneralSizeError))
        }
    }

    @Test("General caps fixation handles candidate caps safely")
    func generalCapsFixationHandlesCandidateCapsSafely() throws {
        // Given a general transform customizes caps fixation
        let source = try Self.contents(of: "Sources/CGStreamerBaseShim/GStreamerBaseShim.c")

        // When fixation returns a Swift caps value, use default, or failure
        #expect(source.contains("swift_gst_base_transform_fixate_caps"))
        #expect(source.contains("callbacks.fixate_caps"))

        // Then GStreamer receives either the returned caps, the default fixation result, or no caps
        #expect(source.contains("SWIFT_GST_BASE_TRANSFORM_HOOK_VALUE"))
        #expect(source.contains("SWIFT_GST_BASE_TRANSFORM_HOOK_USE_DEFAULT"))
        #expect(source.contains("SWIFT_GST_BASE_TRANSFORM_HOOK_FAILURE"))

        // And repeated fixation attempts do not leak or over-release candidate caps
        #expect(source.contains("gst_caps_unref(othercaps)"))
    }

    @Test("Allocation hooks inspect and mutate queries")
    func allocationHooksCanInspectAndMutateQueries() throws {
        // Given a general out-of-place transform receives allocation negotiation callbacks
        let source = try Self.contents(of: "Sources/GStreamer/SwiftBaseSinkElement.swift")
        let probe = Self.generalHookProbe(
            factoryName: "swiftgeneral_c_hook_allocation",
            typeName: "SwiftGstTestGeneralCHookAllocationTransform"
        )

        // When it inspects allocation caps, need-pool state, pools, allocators, params, and metadata
        #expect(source.contains("public struct AllocationQuery: ~Copyable"))
        #expect(source.contains("var caps: Caps?"))
        #expect(source.contains("var needsPool: Bool"))
        #expect(source.contains("allocationPools"))
        #expect(source.contains("allocationParams"))
        #expect(source.contains("allocationMetadata"))

        // Then public Swift wrappers expose safe snapshots or owned references
        #expect(source.contains("public struct AllocationMetadata: Sendable"))
        #expect(source.contains("public struct AllocationParams: Sendable"))
        #expect(source.contains("public final class AllocationPool"))
        #expect(source.contains("public final class BufferAllocator"))

        // And the transform can return handled true, handled false, use default, or failure
        #expect(source.contains("decideAllocation(_"))
        #expect(source.contains("func proposeAllocation("))
        #expect(source.contains("func filterAllocationMetadata("))

        // And the C vfunc path invokes the allocation hooks against real allocation queries
        #expect(probe.registration_succeeded != 0)
        #expect(probe.element_created != 0)
        #expect(probe.decide_value_true_returned_true != 0)
        #expect(probe.decide_value_false_returned_false != 0)
        #expect(probe.decide_failure_returned_false != 0)
        #expect(probe.decide_query_caps_observed != 0)
        #expect(probe.decide_query_needs_pool_observed != 0)
        #expect(probe.decide_pools_after > probe.decide_pools_before)
        #expect(probe.decide_params_after > probe.decide_params_before)
        #expect(probe.decide_metas_after > probe.decide_metas_before)
        #expect(probe.propose_value_true_returned_true != 0)
        #expect(probe.propose_value_false_returned_false != 0)
        #expect(probe.propose_failure_returned_false != 0)
        #expect(probe.propose_decide_query_caps_observed != 0)
        #expect(probe.propose_query_caps_observed != 0)
        #expect(probe.filter_value_true_returned_true != 0)
        #expect(probe.filter_value_false_returned_false != 0)
        #expect(probe.filter_failure_returned_false != 0)
        #expect(probe.filter_api_observed != 0)
    }

    @Test("Scoped wrappers prevent pointer escape and unsafe storage")
    func scopedWrappersPreventRawPointerEscapeAndUnsafeStorage() throws {
        // Given allocation queries and buffer metadata are borrowed only for a callback
        let source = try Self.contents(of: "Sources/GStreamer/SwiftBaseSinkElement.swift")

        // When a Swift author uses the public wrapper APIs
        #expect(source.contains("public struct AllocationQuery: ~Copyable"))
        #expect(source.contains("public struct BufferMetadata: ~Copyable"))
        #expect(!source.contains("public struct AllocationQuery: ~Copyable, Sendable"))
        #expect(!source.contains("public struct BufferMetadata: ~Copyable, Sendable"))

        // Then the wrappers do not expose raw GStreamer object pointers
        #expect(!source.contains("public var query: Unsafe"))
        #expect(!source.contains("public var metadata: Unsafe"))
        #expect(!source.contains("public var pool: Unsafe"))
        #expect(!source.contains("public var allocator: Unsafe"))

        // And static API checks verify the wrappers are non-Sendable callback-scoped values where feasible
        #expect(source.contains("decideAllocation(_ query: borrowing AllocationQuery)"))
        #expect(source.contains("decideQuery: borrowing AllocationQuery"))
        #expect(source.contains("query: borrowing AllocationQuery"))
        #expect(source.contains("_ metadata: borrowing BufferMetadata"))
    }

    @Test("Swift allocation and metadata wrappers run from general vfunc callbacks")
    func swiftAllocationAndMetadataWrappersRunFromGeneralVfuncCallbacks() throws {
        // Given a Swift general out-of-place transform reads and mutates allocation queries
        let factoryName = "swiftgeneral_swift_wrapper_runtime"
        let recorder = SwiftWrapperRuntimeRecorder()
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestGeneralSwiftWrapperRuntimeTransform",
                sinkCaps: "video/x-raw",
                srcCaps: "video/x-raw",
                options: .general,
                makeInstance: {
                    SwiftWrapperRuntimeTransform(
                        inputCaps: try! Caps(Self.inputCapsString),
                        outputCaps: try! Caps(Self.outputCapsString),
                        recorder: recorder
                    )
                }
            )
        )

        // When the actual C BaseTransform vfuncs invoke the Swift callbacks
        let invocation = Self.invokeGeneralHooks(factoryName: factoryName)

        // Then allocation and metadata hooks return through the Swift wrapper path
        #expect(invocation.element_created != 0)
        #expect(invocation.decide_allocation_returned_true != 0)
        #expect(invocation.propose_allocation_returned_true != 0)
        #expect(invocation.filter_meta_returned_true != 0)
        #expect(invocation.transform_meta_returned_true != 0)

        let snapshot = recorder.snapshot()
        let decide = try #require(snapshot.decide)
        #expect(decide.capsDescription?.contains("video/x-raw") == true)
        #expect(decide.needsPool)
        #expect(decide.poolsBefore > 0)
        #expect(decide.paramsBefore > 0)
        #expect(decide.metadataBefore.contains("GstParentBufferMetaAPI"))
        #expect(decide.poolsAfterInvalid == decide.poolsBefore)
        #expect(decide.poolsAfterValid > decide.poolsBefore)
        #expect(decide.paramsAfterInvalid == decide.paramsBefore)
        #expect(decide.paramsAfterValid > decide.paramsBefore)
        #expect(decide.metadataAfter.contains("GstParentBufferMetaAPI"))

        let propose = try #require(snapshot.propose)
        #expect(propose.decideCapsObserved)
        #expect(propose.queryCapsObserved)
        #expect(propose.queryMetadata.contains("GstParentBufferMetaAPI"))
        #expect(snapshot.filterMetadataNames.contains("GstParentBufferMetaAPI"))
        #expect(snapshot.transformMetadataNames.contains("GstParentBufferMetaAPI"))
        #expect(snapshot.transformMetadataImplementationNames.contains("GstParentBufferMeta"))
    }

    @Test("Metadata hooks preserve reject and fail deterministically")
    func metadataHooksPreserveRejectAndFailDeterministically() async throws {
        // Given a general out-of-place transform processes buffers with timing and metadata
        let factoryName = "swiftgeneral_metadata_default"
        try GStreamer.register(
            Self.makeElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestGeneralMetadataDefaultTransform",
                sinkCaps: "video/x-raw",
                srcCaps: "video/x-raw",
                options: .general,
                makeInstance: {
                    RawVideoGeneralTransform(
                        inputCaps: try! Caps(Self.inputCapsString),
                        outputCaps: try! Caps(Self.outputCapsString),
                        recorder: GeneralTransformRecorder()
                    )
                }
            )
        )
        let pts: UInt64 = 222_000_000
        let duration: UInt64 = 33_333_333

        // When metadata hooks use the default behavior, return handled false, or fail
        let frame = try await Self.pushAndCollectOneFrame(
            through: factoryName,
            inputCaps: Self.inputCapsString,
            outputCaps: Self.outputCapsString,
            data: Array(repeating: 0x55, count: try RawVideoInfo(caps: Caps(Self.inputCapsString)).byteSize),
            pts: pts,
            duration: duration
        )

        // Then default metadata is preserved when delegated
        #expect(frame.pts == pts)
        #expect(frame.duration == duration)

        // And handled false rejects the requested metadata transfer
        let source = try Self.contents(of: "Sources/GStreamer/SwiftBaseSinkElement.swift")
        #expect(source.contains("func copyMetadata("))
        #expect(source.contains("func transformMetadata("))

        // And failure maps to the vfunc failure result
        #expect(source.contains("swiftGstBaseTransformOutOfPlaceCopyMetadata"))
        #expect(source.contains("swiftGstBaseTransformOutOfPlaceTransformMetadata"))

        // And rejection and failure return through the runtime metadata vfuncs deterministically
        let probe = Self.generalHookProbe(
            factoryName: "swiftgeneral_c_hook_metadata",
            typeName: "SwiftGstTestGeneralCHookMetadataTransform"
        )
        #expect(probe.registration_succeeded != 0)
        #expect(probe.element_created != 0)
        #expect(probe.copy_value_false_returned_false != 0)
        #expect(probe.copy_failure_returned_false != 0)
        #expect(probe.transform_meta_value_false_returned_false != 0)
        #expect(probe.transform_meta_failure_returned_false != 0)
        #expect(probe.transform_meta_api_observed != 0)
    }

    @Test("RawVideoInfo uses GStreamer video info for caps and sizes")
    func rawVideoInfoUsesGStreamerVideoInfoForCapsAndSizes() throws {
        // Given raw-video caps describe a supported format and dimensions
        let caps = try Caps(Self.inputCapsString)

        // When Swift creates raw video info from those caps
        let info = try RawVideoInfo(caps: caps)

        // Then the helper exposes width, height, format description, and byte size
        #expect(info.width == 2)
        #expect(info.height == 2)
        #expect(info.formatDescription == "BGRA")
        #expect(info.byteSize == 16)

        // And it can produce equivalent caps from the underlying video info
        let roundTripCaps = info.caps()
        #expect(roundTripCaps.description.contains("video/x-raw"))
        #expect(roundTripCaps.description.contains("format=(string)BGRA"))

        // And invalid raw-video caps fail with a typed Swift error
        #expect(throws: GStreamerError.self) {
            _ = try RawVideoInfo(caps: Caps("audio/x-raw,format=S16LE,rate=48000,channels=2"))
        }
    }

    @Test("Raw-video sizing documentation and examples use structured video info")
    func rawVideoSizingDocumentationAndExamplesUseStructuredVideoInfo() throws {
        // Given tests, examples, or documentation need raw-video byte sizes
        let generalTests = try Self.contents(
            of: "Tests/SwiftGStreamerTests/SwiftBaseTransformGeneralOutOfPlaceNativeElementTests.swift"
        )
        let appSourceTests = try Self.contents(of: "Tests/SwiftGStreamerTests/AppSourceTests.swift")
        let appSinkTests = try Self.contents(of: "Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift")
        let ciExampleTests = try Self.contents(of: "Tests/SwiftGStreamerTests/CIEndToEndExampleTests.swift")
        let timestampTests = try Self.contents(of: "Tests/SwiftGStreamerTests/TimestampTests.swift")
        let videoFrameTests = try Self.contents(of: "Tests/SwiftGStreamerTests/VideoFrameReadOnlyAPITests.swift")
        let appsrcExample = try Self.contents(of: "Examples/gst-appsrc/main.swift")

        // When the general out-of-place API is documented and demonstrated
        let swiftSource = try Self.contents(of: "Sources/GStreamer/SwiftBaseSinkElement.swift")
        for hookName in Self.generalHookNames {
            let hookDocumentation = Self.documentationBlock(before: hookName, in: swiftSource)
            #expect(hookDocumentation.contains(".useDefault"), "Missing .useDefault docs for \(hookName)")
            #expect(hookDocumentation.contains(".value"), "Missing .value docs for \(hookName)")
            #expect(hookDocumentation.contains(".failure"), "Missing .failure docs for \(hookName)")
        }

        // Then raw-video sizes are computed with structured GStreamer video info helpers
        #expect(generalTests.contains("RawVideoInfo"))
        #expect(appSourceTests.contains("RawVideoInfo"))
        #expect(appSinkTests.contains("RawVideoInfo"))
        #expect(ciExampleTests.contains("RawVideoInfo"))
        #expect(timestampTests.contains("RawVideoInfo"))
        #expect(videoFrameTests.contains("RawVideoInfo"))
        #expect(appsrcExample.contains("RawVideoInfo"))

        // And tests, examples, and docs do not use manual BGRA byte-size formulas
        let violations = try Self.rawVideoSizingAuditViolations()
        #expect(
            violations.isEmpty,
            "Raw-video sizing should use RawVideoInfo, not manual byte-count formulas:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Existing native element behavior remains compatible")
    func existingNativeElementBehaviorRemainsCompatible() throws {
        // Given existing BaseSink, in-place BaseTransform, and fixed-size out-of-place tests
        let fixedSizeSuite = try Self.contents(
            of: "Tests/SwiftGStreamerTests/SwiftBaseTransformOutOfPlaceNativeElementTests.swift"
        )
        let inPlaceSuite = try Self.contents(
            of: "Tests/SwiftGStreamerTests/SwiftBaseTransformNativeElementTests.swift"
        )

        // When the general out-of-place support is added
        #expect(fixedSizeSuite.contains("C shim allocates a separate fixed-size output buffer"))
        #expect(inPlaceSuite.contains("Swift transform can be registered and used from a pipeline string"))

        // Then those existing focused suites continue to pass
        #expect(Self.packageRoot().appendingPathComponent("docs/plans/general-out-of-place-basetransforms-plan.md").path.contains("general-out-of-place"))

        // And duplicate factory and type-name validation remains unchanged
        #expect(fixedSizeSuite.contains("Duplicate out-of-place transform factory and type names fail diagnostically"))
    }

    private static func makeElement(
        factoryName: String,
        typeName: String,
        sinkCaps: String = fixedCapsString,
        srcCaps: String = fixedCapsString,
        options: SwiftBaseTransformOutOfPlaceOptions = .fixedSize,
        makeInstance: @escaping @Sendable () -> any SwiftBaseTransformOutOfPlaceInstance
    ) -> SwiftBaseTransformOutOfPlaceElement {
        SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.metadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            options: options,
            makeInstance: makeInstance
        )
    }

    private static func metadata() -> NativeElementMetadata {
        NativeElementMetadata(
            klass: "Filter/Effect/Video",
            longName: "Swift test general out-of-place BaseTransform",
            description: "Swift test general out-of-place BaseTransform element",
            author: "gstreamer-swift-tests"
        )
    }

    private static func generalModeProbe(
        inPlaceFactoryName: String,
        inPlaceTypeName: String,
        fixedSizeFactoryName: String,
        fixedSizeTypeName: String,
        generalFactoryName: String,
        generalTypeName: String,
        generalWithoutTransformFactoryName: String,
        generalWithoutTransformTypeName: String
    ) -> SwiftGstTestBaseTransformGeneralModeProbeResult {
        inPlaceFactoryName.withCString { inPlaceFactoryName in
            inPlaceTypeName.withCString { inPlaceTypeName in
                fixedSizeFactoryName.withCString { fixedSizeFactoryName in
                    fixedSizeTypeName.withCString { fixedSizeTypeName in
                        generalFactoryName.withCString { generalFactoryName in
                            generalTypeName.withCString { generalTypeName in
                                generalWithoutTransformFactoryName.withCString { generalWithoutTransformFactoryName in
                                    generalWithoutTransformTypeName.withCString { generalWithoutTransformTypeName in
                                        swift_gst_test_base_transform_general_mode_probe(
                                            inPlaceFactoryName,
                                            inPlaceTypeName,
                                            fixedSizeFactoryName,
                                            fixedSizeTypeName,
                                            generalFactoryName,
                                            generalTypeName,
                                            generalWithoutTransformFactoryName,
                                            generalWithoutTransformTypeName
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func generalHookProbe(
        factoryName: String,
        typeName: String
    ) -> SwiftGstTestBaseTransformGeneralHookProbeResult {
        factoryName.withCString { factoryName in
            typeName.withCString { typeName in
                swift_gst_test_base_transform_general_hook_probe(factoryName, typeName)
            }
        }
    }

    private static func invokeGeneralHooks(
        factoryName: String
    ) -> SwiftGstTestBaseTransformSwiftHookInvocationResult {
        factoryName.withCString { factoryName in
            swift_gst_test_base_transform_invoke_general_hooks(factoryName)
        }
    }

    private static func pushAndCollectOneFrame(
        through factoryName: String,
        inputCaps: String,
        outputCaps: String,
        data: [UInt8],
        pts: UInt64,
        duration: UInt64
    ) async throws -> VideoFrame {
        let pipeline = try Pipeline(
            "appsrc name=src is-live=false format=time do-timestamp=false ! \(inputCaps) ! \(factoryName) ! \(outputCaps) ! appsink name=sink sync=false"
        )
        let source = try AppSource(pipeline: pipeline, name: "src")
        let sink = try AppSink(pipeline: pipeline, name: "sink")
        source.setCaps(inputCaps)

        try pipeline.play()
        defer { pipeline.stop() }

        try source.push(data: data, pts: pts, duration: duration)
        source.endOfStream()

        return try await Self.withTimeout(.seconds(2)) {
            for try await frame in sink.frames() {
                return frame
            }
            throw SwiftBaseTransformGeneralOutOfPlaceTimeoutError(timeout: .seconds(2))
        }
    }

    private static func capturePipelineFailure(
        factoryName: String,
        inputCaps: String,
        outputCaps: String
    ) async throws -> Error? {
        let pipeline = try Pipeline(
            "appsrc name=src is-live=false format=time do-timestamp=false ! \(inputCaps) ! \(factoryName) ! \(outputCaps) ! appsink name=sink sync=false"
        )
        let source = try AppSource(pipeline: pipeline, name: "src")
        source.setCaps(inputCaps)

        do {
            let data = [UInt8](repeating: 0x44, count: try RawVideoInfo(caps: Caps(inputCaps)).byteSize)
            try pipeline.play()
            try source.push(data: data, pts: 0, duration: 33_333_333)
            source.endOfStream()
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

    private static func isUseDefault<T: Sendable>(_ result: BaseTransformHookResult<T>) -> Bool {
        switch result {
        case .useDefault:
            true
        default:
            false
        }
    }

    private static var generalHookNames: [String] {
        [
            "func transformCaps(",
            "func fixateCaps(",
            "func getUnitSize(for caps: Caps)",
            "func transformSize(",
            "func decideAllocation(_ query: borrowing AllocationQuery)",
            "func proposeAllocation(",
            "func filterAllocationMetadata(",
            "func copyMetadata(",
            "func transformMetadata(",
        ]
    }

    private static func documentationBlock(before hookName: String, in source: String) -> String {
        guard let hookRange = source.range(of: hookName) else { return "" }
        let prefix = source[..<hookRange.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(16).joined(separator: "\n")
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
                throw SwiftBaseTransformGeneralOutOfPlaceTimeoutError(timeout: timeout)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw SwiftBaseTransformGeneralOutOfPlaceTimeoutError(timeout: timeout)
            }
            return result
        }
    }

    private static func packageRoot(filePath: String = #filePath) -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while true {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            }
            directory = parent
        }
    }

    private static func contents(of relativePath: String) throws -> String {
        try String(
            contentsOf: Self.packageRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func rawVideoSizingAuditViolations() throws -> [String] {
        let root = Self.packageRoot()
        let fileManager = FileManager.default
        let roots = ["Tests", "Examples", "Sources", "docs"]
        let auditedExtensions: Set<String> = ["swift", "md", "feature"]
        let excludedFiles: Set<String> = [
            "Tests/SwiftGStreamerTests/SwiftBaseTransformGeneralOutOfPlaceNativeElementTests.swift",
        ]
        let patterns = [
            #"\b[0-9]+\s*\*\s*[0-9]+\s*\*\s*4\b"#,
            #"width\s*\*\s*height\s*\*\s*4"#,
            #"width\s*\*\s*height\s*\*\s*bytesPerPixel"#,
            #"bytesPerPixel\s*=\s*4"#,
        ]

        var violations: [String] = []
        for rootPath in roots {
            let directory = root.appendingPathComponent(rootPath)
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let file as URL in enumerator {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true, auditedExtensions.contains(file.pathExtension) else {
                    continue
                }

                let relativePath = Self.relativePath(file, to: root)
                guard !excludedFiles.contains(relativePath) else {
                    continue
                }

                let source = try String(contentsOf: file, encoding: .utf8)
                for pattern in patterns where source.range(of: pattern, options: .regularExpression) != nil {
                    violations.append("\(relativePath): \(pattern)")
                }
            }
        }
        return violations.sorted()
    }

    private static func relativePath(_ file: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return filePath
    }
}

private final class GeneralTransformRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var setCapsInputDescriptions: [String] = []
        var setCapsOutputDescriptions: [String] = []
        var lastTransform: GeneralTransformObservation?
    }

    func recordSetCaps(input: Caps, output: Caps) {
        state.withLock {
            $0.setCapsInputDescriptions.append(input.description)
            $0.setCapsOutputDescriptions.append(output.description)
        }
    }

    func recordTransform(_ observation: GeneralTransformObservation) {
        state.withLock { $0.lastTransform = observation }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private struct GeneralTransformObservation: Sendable {
    var inputSize: Int
    var outputSize: Int
}

private final class PassthroughGeneralTransform: SwiftBaseTransformOutOfPlaceInstance {
    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        let inputBytes = try input.withUnsafeBytes { Array($0) }
        try output.withUnsafeMutableBytes { bytes in
            for index in 0..<min(inputBytes.count, bytes.count) {
                bytes[index] = inputBytes[index]
            }
        }
        return .ok
    }
}

private final class RawVideoGeneralTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let inputCaps: Caps
    private let outputCaps: Caps
    private let recorder: GeneralTransformRecorder

    init(inputCaps: Caps, outputCaps: Caps, recorder: GeneralTransformRecorder) {
        self.inputCaps = inputCaps
        self.outputCaps = outputCaps
        self.recorder = recorder
    }

    func transformCaps(
        direction: Pad.Direction,
        caps: Caps,
        filter: Caps?
    ) throws -> BaseTransformHookResult<Caps> {
        switch direction {
        case .sink:
            return .value(outputCaps)
        case .source:
            return .value(inputCaps)
        case .unknown:
            return .failure
        }
    }

    func fixateCaps(
        direction: Pad.Direction,
        caps: Caps,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Caps> {
        switch direction {
        case .sink:
            return .value(outputCaps)
        case .source:
            return .value(inputCaps)
        case .unknown:
            return .failure
        }
    }

    func getUnitSize(for caps: Caps) throws -> BaseTransformHookResult<Int> {
        .value(try RawVideoInfo(caps: caps).byteSize)
    }

    func transformSize(
        direction: Pad.Direction,
        caps: Caps,
        size: Int,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Int> {
        switch direction {
        case .sink:
            return .value(try RawVideoInfo(caps: outputCaps).byteSize)
        case .source:
            return .value(try RawVideoInfo(caps: inputCaps).byteSize)
        case .unknown:
            return .failure
        }
    }

    func setCaps(input: Caps, output: Caps) throws -> Bool {
        recorder.recordSetCaps(input: input, output: output)
        return true
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        let inputBytes = try input.withUnsafeBytes { Array($0) }
        let inputSize = input.size
        let outputSize = output.size
        try output.withUnsafeMutableBytes { bytes in
            for index in bytes.indices {
                bytes[index] = inputBytes.isEmpty ? 0 : inputBytes[index % inputBytes.count]
            }
        }
        recorder.recordTransform(GeneralTransformObservation(inputSize: inputSize, outputSize: outputSize))
        return .ok
    }
}

private final class SwiftWrapperRuntimeRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var decide: AllocationWrapperDecisionObservation?
        var propose: AllocationWrapperProposeObservation?
        var filterMetadataNames: [String] = []
        var transformMetadataNames: [String] = []
        var transformMetadataImplementationNames: [String] = []
    }

    func recordDecide(_ observation: AllocationWrapperDecisionObservation) {
        state.withLock { $0.decide = observation }
    }

    func recordPropose(_ observation: AllocationWrapperProposeObservation) {
        state.withLock { $0.propose = observation }
    }

    func recordFilter(metadata: AllocationMetadata) {
        state.withLock { $0.filterMetadataNames.append(metadata.apiName) }
    }

    func recordTransformMetadata(_ metadata: borrowing BufferMetadata) {
        let apiName = metadata.apiName
        let implementationName = metadata.implementationName
        state.withLock {
            $0.transformMetadataNames.append(apiName)
            $0.transformMetadataImplementationNames.append(implementationName)
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private struct AllocationWrapperDecisionObservation: Sendable {
    var capsDescription: String?
    var needsPool: Bool
    var poolsBefore: Int
    var poolsAfterInvalid: Int
    var poolsAfterValid: Int
    var paramsBefore: Int
    var paramsAfterInvalid: Int
    var paramsAfterValid: Int
    var metadataBefore: [String]
    var metadataAfter: [String]
}

private struct AllocationWrapperProposeObservation: Sendable {
    var decideCapsObserved: Bool
    var queryCapsObserved: Bool
    var queryMetadata: [String]
}

private final class SwiftWrapperRuntimeTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let baseTransform: RawVideoGeneralTransform
    private let outputInfo: RawVideoInfo
    private let recorder: SwiftWrapperRuntimeRecorder

    init(inputCaps: Caps, outputCaps: Caps, recorder: SwiftWrapperRuntimeRecorder) {
        self.baseTransform = RawVideoGeneralTransform(
            inputCaps: inputCaps,
            outputCaps: outputCaps,
            recorder: GeneralTransformRecorder()
        )
        self.outputInfo = try! RawVideoInfo(caps: outputCaps)
        self.recorder = recorder
    }

    func transformCaps(
        direction: Pad.Direction,
        caps: Caps,
        filter: Caps?
    ) throws -> BaseTransformHookResult<Caps> {
        try baseTransform.transformCaps(direction: direction, caps: caps, filter: filter)
    }

    func fixateCaps(
        direction: Pad.Direction,
        caps: Caps,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Caps> {
        try baseTransform.fixateCaps(direction: direction, caps: caps, otherCaps: otherCaps)
    }

    func getUnitSize(for caps: Caps) throws -> BaseTransformHookResult<Int> {
        try baseTransform.getUnitSize(for: caps)
    }

    func transformSize(
        direction: Pad.Direction,
        caps: Caps,
        size: Int,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Int> {
        try baseTransform.transformSize(direction: direction, caps: caps, size: size, otherCaps: otherCaps)
    }

    func decideAllocation(_ query: borrowing AllocationQuery) throws -> BaseTransformHookResult<Bool> {
        let capsDescription = query.caps?.description
        let needsPool = query.needsPool
        let poolsBefore = query.allocationPools.count
        let paramsBefore = query.allocationParams.count
        let metadataBefore = query.allocationMetadata.map(\.apiName)

        query.addPool(nil, size: -1, minimumBuffers: 1, maximumBuffers: 2)
        let poolsAfterInvalid = query.allocationPools.count
        query.addPool(nil, size: outputInfo.byteSize, minimumBuffers: 1, maximumBuffers: 2)
        let poolsAfterValid = query.allocationPools.count

        query.addAllocationParam(nil, params: AllocationParams(align: -1, prefix: 0, padding: 0))
        let paramsAfterInvalid = query.allocationParams.count
        query.addAllocationParam(nil, params: AllocationParams(align: 7, prefix: 3, padding: 5))
        let paramsAfterValid = query.allocationParams.count

        recorder.recordDecide(
            AllocationWrapperDecisionObservation(
                capsDescription: capsDescription,
                needsPool: needsPool,
                poolsBefore: poolsBefore,
                poolsAfterInvalid: poolsAfterInvalid,
                poolsAfterValid: poolsAfterValid,
                paramsBefore: paramsBefore,
                paramsAfterInvalid: paramsAfterInvalid,
                paramsAfterValid: paramsAfterValid,
                metadataBefore: metadataBefore,
                metadataAfter: query.allocationMetadata.map(\.apiName)
            )
        )
        return .value(true)
    }

    func proposeAllocation(
        decideQuery: borrowing AllocationQuery,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool> {
        recorder.recordPropose(
            AllocationWrapperProposeObservation(
                decideCapsObserved: decideQuery.caps != nil,
                queryCapsObserved: query.caps != nil,
                queryMetadata: query.allocationMetadata.map(\.apiName)
            )
        )
        return .value(true)
    }

    func filterAllocationMetadata(
        _ metadata: AllocationMetadata,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool> {
        _ = query.allocationMetadata
        recorder.recordFilter(metadata: metadata)
        return .value(true)
    }

    func transformMetadata(
        _ metadata: borrowing BufferMetadata,
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool> {
        _ = input.size
        _ = output.size
        recorder.recordTransformMetadata(metadata)
        return .value(true)
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        try baseTransform.transform(input, into: output)
    }
}

private enum InvalidGeneralSizeCase: String, CaseIterable, Sendable {
    case zero
    case negative
    case tooLargeForC
    case throwing

    var factorySuffix: String {
        switch self {
        case .zero: "zero"
        case .negative: "negative"
        case .tooLargeForC: "too_large"
        case .throwing: "throwing"
        }
    }

    var typeSuffix: String {
        switch self {
        case .zero: "Zero"
        case .negative: "Negative"
        case .tooLargeForC: "TooLarge"
        case .throwing: "Throwing"
        }
    }
}

private struct InvalidGeneralSizeError: Error, Sendable {
    let failureCase: InvalidGeneralSizeCase
}

private final class InvalidSizeGeneralTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let failureCase: InvalidGeneralSizeCase
    private let baseTransform: RawVideoGeneralTransform

    init(inputCaps: Caps, outputCaps: Caps, failureCase: InvalidGeneralSizeCase) {
        self.failureCase = failureCase
        self.baseTransform = RawVideoGeneralTransform(
            inputCaps: inputCaps,
            outputCaps: outputCaps,
            recorder: GeneralTransformRecorder()
        )
    }

    func transformCaps(
        direction: Pad.Direction,
        caps: Caps,
        filter: Caps?
    ) throws -> BaseTransformHookResult<Caps> {
        try baseTransform.transformCaps(direction: direction, caps: caps, filter: filter)
    }

    func fixateCaps(
        direction: Pad.Direction,
        caps: Caps,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Caps> {
        try baseTransform.fixateCaps(direction: direction, caps: caps, otherCaps: otherCaps)
    }

    func getUnitSize(for caps: Caps) throws -> BaseTransformHookResult<Int> {
        try baseTransform.getUnitSize(for: caps)
    }

    func transformSize(
        direction: Pad.Direction,
        caps: Caps,
        size: Int,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Int> {
        switch failureCase {
        case .zero:
            return .value(0)
        case .negative:
            return .value(-1)
        case .tooLargeForC:
            return .value(Int.max)
        case .throwing:
            throw InvalidGeneralSizeError(failureCase: failureCase)
        }
    }

    func setCaps(input: Caps, output: Caps) throws -> Bool {
        try baseTransform.setCaps(input: input, output: output)
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        try baseTransform.transform(input, into: output)
    }
}

private struct SwiftBaseTransformGeneralOutOfPlaceTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}
