import Foundation
import Synchronization
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Static Plugin Grouping Tests", .serialized, .timeLimit(.minutes(2)))
struct StaticPluginGroupingTests {
    private static let videoCaps = "video/x-raw,format=RGB,width=2,height=2,framerate=1/1"

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Static plugin group registers every supported native element kind")
    func staticPluginGroupRegistersEverySupportedNativeElementKind() async throws {
        // Given a Swift static plugin group contains a BaseSink, an in-place BaseTransform, a fixed-size out-of-place BaseTransform, and a general out-of-place BaseTransform
        let plugin = StaticPluginTestMetadata.valid(name: "swift_static_all_kinds")
        let sinkCounter = StaticPluginCounter()
        let inPlaceCounter = StaticPluginCounter()
        let fixedCounter = StaticPluginCounter()
        let generalCounter = StaticPluginCounter()
        let sinkFactory = "swift_static_all_kinds_sink"
        let inPlaceFactory = "swift_static_all_kinds_in_place"
        let fixedFactory = "swift_static_all_kinds_fixed"
        let generalFactory = "swift_static_all_kinds_general"

        // When the user registers the group with valid static plugin metadata
        try GStreamer.registerStaticPlugin(
            name: plugin.name,
            description: plugin.pluginDescription,
            version: plugin.version,
            license: plugin.license,
            source: plugin.source,
            package: plugin.package,
            origin: plugin.origin
        ) {
            Self.makeSink(
                factoryName: sinkFactory,
                typeName: "SwiftGstStaticAllKindsSink",
                counter: sinkCounter
            )
            Self.makeInPlaceTransform(
                factoryName: inPlaceFactory,
                typeName: "SwiftGstStaticAllKindsInPlaceTransform",
                counter: inPlaceCounter
            )
            Self.makeFixedOutOfPlaceTransform(
                factoryName: fixedFactory,
                typeName: "SwiftGstStaticAllKindsFixedTransform",
                counter: fixedCounter
            )
            Self.makeGeneralOutOfPlaceTransform(
                factoryName: generalFactory,
                typeName: "SwiftGstStaticAllKindsGeneralTransform",
                counter: generalCounter
            )
        }

        // Then each grouped factory can be created by factory name in the current process
        #expect(Self.elementFactoryExists(sinkFactory))
        #expect(Self.elementFactoryExists(inPlaceFactory))
        #expect(Self.elementFactoryExists(fixedFactory))
        #expect(Self.elementFactoryExists(generalFactory))

        // And finite pipeline strings can use the grouped factories
        try await Self.runFiniteVideoPipeline("videotestsrc num-buffers=3 ! \(Self.videoCaps) ! \(sinkFactory)")
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=3 ! \(Self.videoCaps) ! \(inPlaceFactory) ! fakesink sync=false"
        )
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=3 ! \(Self.videoCaps) ! \(fixedFactory) ! fakesink sync=false"
        )
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=3 ! \(Self.videoCaps) ! \(generalFactory) ! \(Self.videoCaps) ! fakesink sync=false"
        )
        #expect(sinkCounter.value == 3)
        #expect(inPlaceCounter.value == 3)
        #expect(fixedCounter.value == 3)
        #expect(generalCounter.value == 3)
    }

    @Test("Builder accepts direct native element expressions and control flow")
    func builderAcceptsDirectNativeElementExpressionsAndControlFlow() throws {
        // Given a Swift user has native element definitions for related factories
        let plugin = StaticPluginTestMetadata.valid(name: "swift_static_builder")
        let optionalSink: SwiftBaseSinkElement? = Self.makeSink(
            factoryName: "swift_static_builder_optional_sink",
            typeName: "SwiftGstStaticBuilderOptionalSink"
        )
        let useFirstBranch = false
        let loopFactories = [
            "swift_static_builder_loop_sink_0",
            "swift_static_builder_loop_sink_1",
        ]

        // When the user lists direct element expressions, optional entries, conditional branches, and looped entries in the static plugin builder
        let entries = Self.pluginEntries {
            Self.makeSink(
                factoryName: "swift_static_builder_direct_sink",
                typeName: "SwiftGstStaticBuilderDirectSink"
            )
            Self.makeInPlaceTransform(
                factoryName: "swift_static_builder_direct_transform",
                typeName: "SwiftGstStaticBuilderDirectTransform"
            )
            if let optionalSink {
                optionalSink
            }
            if useFirstBranch {
                Self.makeFixedOutOfPlaceTransform(
                    factoryName: "swift_static_builder_first_branch",
                    typeName: "SwiftGstStaticBuilderFirstBranchTransform"
                )
            } else {
                Self.makeGeneralOutOfPlaceTransform(
                    factoryName: "swift_static_builder_second_branch",
                    typeName: "SwiftGstStaticBuilderSecondBranchTransform"
                )
            }
            for (index, factoryName) in loopFactories.enumerated() {
                Self.makeSink(
                    factoryName: factoryName,
                    typeName: "SwiftGstStaticBuilderLoopSink\(index)"
                )
            }
        }

        // Then the builder produces native plugin entries without manual wrapping for the direct element expressions
        Self.expectSendable(entries[0])
        #expect(entries.map(\.staticPluginTestFactoryName) == [
            "swift_static_builder_direct_sink",
            "swift_static_builder_direct_transform",
            "swift_static_builder_optional_sink",
            "swift_static_builder_second_branch",
            "swift_static_builder_loop_sink_0",
            "swift_static_builder_loop_sink_1",
        ])

        // And entries from the optional, conditional, and looped builder branches are preserved
        #expect(entries.contains { $0.staticPluginTestFactoryName == "swift_static_builder_optional_sink" })
        #expect(entries.contains { $0.staticPluginTestFactoryName == "swift_static_builder_second_branch" })
        #expect(loopFactories.allSatisfy { factoryName in
            entries.contains { $0.staticPluginTestFactoryName == factoryName }
        })

        // And the static plugin API accepts the produced entries
        try Self.registerStaticPlugin(plugin, entries: entries)
        for entry in entries {
            #expect(Self.elementFactoryExists(entry.staticPluginTestFactoryName))
        }
    }

    @Test("Known invalid static plugin input fails before registration starts")
    func knownInvalidStaticPluginInputFailsBeforeRegistrationStarts() throws {
        // Given a static plugin registration request has an empty group, invalid plugin metadata, invalid grouped elements, duplicate names, or names already registered in the process
        for invalidCase in StaticPluginInvalidInputCase.allCases {
            let request = try Self.invalidRequest(for: invalidCase)

            // When the user registers the static plugin group
            let capture = NativeElementRegistrationTestHooks.captureStaticPluginCRegistrationAttempts {
                try Self.registerStaticPlugin(request.metadata, entries: request.entries)
            }

            // Then registration throws a typed validation error
            let error = try #require(capture.error)
            Self.expectInvalidArgument(error, parameter: invalidCase.expectedParameter, context: invalidCase.rawValue)

            // And static plugin registration is not attempted
            #expect(capture.attemptCount == 0)

            // And no grouped factory from that invalid request is registered
            for factoryName in request.factoriesExpectedAbsent {
                #expect(!Self.elementFactoryExists(factoryName))
            }
        }
    }

    @Test("License approval is delegated to GStreamer")
    func licenseApprovalIsDelegatedToGStreamer() throws {
        // Given a static plugin registration request has a non-empty license string
        let unusualLicense = "LicenseRef-StaticPluginGroupingTest"
        let plugin = StaticPluginTestMetadata.valid(
            name: "swift_static_license_passthrough",
            license: unusualLicense
        )
        let factoryName = "swift_static_license_sink"

        // When the user registers the static plugin group
        let capture = NativeElementRegistrationTestHooks.captureStaticPluginCRegistrationAttempts {
            try Self.registerStaticPlugin(plugin) {
                Self.makeSink(
                    factoryName: factoryName,
                    typeName: "SwiftGstStaticLicenseSink"
                )
            }
        }

        // Then Swift does not reject the license through a Swift-side license whitelist
        if let error = capture.error {
            if case GStreamerError.invalidArgument(_, _) = error {
                Issue.record("Expected license validation to be delegated to GStreamer, got \(error)")
            } else {
                Self.expectInitializationFailed(error)
            }
        } else {
            #expect(Self.elementFactoryExists(factoryName))
        }

        // And the license string is passed to GStreamer static plugin registration
        #expect(capture.attemptCount == 1)
        let attempt = try #require(capture.attempts.last)
        #expect(attempt.license == unusualLicense)

        // And any GStreamer license rejection is reported as a registration failure
        if let error = capture.error {
            Self.expectInitializationFailed(error)
        }
    }

    @Test("Static plugin registration failure is diagnostic and not partial success")
    func staticPluginRegistrationFailureIsDiagnosticAndNotPartialSuccess() throws {
        // Given the C bridge rejects metadata after Swift prevalidation has passed
        let plugin = StaticPluginTestMetadata.valid(
            name: "swift_static_immediate_c_failure",
            license: "\0"
        )
        let factoryName = "swift_static_immediate_c_failure_sink"

        // When the user registers an otherwise valid static plugin group
        let capture = NativeElementRegistrationTestHooks.captureStaticPluginCRegistrationAttempts {
            try Self.registerStaticPlugin(plugin) {
                Self.makeSink(
                    factoryName: factoryName,
                    typeName: "SwiftGstStaticImmediateCFailureSink"
                )
            }
        }

        // Then registration throws an initialization failure diagnostic
        let error = try #require(capture.error)
        Self.expectInitializationFailed(error, containing: "license")

        // And the API does not return a partial-success result
        #expect(capture.attemptCount == 1)

        // And the API does not claim rollback for process-global side effects
        #expect(!Self.elementFactoryExists(factoryName))
    }

    @Test("Plugin init failure is diagnostic and not partial success")
    func pluginInitFailureIsDiagnosticAndNotPartialSuccess() throws {
        // Given static plugin init cannot register one grouped native element
        let plugin = StaticPluginTestMetadata.valid(name: "swift_static_plugin_init_failure")
        let firstFactory = "swift_static_plugin_init_failure_first"
        let failingFactory = "swift_static_plugin_init_failure_failing"
        let diagnostic = "forced grouped element registration failure"

        // When the user registers the static plugin group
        let capture = NativeElementRegistrationTestHooks.captureStaticPluginCRegistrationAttempts {
            try NativeElementRegistrationTestHooks.withForcedStaticPluginInitRegistrationFailure(
                factoryName: failingFactory,
                message: diagnostic
            ) {
                try Self.registerStaticPlugin(plugin) {
                    Self.makeSink(
                        factoryName: firstFactory,
                        typeName: "SwiftGstStaticPluginInitFailureFirstSink"
                    )
                    Self.makeSink(
                        factoryName: failingFactory,
                        typeName: "SwiftGstStaticPluginInitFailureFailingSink"
                    )
                }
            }
        }

        // Then registration throws an initialization failure diagnostic from plugin init
        let error = try #require(capture.error)
        Self.expectInitializationFailed(error, containing: diagnostic)

        // And invalid grouped elements are not silently skipped
        #expect(capture.attemptCount == 1)
        #expect(!Self.elementFactoryExists(failingFactory))

        // And the API does not return a partial-success result
        _ = firstFactory
    }

    @Test("Grouped factories belong to the static plugin metadata record")
    func groupedFactoriesBelongToTheStaticPluginMetadataRecord() throws {
        // Given a static plugin group has valid plugin metadata and grouped native elements
        let plugin = StaticPluginTestMetadata.valid(name: "swift_static_owner")
        let sinkFactory = "swift_static_owner_sink"
        let inPlaceFactory = "swift_static_owner_in_place"
        let fixedFactory = "swift_static_owner_fixed"
        let generalFactory = "swift_static_owner_general"

        // When the group is registered successfully
        let probe = NativeElementRegistrationTestHooks.capturePluginAwareNativeElementRegistrations {
            try Self.registerStaticPlugin(plugin) {
                Self.makeSink(
                    factoryName: sinkFactory,
                    typeName: "SwiftGstStaticOwnerSink"
                )
                Self.makeInPlaceTransform(
                    factoryName: inPlaceFactory,
                    typeName: "SwiftGstStaticOwnerInPlaceTransform"
                )
                Self.makeFixedOutOfPlaceTransform(
                    factoryName: fixedFactory,
                    typeName: "SwiftGstStaticOwnerFixedTransform"
                )
                Self.makeGeneralOutOfPlaceTransform(
                    factoryName: generalFactory,
                    typeName: "SwiftGstStaticOwnerGeneralTransform"
                )
            }
        }
        if let error = probe.error {
            Issue.record("Expected grouped registration to succeed, got \(error)")
        }

        // Then each grouped factory is associated with the static plugin metadata record
        for factoryName in [sinkFactory, inPlaceFactory, fixedFactory, generalFactory] {
            #expect(Self.factoryOwnerMatches(factoryName: factoryName, pluginName: plugin.name))
        }
        #expect(probe.baseSinkNonNullPluginCount == 1)
        #expect(probe.baseTransformInPlaceNonNullPluginCount == 1)
        #expect(probe.baseTransformFixedOutOfPlaceNonNullPluginCount == 1)
        #expect(probe.baseTransformGeneralOutOfPlaceNonNullPluginCount == 1)

        // And grouped elements are not registered as standalone factories with no plugin owner
        #expect(probe.nullPluginRegistrationCount == 0)
        for factoryName in [sinkFactory, inPlaceFactory, fixedFactory, generalFactory] {
            #expect(Self.factoryHasPluginOwner(factoryName))
        }
    }

    @Test("Static plugin context lifetime is balanced")
    func staticPluginContextLifetimeIsBalanced() throws {
        // Given Swift context data is passed through static plugin registration
        let successPlugin = StaticPluginTestMetadata.valid(name: "swift_static_context_success")
        let initFailurePlugin = StaticPluginTestMetadata.valid(name: "swift_static_context_init_failure")
        let cFailurePlugin = StaticPluginTestMetadata.valid(
            name: "swift_static_context_c_failure",
            license: "\0"
        )
        let initFailureFactory = "swift_static_context_init_failure_sink"
        let cFailureFactory = "swift_static_context_c_failure_sink"

        // When static plugin registration succeeds, plugin init fails, or the C registration bridge fails immediately
        let success = NativeElementRegistrationTestHooks.captureStaticPluginContextRetainRelease {
            try Self.registerStaticPlugin(successPlugin) {
                Self.makeSink(
                    factoryName: "swift_static_context_success_sink",
                    typeName: "SwiftGstStaticContextSuccessSink"
                )
            }
        }
        let initFailure = NativeElementRegistrationTestHooks.captureStaticPluginContextRetainRelease {
            try NativeElementRegistrationTestHooks.withForcedStaticPluginInitRegistrationFailure(
                factoryName: initFailureFactory,
                message: "forced static context init failure"
            ) {
                try Self.registerStaticPlugin(initFailurePlugin) {
                    Self.makeSink(
                        factoryName: initFailureFactory,
                        typeName: "SwiftGstStaticContextInitFailureSink"
                    )
                }
            }
        }
        let cFailure = NativeElementRegistrationTestHooks.captureStaticPluginContextRetainRelease {
            try Self.registerStaticPlugin(cFailurePlugin) {
                Self.makeSink(
                    factoryName: cFailureFactory,
                    typeName: "SwiftGstStaticContextCFailureSink"
                )
            }
        }

        // Then the static plugin context is retained for the registration call
        #expect(success.retainCount == 1)
        #expect(initFailure.retainCount == 1)
        #expect(cFailure.retainCount == 1)

        // And the static plugin context is released exactly once after the registration call returns
        #expect(success.releaseCount == 1)
        #expect(initFailure.releaseCount == 1)
        #expect(cFailure.releaseCount == 1)
        if let error = success.error {
            Issue.record("Expected successful static plugin context capture, got \(error)")
        }
        Self.expectInitializationFailed(try #require(initFailure.error))
        Self.expectInitializationFailed(try #require(cFailure.error))

        // And successfully registered element class contexts keep the existing process-lifetime ownership model
        #expect(success.successfulElementClassContextReleaseCount == 0)
    }

    @Test("Standalone native element registration remains compatible")
    func standaloneNativeElementRegistrationRemainsCompatible() async throws {
        // Given existing Swift BaseSink, in-place BaseTransform, and out-of-place BaseTransform standalone registrations
        let sinkFactory = "swift_static_standalone_sink"
        let inPlaceFactory = "swift_static_standalone_in_place"
        let outOfPlaceFactory = "swift_static_standalone_out_of_place"
        let sinkType = "SwiftGstStaticStandaloneSink"
        let inPlaceType = "SwiftGstStaticStandaloneInPlaceTransform"
        let outOfPlaceType = "SwiftGstStaticStandaloneOutOfPlaceTransform"

        // When users continue calling the existing standalone registration APIs
        try GStreamer.register(Self.makeSink(factoryName: sinkFactory, typeName: sinkType))
        try GStreamer.register(Self.makeInPlaceTransform(factoryName: inPlaceFactory, typeName: inPlaceType))
        try GStreamer.register(
            Self.makeFixedOutOfPlaceTransform(factoryName: outOfPlaceFactory, typeName: outOfPlaceType)
        )

        // Then the standalone factories register in the current process as before
        #expect(Self.elementFactoryExists(sinkFactory))
        #expect(Self.elementFactoryExists(inPlaceFactory))
        #expect(Self.elementFactoryExists(outOfPlaceFactory))
        try await Self.runFiniteVideoPipeline("videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \(sinkFactory)")
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \(inPlaceFactory) ! fakesink sync=false"
        )
        try await Self.runFiniteVideoPipeline(
            "videotestsrc num-buffers=1 ! \(Self.videoCaps) ! \(outOfPlaceFactory) ! fakesink sync=false"
        )

        // And existing duplicate factory and duplicate GType diagnostics remain unchanged
        Self.expectInitializationFailed(try #require(Self.captureError {
            try GStreamer.register(
                Self.makeSink(
                    factoryName: sinkFactory,
                    typeName: "SwiftGstStaticStandaloneDuplicateFactorySink"
                )
            )
        }))
        Self.expectInitializationFailed(try #require(Self.captureError {
            try GStreamer.register(
                Self.makeInPlaceTransform(
                    factoryName: "swift_static_standalone_duplicate_in_place_type",
                    typeName: inPlaceType
                )
            )
        }))
        Self.expectInitializationFailed(try #require(Self.captureError {
            try GStreamer.register(
                Self.makeFixedOutOfPlaceTransform(
                    factoryName: "swift_static_standalone_duplicate_out_of_place_type",
                    typeName: outOfPlaceType
                )
            )
        }))

        // And no source changes are required for existing standalone call sites
        #expect(!Self.factoryHasPluginOwner(sinkFactory))
        #expect(!Self.factoryHasPluginOwner(inPlaceFactory))
        #expect(!Self.factoryHasPluginOwner(outOfPlaceFactory))
    }

    @Test("Documentation describes current-process-only static plugin grouping")
    func documentationDescribesCurrentProcessOnlyStaticPluginGrouping() throws {
        // Given a user reads the tracked native element documentation
        let document = try Self.contents(of: "Sources/GStreamer/Documentation.docc/NativeElements.md")
        let phase5 = Self.staticPluginGroupingDocumentationSection(in: document).lowercased()

        // When static plugin grouping is described
        #expect(!phase5.isEmpty)

        // Then the documentation states grouped Swift factories are private to the current process
        #expect(phase5.contains("current process") || phase5.contains("current application or library process"))

        // And it states a separate gst-inspect-1.0 process will not discover them by default
        #expect(phase5.contains("gst-inspect-1.0"))
        #expect(phase5.contains("will not discover") || phase5.contains("not discover"))
        #expect(phase5.contains("by default"))

        // And it keeps dynamic plugin output, plugin scanner discovery, install paths, rpath, Swift runtime linking, and codesign in Phase 6 scope
        for phrase in [
            "dynamic plugin",
            "plugin scanner",
            "install path",
            "rpath",
            "swift runtime",
            "codesign",
            "phase 6",
        ] {
            #expect(phase5.contains(phrase))
        }
    }

    private static func pluginEntries(
        @NativeElementPluginBuilder _ elements: () -> [NativeElementPluginEntry]
    ) -> [NativeElementPluginEntry] {
        elements()
    }

    private static func registerStaticPlugin(
        _ metadata: StaticPluginTestMetadata,
        @NativeElementPluginBuilder elements: () -> [NativeElementPluginEntry]
    ) throws {
        try Self.registerStaticPlugin(metadata, entries: elements())
    }

    private static func registerStaticPlugin(
        _ metadata: StaticPluginTestMetadata,
        entries: [NativeElementPluginEntry]
    ) throws {
        try GStreamer.registerStaticPlugin(
            name: metadata.name,
            description: metadata.pluginDescription,
            version: metadata.version,
            license: metadata.license,
            source: metadata.source,
            package: metadata.package,
            origin: metadata.origin
        ) {
            for entry in entries {
                entry
            }
        }
    }

    private static func invalidRequest(
        for invalidCase: StaticPluginInvalidInputCase
    ) throws -> StaticPluginInvalidRequest {
        let prefix = "swift_static_invalid_\(invalidCase.factorySuffix)"
        var metadata = StaticPluginTestMetadata.valid(name: prefix)
        var entries = Self.pluginEntries {
            Self.makeSink(
                factoryName: "\(prefix)_sink",
                typeName: "SwiftGstStaticInvalid\(invalidCase.typeSuffix)Sink"
            )
        }
        var factoriesExpectedAbsent = entries.map(\.staticPluginTestFactoryName)

        switch invalidCase {
        case .emptyElementGroup:
            entries = []
            factoriesExpectedAbsent = []
        case .blankPluginName:
            metadata.name = "   "
        case .blankPluginDescription:
            metadata.pluginDescription = "\n\t"
        case .blankPluginVersion:
            metadata.version = " "
        case .blankPluginLicense:
            metadata.license = ""
        case .blankPluginSource:
            metadata.source = " "
        case .blankPluginPackage:
            metadata.package = "\n"
        case .blankPluginOrigin:
            metadata.origin = "\t"
        case .invalidPluginName:
            metadata.name = "-swift static invalid"
        case .invalidGroupedElementDefinition:
            entries = Self.pluginEntries {
                Self.makeSink(
                    factoryName: "\(prefix)_bad_caps",
                    typeName: "SwiftGstStaticInvalidBadCapsSink",
                    sinkCaps: "video/x-raw,format=(string"
                )
            }
            factoriesExpectedAbsent = entries.map(\.staticPluginTestFactoryName)
        case .duplicateFactoryNamesWithinGroup:
            entries = Self.pluginEntries {
                Self.makeSink(
                    factoryName: "\(prefix)_duplicate",
                    typeName: "SwiftGstStaticInvalidDuplicateFactoryOneSink"
                )
                Self.makeSink(
                    factoryName: "\(prefix)_duplicate",
                    typeName: "SwiftGstStaticInvalidDuplicateFactoryTwoSink"
                )
            }
            factoriesExpectedAbsent = Array(Set(entries.map(\.staticPluginTestFactoryName)))
        case .duplicateExplicitGTypeNamesWithinGroup:
            entries = Self.pluginEntries {
                Self.makeSink(
                    factoryName: "\(prefix)_explicit_one",
                    typeName: "SwiftGstStaticInvalidDuplicateExplicitSink"
                )
                Self.makeSink(
                    factoryName: "\(prefix)_explicit_two",
                    typeName: "SwiftGstStaticInvalidDuplicateExplicitSink"
                )
            }
            factoriesExpectedAbsent = entries.map(\.staticPluginTestFactoryName)
        case .duplicateGeneratedGTypeNamesWithinGroup:
            entries = Self.pluginEntries {
                Self.makeSink(factoryName: "\(prefix)_generated_duplicate")
                Self.makeSink(factoryName: "\(prefix)_generated_duplicate")
            }
            factoriesExpectedAbsent = Array(Set(entries.map(\.staticPluginTestFactoryName)))
        case .explicitAndGeneratedGTypeNamesCollideWithinGroup:
            let generatedFactory = "\(prefix)_generated"
            let generatedType = NativeElementTypeName.generatedBaseSinkTypeName(factoryName: generatedFactory)
            entries = Self.pluginEntries {
                Self.makeSink(factoryName: generatedFactory)
                Self.makeSink(
                    factoryName: "\(prefix)_explicit",
                    typeName: generatedType
                )
            }
            factoriesExpectedAbsent = entries.map(\.staticPluginTestFactoryName)
        case .factoryNameAlreadyRegisteredInProcess:
            let existingFactory = "\(prefix)_existing_factory"
            try GStreamer.register(
                Self.makeSink(
                    factoryName: existingFactory,
                    typeName: "SwiftGstStaticInvalidAlreadyRegisteredFactorySink"
                )
            )
            entries = Self.pluginEntries {
                Self.makeSink(
                    factoryName: existingFactory,
                    typeName: "SwiftGstStaticInvalidAlreadyRegisteredFactoryGroupedSink"
                )
                Self.makeSink(
                    factoryName: "\(prefix)_new_factory",
                    typeName: "SwiftGstStaticInvalidAlreadyRegisteredFactoryNewSink"
                )
            }
            factoriesExpectedAbsent = ["\(prefix)_new_factory"]
        case .gTypeNameAlreadyRegisteredInProcess:
            let existingType = "SwiftGstStaticInvalidAlreadyRegisteredTypeSink"
            try GStreamer.register(
                Self.makeSink(
                    factoryName: "\(prefix)_existing_type_owner",
                    typeName: existingType
                )
            )
            entries = Self.pluginEntries {
                Self.makeSink(
                    factoryName: "\(prefix)_new_type_user",
                    typeName: existingType
                )
            }
            factoriesExpectedAbsent = entries.map(\.staticPluginTestFactoryName)
        }

        return StaticPluginInvalidRequest(
            metadata: metadata,
            entries: entries,
            factoriesExpectedAbsent: factoriesExpectedAbsent
        )
    }

    private static func makeSink(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = videoCaps,
        counter: StaticPluginCounter? = nil
    ) -> SwiftBaseSinkElement {
        let counter = counter ?? StaticPluginCounter()
        return SwiftBaseSinkElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.sinkMetadata(),
            sinkCaps: sinkCaps,
            makeInstance: { StaticPluginCountingSink(counter: counter) }
        )
    }

    private static func makeInPlaceTransform(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = videoCaps,
        srcCaps: String = videoCaps,
        counter: StaticPluginCounter? = nil
    ) -> SwiftBaseTransformElement {
        let counter = counter ?? StaticPluginCounter()
        return SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.transformMetadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            passthroughOptions: SwiftBaseTransformPassthroughOptions(
                passthroughOnSameCaps: false,
                transformInPlaceOnPassthrough: false
            ),
            makeInstance: { StaticPluginCountingTransform(counter: counter) }
        )
    }

    private static func makeFixedOutOfPlaceTransform(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = videoCaps,
        srcCaps: String = videoCaps,
        counter: StaticPluginCounter? = nil
    ) -> SwiftBaseTransformOutOfPlaceElement {
        let counter = counter ?? StaticPluginCounter()
        return SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.transformMetadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            options: .fixedSize,
            makeInstance: { StaticPluginCopyingOutOfPlaceTransform(counter: counter) }
        )
    }

    private static func makeGeneralOutOfPlaceTransform(
        factoryName: String,
        typeName: String? = nil,
        metadata: NativeElementMetadata? = nil,
        sinkCaps: String = videoCaps,
        srcCaps: String = videoCaps,
        counter: StaticPluginCounter? = nil
    ) -> SwiftBaseTransformOutOfPlaceElement {
        let counter = counter ?? StaticPluginCounter()
        return SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: metadata ?? Self.transformMetadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            options: .general,
            makeInstance: { StaticPluginCopyingOutOfPlaceTransform(counter: counter) }
        )
    }

    private static func sinkMetadata(
        klass: String = "Sink/Video",
        longName: String = "Swift static plugin test BaseSink",
        description: String = "Swift static plugin test BaseSink element",
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

    private static func transformMetadata(
        klass: String = "Filter/Effect/Video",
        longName: String = "Swift static plugin test BaseTransform",
        description: String = "Swift static plugin test BaseTransform element",
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

    private static func runFiniteVideoPipeline(_ description: String) async throws {
        let pipeline = try Pipeline(description)
        try pipeline.play()
        defer { pipeline.stop() }
        try await Self.withTimeout(.seconds(2)) {
            try await pipeline.bus.waitForEOSOrError()
        }
    }

    private static func expectInvalidArgument(
        _ error: Error,
        parameter expectedParameter: String? = nil,
        context: String = ""
    ) {
        guard case GStreamerError.invalidArgument(let parameter, let reason) = error else {
            Issue.record("Expected invalidArgument for \(context), got \(error)")
            return
        }

        if let expectedParameter {
            #expect(parameter == expectedParameter || parameter.hasSuffix(".\(expectedParameter)"))
        }
        #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func expectInitializationFailed(
        _ error: Error,
        containing expectedDiagnostic: String? = nil
    ) {
        guard case GStreamerError.initializationFailed(let reason) = error else {
            Issue.record("Expected initializationFailed, got \(error)")
            return
        }

        #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let expectedDiagnostic {
            #expect(reason.localizedCaseInsensitiveContains(expectedDiagnostic))
        }
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

    private static func factoryOwnerMatches(factoryName: String, pluginName: String) -> Bool {
        factoryName.withCString { factoryName in
            pluginName.withCString { pluginName in
                swift_gst_test_element_factory_plugin_name_matches(factoryName, pluginName) != 0
            }
        }
    }

    private static func factoryHasPluginOwner(_ factoryName: String) -> Bool {
        factoryName.withCString { swift_gst_test_element_factory_has_plugin_owner($0) != 0 }
    }

    private static func expectSendable<T: Sendable>(_ value: T) {
        _ = value
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
                throw StaticPluginGroupingTimeoutError(timeout: timeout)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw StaticPluginGroupingTimeoutError(timeout: timeout)
            }
            return result
        }
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
                throw StaticPluginGroupingTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func contents(of relativePath: String) throws -> String {
        try String(
            contentsOf: try Self.packageRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func staticPluginGroupingDocumentationSection(in document: String) -> String {
        var sections: [String] = []
        var searchStart = document.startIndex

        while let phase5 = document.range(
            of: "Phase 5: Static plugin grouping",
            options: .caseInsensitive,
            range: searchStart..<document.endIndex
        ) {
            let remainder = document[phase5.lowerBound...]
            if let phase6 = remainder.range(of: "Phase 6:", options: .caseInsensitive) {
                sections.append(String(remainder[..<phase6.upperBound]))
                searchStart = phase6.upperBound
            } else {
                sections.append(String(remainder))
                break
            }
        }

        return sections.joined(separator: "\n")
    }
}

private struct StaticPluginTestMetadata: Sendable {
    var name: String
    var pluginDescription: String
    var version: String
    var license: String
    var source: String
    var package: String
    var origin: String

    static func valid(
        name: String,
        license: String = "MIT"
    ) -> StaticPluginTestMetadata {
        StaticPluginTestMetadata(
            name: name,
            pluginDescription: "Swift static plugin grouping test",
            version: "1.0.0",
            license: license,
            source: "gstreamer-swift-tests",
            package: "gstreamer-swift-tests",
            origin: "https://example.invalid/gstreamer-swift-tests"
        )
    }
}

private struct StaticPluginInvalidRequest: Sendable {
    var metadata: StaticPluginTestMetadata
    var entries: [NativeElementPluginEntry]
    var factoriesExpectedAbsent: [String]
}

private enum StaticPluginInvalidInputCase: String, CaseIterable, Sendable {
    case emptyElementGroup
    case blankPluginName
    case blankPluginDescription
    case blankPluginVersion
    case blankPluginLicense
    case blankPluginSource
    case blankPluginPackage
    case blankPluginOrigin
    case invalidPluginName
    case invalidGroupedElementDefinition
    case duplicateFactoryNamesWithinGroup
    case duplicateExplicitGTypeNamesWithinGroup
    case duplicateGeneratedGTypeNamesWithinGroup
    case explicitAndGeneratedGTypeNamesCollideWithinGroup
    case factoryNameAlreadyRegisteredInProcess
    case gTypeNameAlreadyRegisteredInProcess

    var expectedParameter: String? {
        switch self {
        case .emptyElementGroup:
            "elements"
        case .blankPluginName, .invalidPluginName:
            "name"
        case .blankPluginDescription:
            "description"
        case .blankPluginVersion:
            "version"
        case .blankPluginLicense:
            "license"
        case .blankPluginSource:
            "source"
        case .blankPluginPackage:
            "package"
        case .blankPluginOrigin:
            "origin"
        case .invalidGroupedElementDefinition:
            "sinkCaps"
        case .duplicateFactoryNamesWithinGroup, .factoryNameAlreadyRegisteredInProcess:
            "factoryName"
        case .duplicateExplicitGTypeNamesWithinGroup,
             .explicitAndGeneratedGTypeNamesCollideWithinGroup,
             .gTypeNameAlreadyRegisteredInProcess:
            "typeName"
        case .duplicateGeneratedGTypeNamesWithinGroup:
            nil
        }
    }

    var factorySuffix: String {
        switch self {
        case .emptyElementGroup:
            "empty"
        case .blankPluginName:
            "blank_name"
        case .blankPluginDescription:
            "blank_description"
        case .blankPluginVersion:
            "blank_version"
        case .blankPluginLicense:
            "blank_license"
        case .blankPluginSource:
            "blank_source"
        case .blankPluginPackage:
            "blank_package"
        case .blankPluginOrigin:
            "blank_origin"
        case .invalidPluginName:
            "invalid_name"
        case .invalidGroupedElementDefinition:
            "invalid_element"
        case .duplicateFactoryNamesWithinGroup:
            "duplicate_factory"
        case .duplicateExplicitGTypeNamesWithinGroup:
            "duplicate_explicit_type"
        case .duplicateGeneratedGTypeNamesWithinGroup:
            "duplicate_generated_type"
        case .explicitAndGeneratedGTypeNamesCollideWithinGroup:
            "explicit_generated_type"
        case .factoryNameAlreadyRegisteredInProcess:
            "registered_factory"
        case .gTypeNameAlreadyRegisteredInProcess:
            "registered_type"
        }
    }

    var typeSuffix: String {
        switch self {
        case .emptyElementGroup:
            "Empty"
        case .blankPluginName:
            "BlankName"
        case .blankPluginDescription:
            "BlankDescription"
        case .blankPluginVersion:
            "BlankVersion"
        case .blankPluginLicense:
            "BlankLicense"
        case .blankPluginSource:
            "BlankSource"
        case .blankPluginPackage:
            "BlankPackage"
        case .blankPluginOrigin:
            "BlankOrigin"
        case .invalidPluginName:
            "InvalidName"
        case .invalidGroupedElementDefinition:
            "InvalidElement"
        case .duplicateFactoryNamesWithinGroup:
            "DuplicateFactory"
        case .duplicateExplicitGTypeNamesWithinGroup:
            "DuplicateExplicitType"
        case .duplicateGeneratedGTypeNamesWithinGroup:
            "DuplicateGeneratedType"
        case .explicitAndGeneratedGTypeNamesCollideWithinGroup:
            "ExplicitGeneratedType"
        case .factoryNameAlreadyRegisteredInProcess:
            "RegisteredFactory"
        case .gTypeNameAlreadyRegisteredInProcess:
            "RegisteredType"
        }
    }
}

private extension NativeElementPluginEntry {
    var staticPluginTestFactoryName: String {
        switch self {
        case .baseSink(let element):
            element.factoryName
        case .baseTransform(let element):
            element.factoryName
        case .baseTransformOutOfPlace(let element):
            element.factoryName
        }
    }
}

private final class StaticPluginCounter: @unchecked Sendable {
    private let state = Mutex(0)

    var value: Int {
        state.withLock { $0 }
    }

    func increment() {
        state.withLock { $0 += 1 }
    }
}

private final class StaticPluginCountingSink: SwiftBaseSinkInstance {
    private let counter: StaticPluginCounter

    init(counter: StaticPluginCounter) {
        self.counter = counter
    }

    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        counter.increment()
        return .ok
    }
}

private final class StaticPluginCountingTransform: SwiftBaseTransformInstance {
    private let counter: StaticPluginCounter

    init(counter: StaticPluginCounter) {
        self.counter = counter
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        counter.increment()
        return .ok
    }
}

private final class StaticPluginCopyingOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
    private let counter: StaticPluginCounter

    init(counter: StaticPluginCounter) {
        self.counter = counter
    }

    func getUnitSize(for caps: Caps) throws -> BaseTransformHookResult<Int> {
        .value(12)
    }

    func transformSize(
        direction: Pad.Direction,
        caps: Caps,
        size: Int,
        otherCaps: Caps
    ) throws -> BaseTransformHookResult<Int> {
        .value(12)
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        let inputBytes = try input.withUnsafeBytes { Array($0) }
        try output.withUnsafeMutableBytes { bytes in
            let count = min(bytes.count, inputBytes.count)
            for index in 0..<count {
                bytes[index] = inputBytes[index]
            }
        }
        counter.increment()
        return .ok
    }
}

private struct StaticPluginGroupingTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}

private enum StaticPluginGroupingTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not find Package.swift while walking up from \(filePath)"
        }
    }
}
