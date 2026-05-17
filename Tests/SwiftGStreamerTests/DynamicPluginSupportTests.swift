import Foundation
import Synchronization
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Dynamic Plugin Support Tests", .serialized, .timeLimit(.minutes(2)))
struct DynamicPluginSupportTests {
    fileprivate static let videoCaps = "video/x-raw,format=RGB,width=2,height=2,framerate=1/1"
    private static let templateRoot = "Examples/DynamicPluginTemplate"

    init() throws {
        try GStreamer.initialize()
    }

    @Test("Builds SwiftPM dynamic plugin artifact from template")
    func buildsSwiftPMDynamicPluginArtifactFromTemplate() throws {
        // Given a developer copies the Phase 6 dynamic plugin template
        let manifest = try Self.templateContents("Package.swift")
        let template = try Self.concatenatedTemplateContents()

        // When the developer builds the template with SwiftPM
        // Then the checked-in template describes a SwiftPM dynamic library artifact named for the plugin ID
        Self.expectContains(manifest, [
            ".library(",
            "name: \"gstswiftnative\"",
            "type: .dynamic",
            "GStreamer",
        ])

        // And the default macOS and Linux artifact names are documented or scripted
        Self.expectContains(template, [
            "swiftnative",
            "libgstswiftnative.dylib",
            "libgstswiftnative.so",
        ])

        // And symbol inspection covers the GStreamer entrypoint and exported Swift init symbols
        Self.expectContains(template, [
            "nm",
            "swift_native_dynamic_plugin_init",
        ])
        #expect(
            template.contains("gst_plugin_swiftnative_get_desc")
                || template.contains("gst_plugin_swiftnative_register")
        )
    }

    @Test("Accepts valid plugin identifiers before build or install")
    func acceptsValidPluginIdentifiersBeforeBuildOrInstall() throws {
        // Given a developer configures the dynamic plugin template with a valid plugin ID
        let validator = try Self.templateScript(
            preferredNameContaining: "validate",
            containing: ["plugin", "id"]
        )

        for (pluginID, artifactStem) in [
            ("swiftnative", "libgstswiftnative"),
            ("custom_plugin1", "libgstcustom_plugin1"),
        ] {
            // When template validation runs
            let result = try Self.runShellScript(validator.url, arguments: [pluginID])

            // Then validation accepts the plugin ID
            #expect(result.exitCode == 0)

            // And the plugin ID derives the expected libgst artifact name
            let output = result.combinedOutput
            #expect(output.contains(pluginID))
            #expect(
                output.contains("\(artifactStem).dylib")
                    || output.contains("\(artifactStem).so")
                    || output.contains(artifactStem)
            )
        }
    }

    @Test("Rejects invalid plugin identifiers before build or install")
    func rejectsInvalidPluginIdentifiersBeforeBuildOrInstall() throws {
        // Given a developer configures the dynamic plugin template with an invalid plugin ID
        let validator = try Self.templateScript(
            preferredNameContaining: "validate",
            containing: ["plugin", "id"]
        )

        for pluginID in ["1swift", "swift-plugin", "swift.plugin"] {
            // When template validation runs
            let result = try Self.runShellScript(validator.url, arguments: [pluginID])

            // Then validation rejects the plugin ID
            #expect(result.exitCode != 0)
            #expect(result.combinedOutput.localizedCaseInsensitiveContains("invalid"))

            // And no plugin library filename is staged or emitted for the invalid ID
            #expect(!result.combinedOutput.contains("libgst\(pluginID).dylib"))
            #expect(!result.combinedOutput.contains("libgst\(pluginID).so"))
        }
    }

    @Test("Loads dynamic plugin through C entrypoint and Swift init")
    func loadsDynamicPluginThroughCEntrypointAndSwiftInit() throws {
        // Given a staged Swift dynamic plugin library
        let cEntrypoint = try Self.templateSourceFile(containing: [
            "GST_PLUGIN_DEFINE",
            "swift_native_dynamic_plugin_init",
        ])
        let swiftInit = try Self.templateSourceFile(containing: [
            "@_cdecl",
            "swift_native_dynamic_plugin_init",
        ])

        // When GStreamer loads the plugin through the C entrypoint
        // Then plugin metadata is supplied by GST_PLUGIN_DEFINE
        Self.expectContains(cEntrypoint.contents, [
            "GST_PLUGIN_DEFINE",
            "PACKAGE",
            "swiftnative",
        ])

        // And the C entrypoint calls the exported Swift init function
        Self.expectContains(cEntrypoint.contents, [
            "swift_native_dynamic_plugin_init",
            "swift_native_dynamic_plugin_link_anchor",
        ])
        Self.expectContains(swiftInit.contents, [
            "@_cdecl(\"swift_native_dynamic_plugin_init\")",
            "GStreamer.withDynamicPluginContext",
            "GStreamer.registerDynamicPluginElements",
        ])

        // And Swift plugin init does not initialize GStreamer again
        Self.expectDoesNotContain(swiftInit.contents, [
            "import Foundation",
            "GStreamer.initialize(",
            "GStreamer.ensureInitialized(",
            "ensureInitialized(",
            "gst_init",
            "gst_plugin_register_static_full",
            "ProcessInfo.processInfo",
        ])
        #expect(swiftInit.contents.contains("getenv"))
    }

    @Test("Registers Swift factories against borrowed dynamic plugin")
    func registersSwiftFactoriesAgainstBorrowedDynamicPlugin() throws {
        // Given GStreamer supplies a non-null plugin pointer during plugin load
        let pluginName = "swift_dynamic_all_kinds_plugin"
        let probe = DynamicPluginCallbackProbe(
            operation: .registerAllKinds,
            prefix: "swift_dynamic_all_kinds"
        )

        // When Swift plugin init registers each supported Swift-backed factory kind
        let capture = NativeElementRegistrationTestHooks.capturePluginAwareNativeElementRegistrations {
            try Self.registerTestPlugin(name: pluginName, probe: probe)
        }
        if let error = capture.error {
            Issue.record("Expected dynamic plugin registration to succeed, got \(error)")
        }

        // Then every factory is registered against the supplied plugin
        let state = probe.snapshot()
        #expect(state.wasCalled)
        #expect(state.rawPluginWasNonNil)
        #expect(state.succeeded)
        #expect(state.errorDescription == nil)
        #expect(capture.baseSinkNonNullPluginCount == 1)
        #expect(capture.baseTransformInPlaceNonNullPluginCount == 1)
        #expect(capture.baseTransformFixedOutOfPlaceNonNullPluginCount == 1)
        #expect(capture.baseTransformGeneralOutOfPlaceNonNullPluginCount == 1)

        for factoryName in probe.expectedFactoryNames {
            #expect(Self.elementFactoryExists(factoryName))
            #expect(Self.factoryOwnerMatches(factoryName: factoryName, pluginName: pluginName))
        }

        // And no factory is registered with a null plugin owner
        #expect(capture.nullPluginRegistrationCount == 0)
    }

    @Test("Prevents borrowed dynamic plugin context misuse")
    func preventsBorrowedDynamicPluginContextMisuse() throws {
        // Given Swift plugin init receives a borrowed GStreamer plugin pointer
        let source = try NativeElementSourceLayoutTestSupport.nativeElementSwiftSource()

        // When maintainers inspect the public dynamic plugin API
        let contextBlock = try Self.bracedDeclarationBlock(
            in: source,
            startingAt: "public struct NativeElementDynamicPluginContext"
        )

        // Then the dynamic plugin context is noncopyable
        #expect(contextBlock.contains(": ~Copyable"))

        // And it has no public initializer
        #expect(!contextBlock.contains("public init"))

        // And it exposes no public raw pointer storage
        #expect(
            contextBlock.range(
                of: #"public\s+(let|var)\s+\w+\s*:\s*(OpaquePointer|Unsafe(Mutable)?RawPointer|Unsafe(Mutable)?Pointer)"#,
                options: String.CompareOptions.regularExpression
            ) == nil
        )

        // And it has no Sendable conformance
        #expect(!contextBlock.contains("Sendable"))
        #expect(
            source.range(
                of: #"extension\s+NativeElementDynamicPluginContext\s*:\s*(@unchecked\s+)?Sendable"#,
                options: String.CompareOptions.regularExpression
            ) == nil
        )

        // And registration accepts the context only as a borrowing parameter
        Self.expectContains(source, [
            "rawPlugin: OpaquePointer",
            "(borrowing NativeElementDynamicPluginContext) throws -> R",
            "into plugin: borrowing NativeElementDynamicPluginContext",
        ])
    }

    @Test("Allows dynamic plugin registry-cache reloads during external discovery")
    func allowsDynamicPluginRegistryCacheReloadsDuringExternalDiscovery() throws {
        // Given external GStreamer tools may cache dynamic plugin features before loading their element classes
        let dynamicRegistration = try Self.contents(of: "Sources/GStreamer/NativeElements/DynamicPluginRegistration.swift")
        let staticRegistration = try Self.contents(of: "Sources/GStreamer/NativeElements/StaticPluginRegistration.swift")
        let shimHeader = try Self.contents(of: "Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        let baseSinkShim = try Self.contents(of: "Sources/CGStreamerBaseShim/GStreamerBaseSinkShim.c")
        let baseTransformShim = try Self.contents(of: "Sources/CGStreamerBaseShim/GStreamerBaseTransformShim.c")

        // Then dynamic plugin validation ignores factories already owned by the same plugin cache entry
        Self.expectContains(dynamicRegistration, [
            "swift_gst_plugin_name",
            "allowingExistingFactoriesOwnedBy",
        ])
        Self.expectContains(staticRegistration, [
            "swift_gst_element_factory_plugin_name_matches",
            "allowingExistingOwnerPluginNamed",
        ])
        Self.expectContains(shimHeader, [
            "swift_gst_plugin_name",
            "swift_gst_element_factory_plugin_name_matches",
        ])

        // And the C registration precheck keeps the stricter global lookup only for process-local registration
        Self.expectContains(baseSinkShim, [
            "if (plugin == NULL)",
            "gst_element_factory_find",
        ])
        Self.expectContains(baseTransformShim, [
            "if (plugin == NULL)",
            "gst_element_factory_find",
        ])
    }

    @Test("Rejects invalid dynamic element groups before registration")
    func rejectsInvalidDynamicElementGroupsBeforeRegistration() throws {
        // Given a dynamic plugin element group is empty, invalid, duplicated, or already registered
        for invalidCase in DynamicInvalidGroupCase.allCases {
            let prefix = "swift_dynamic_invalid_\(invalidCase.suffix)"
            try Self.prepareExistingRegistration(for: invalidCase, prefix: prefix)
            let probe = DynamicPluginCallbackProbe(
                operation: .invalidGroup(invalidCase),
                prefix: prefix
            )

            // When Swift plugin init validates the group
            let capture = NativeElementRegistrationTestHooks.capturePluginAwareNativeElementRegistrations {
                try Self.registerTestPlugin(name: "\(prefix)_plugin", probe: probe)
            }
            #expect(capture.error != nil)

            // Then registration throws a validation error before grouped registration begins
            let state = probe.snapshot()
            #expect(state.wasCalled)
            #expect(state.rawPluginWasNonNil)
            #expect(!state.succeeded)
            Self.expectInvalidArgument(state, parameter: invalidCase.expectedParameter)
            #expect(capture.baseSinkNonNullPluginCount == 0)
            #expect(capture.baseTransformInPlaceNonNullPluginCount == 0)
            #expect(capture.baseTransformFixedOutOfPlaceNonNullPluginCount == 0)
            #expect(capture.baseTransformGeneralOutOfPlaceNonNullPluginCount == 0)
            #expect(capture.nullPluginRegistrationCount == 0)

            // And invalid elements are not silently skipped or reported as partial success
            for factoryName in invalidCase.factoriesExpectedAbsent(prefix: prefix) {
                #expect(!Self.elementFactoryExists(factoryName))
            }
        }
    }

    @Test("Reports Swift init failures through plugin status diagnostics")
    func reportsSwiftInitFailuresThroughPluginStatusDiagnostics() throws {
        // Given Swift dynamic plugin registration throws during plugin init
        let swiftInit = try Self.templateSourceFile(containing: [
            "@_cdecl",
            "swift_native_dynamic_plugin_init",
        ])
        let cStatusHelper = try Self.templateSourceFile(containing: [
            "swift_native_dynamic_plugin_record_status_error",
            "gst_plugin_add_status_error",
        ])

        // When the Swift init boundary catches the failure
        Self.expectContains(swiftInit.contents, [
            "do",
            "catch",
            "swift_native_dynamic_plugin_record_status_error",
        ])

        // Then the plugin records a useful GStreamer status error
        #expect(cStatusHelper.contents.contains("gst_plugin_add_status_error"))
        #expect(cStatusHelper.contents.contains("g_printerr"))
        Self.expectContains(swiftInit.contents, [
            "SWIFT_NATIVE_DYNAMIC_PLUGIN_FORCE_REGISTRATION_FAILURE",
            "forced Swift dynamic plugin registration failure",
        ])
        Self.expectContains(try Self.allTemplateScriptContents(), [
            "EXPECT_FAILURE_DIAGNOSTIC",
            "GST_REGISTRY_FORK=no",
            "SWIFT_NATIVE_DYNAMIC_PLUGIN_FORCE_REGISTRATION_FAILURE",
            "forced Swift dynamic plugin registration failure",
            "missing useful Swift registration failure diagnostic",
        ])

        // And the init function returns FALSE without letting Swift errors escape through C
        #expect(
            swiftInit.contents.contains("return 0")
                || swiftInit.contents.contains("return FALSE")
                || swiftInit.contents.contains("return false")
        )
        Self.expectDoesNotContain(swiftInit.contents, [
            "GStreamer.initialize(",
            "GStreamer.ensureInitialized(",
            "ensureInitialized(",
            "gst_init",
            "gst_plugin_register_static_full",
        ])
    }

    @Test("Stages install with bundled Swift libraries and external system libraries")
    func stagesInstallWithBundledSwiftLibrariesAndExternalSystemLibraries() throws {
        // Given a developer chooses a non-privileged install prefix
        let scripts = try Self.allTemplateScriptContents()

        // When the staged install workflow runs
        // Then the plugin library is installed below the prefix GStreamer plugin directory
        Self.expectContains(scripts, [
            "prefix",
            "libgst",
            "gstreamer-1.0",
        ])

        // And Swift and private SwiftPM dynamic libraries are installed below the prefix Swift library directory
        Self.expectContains(scripts, [
            "swift",
            "runtimeLibraryPaths",
        ])

        // And GStreamer, GLib, and platform system libraries remain external dependencies
        Self.expectContains(scripts, [
            "GStreamer",
            "GLib",
            "/home/linuxbrew/.linuxbrew",
            "/opt/homebrew",
            "/usr/local/Cellar",
            "/usr/local/opt",
        ])

        // And unclassified dependencies fail install validation
        #expect(
            scripts.localizedCaseInsensitiveContains("unclassified")
                || scripts.localizedCaseInsensitiveContains("unsupported dependency")
        )
    }

    @Test("Discovers Swift runtime paths and classifies runtime dependencies")
    func discoversSwiftRuntimePathsAndClassifiesRuntimeDependencies() throws {
        // Given the staged install workflow is preparing Swift dependencies
        let scripts = try Self.allTemplateScriptContents()

        // When it queries Swift target information
        // Then it reads runtime library and resource paths from swift -print-target-info
        #expect(
            scripts.contains("swiftly run swift -print-target-info")
                || (scripts.contains("swiftly") && scripts.contains("-print-target-info"))
        )
        Self.expectContains(scripts, [
            "runtimeLibraryPaths",
            "runtimeResourcePath",
        ])
        Self.expectContains(scripts, [
            "libBlocksRuntime",
            "libdispatch",
            "libFoundation",
            "libFoundationEssentials",
            "libFoundationInternationalization",
            "lib_FoundationICU",
        ])

        // And it classifies macOS dependencies with otool and Linux dependencies with ldd
        Self.expectContains(scripts, [
            "swift-stdlib-tool",
            "--copy",
            "--scan-executable",
            "otool -L",
            "ldd",
        ])
    }

    @Test("Configures relative rpaths and platform loader requirements")
    func configuresRelativeRpathsAndPlatformLoaderRequirements() throws {
        // Given the staged plugin and Swift libraries have been copied into the install prefix
        let scripts = try Self.allTemplateScriptContents()

        // When platform loader fixups run
        // Then macOS and Linux configure relative runtime search paths to the staged Swift libraries
        Self.expectContains(scripts, [
            "@loader_path/../swift",
            "$ORIGIN/../swift",
        ])

        // And macOS verifies rpaths, ad-hoc signs after binary modifications, and verifies the signature
        Self.expectContains(scripts, [
            "otool -l",
            "otool -L",
            "codesign",
            "DYLD_LIBRARY_PATH",
            "GI_TYPELIB_PATH",
        ])

        // And Linux reports patchelf as unavailable when it is required but missing
        Self.expectContains(scripts, [
            "patchelf",
        ])
        #expect(
            scripts.localizedCaseInsensitiveContains("patchelf unavailable")
                || scripts.localizedCaseInsensitiveContains("patchelf is unavailable")
                || scripts.localizedCaseInsensitiveContains("patchelf missing")
                || scripts.localizedCaseInsensitiveContains("missing patchelf")
        )
    }

    @Test("Validates external discovery with isolated registry")
    func validatesExternalDiscoveryWithIsolatedRegistry() throws {
        // Given a staged dynamic plugin install
        let scripts = try Self.allTemplateScriptContents()

        // When validation runs with GST_PLUGIN_PATH and a temporary GST_REGISTRY
        Self.expectContains(scripts, [
            "GST_PLUGIN_PATH",
            "GST_REGISTRY",
        ])

        // Then gst-inspect can inspect plugin metadata and a Swift-backed factory
        Self.expectContains(scripts, [
            "gst-inspect-1.0",
            "swiftnative",
            "swiftnativeidentity",
        ])

        // And an external pipeline subprocess can use a Swift-backed factory
        #expect(scripts.contains("gst-launch-1.0"))

        // And stale registry cache entries do not affect the validation result
        #expect(
            scripts.contains("rm -f")
                || scripts.localizedCaseInsensitiveContains("remove")
                || scripts.localizedCaseInsensitiveContains("delete")
        )
    }

    @Test("CI validates dynamic plugin through external GStreamer tools")
    func ciValidatesDynamicPluginThroughExternalGStreamerTools() throws {
        // Given the repository CI includes an external dynamic plugin validation job
        let workflow = try Self.contents(of: ".github/workflows/ci.yml")
        let job = try Self.workflowJob(named: "dynamic-plugin-external", in: workflow)

        // Then the job is an Ubuntu-only blocking check with the expected toolchain baseline
        Self.expectContains(job, [
            "runs-on: ubuntu-22.04",
            "timeout-minutes: 60",
            "permissions:",
            "contents: read",
            "SWIFT_VERSION: 6.3.1",
        ])
        #expect(!job.contains("continue-on-error"))

        // And Linux CI installs GStreamer through Linuxbrew while exporting its runtime library path
        let linuxbrewStep = try Self.workflowStep(
            named: "Install dynamic plugin Linuxbrew GStreamer dependencies",
            in: job
        )
        Self.expectContains(linuxbrewStep, [
            #"eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)""#,
            "brew install pkgconf gstreamer",
            #"echo "LD_LIBRARY_PATH=${HOMEBREW_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" >> "$GITHUB_ENV""#,
        ])

        // And Linux CI installs patchelf because the staged install script requires it for Linux rpaths
        let supportStep = try Self.workflowStep(
            named: "Install dynamic plugin Swift support dependencies (Ubuntu)",
            in: job
        )
        Self.expectContains(supportStep, [
            "sudo apt-get remove -y libunwind-13-dev libunwind-14-dev",
            "libcurl4-openssl-dev",
            "pkg-config",
            "python3-lldb-13",
            "libunwind-dev",
            "patchelf",
            "patchelf --version",
        ])

        // And the dynamic preflight covers every native-element GStreamer module
        let preflightStep = try Self.workflowStep(named: "Preflight dynamic plugin dependencies", in: job)
        #expect(
            Self.hasSwiftlyAndLinuxbrewEnvironmentBefore("pkg-config --exists", in: preflightStep)
        )
        #expect(
            Self.hasSwiftlyAndLinuxbrewEnvironmentBefore("gst-inspect-1.0 --version", in: preflightStep)
        )
        #expect(
            preflightStep.contains(
                "pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gstreamer-base-1.0"
            )
        )
        for module in Self.requiredGStreamerModules {
            #expect(preflightStep.contains("pkg-config --modversion \(module)"))
            #expect(preflightStep.contains("pkg-config --atleast-version=1.28.2 \(module)"))
        }

        // And the template is built, inspected, staged, and validated as an external plugin
        let buildStep = try Self.workflowStep(named: "Build dynamic plugin template", in: job)
        #expect(
            Self.hasSwiftlyAndLinuxbrewEnvironmentBefore("swiftly run swift build -c release", in: buildStep)
        )
        Self.expectContains(buildStep, [
            "cd Examples/DynamicPluginTemplate",
            "swiftly run swift build -c release",
        ])

        let inspectStep = try Self.workflowStep(named: "Inspect dynamic plugin symbols", in: job)
        #expect(Self.hasSwiftlyAndLinuxbrewEnvironmentBefore("nm -D", in: inspectStep))
        Self.expectContains(inspectStep, [
            ".build/release/libgstswiftnative.so",
            "swift_native_dynamic_plugin_init",
            "gst_plugin_swiftnative_(get_desc|register)",
        ])

        let stageStep = try Self.workflowStep(named: "Stage dynamic plugin template", in: job)
        #expect(Self.hasSwiftlyAndLinuxbrewEnvironmentBefore("Scripts/stage-install.sh", in: stageStep))
        Self.expectContains(stageStep, [
            #"Scripts/stage-install.sh swiftnative "$RUNNER_TEMP/swiftnative-stage""#,
        ])

        let validationStep = try Self.workflowStep(named: "Validate staged dynamic plugin", in: job)
        #expect(
            Self.hasSwiftlyAndLinuxbrewEnvironmentBefore("Scripts/validate-staged-plugin.sh", in: validationStep)
        )
        Self.expectContains(validationStep, [
            "VALIDATION_TIMEOUT_SECONDS=30",
            #"Scripts/validate-staged-plugin.sh swiftnative "$RUNNER_TEMP/swiftnative-stage" swiftnativeidentity"#,
        ])

        let failureDiagnosticStep = try Self.workflowStep(
            named: "Validate dynamic plugin failure diagnostics",
            in: job
        )
        #expect(
            Self.hasSwiftlyAndLinuxbrewEnvironmentBefore(
                "Scripts/validate-staged-plugin.sh",
                in: failureDiagnosticStep
            )
        )
        Self.expectContains(failureDiagnosticStep, [
            "EXPECT_FAILURE_DIAGNOSTIC=1",
            "VALIDATION_TIMEOUT_SECONDS=30",
            #"Scripts/validate-staged-plugin.sh swiftnative "$RUNNER_TEMP/swiftnative-stage" swiftnativeidentity"#,
        ])
    }

    @Test("Uses template-root stage defaults independent of caller directory")
    func usesTemplateRootStageDefaultsIndependentOfCallerDirectory() throws {
        // Given a developer invokes the template scripts from the repository root or another directory
        let stageInstall = try Self.templateScript(
            preferredNameContaining: "stage-install",
            containing: ["template_root", ".stage"]
        )
        let validator = try Self.templateScript(
            preferredNameContaining: "validate-staged",
            containing: ["template_root", ".stage"]
        )

        // Then default staging resolves relative to the template root, not the caller's current directory
        Self.expectContains(stageInstall.contents, [
            "template_root=",
            #"prefix="${2:-$template_root/.stage}""#,
            #"cd "$template_root""#,
        ])
        Self.expectContains(validator.contents, [
            "template_root=",
            #"prefix="${2:-$template_root/.stage}""#,
        ])
    }

    @Test("Reports missing staged plugin before invoking GStreamer scanner")
    func reportsMissingStagedPluginBeforeInvokingGStreamerScanner() throws {
        // Given validation is pointed at an empty staged prefix
        let validator = try Self.templateScript(
            preferredNameContaining: "validate-staged",
            containing: ["GST_PLUGIN_PATH", "GST_REGISTRY"]
        )
        let missingPrefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("gstreamer-swift-missing-stage-\(UUID().uuidString)")

        // When validation runs before the plugin has been staged
        let result = try Self.runShellScript(validator.url, arguments: ["swiftnative", missingPrefix.path])

        // Then it fails before noisy gst-plugin-scanner discovery
        #expect(result.exitCode != 0)
        Self.expectContains(result.combinedOutput, [
            "missing staged plugin library",
            "stage-install.sh",
            "swiftly run swift build -c release",
        ])
        #expect(!result.combinedOutput.contains("gst-plugin-scanner"))
        #expect(!result.combinedOutput.contains("No such element or plugin"))
    }

    @Test("Marks external validation unavailable when required tools are missing")
    func marksExternalValidationUnavailableWhenRequiredToolsAreMissing() throws {
        // Given the staged validation workflow checks host requirements
        let scripts = try Self.allTemplateScriptContents()

        // When required GStreamer, Swift, gst-inspect, gst-launch, or platform loader tools are missing
        Self.expectContains(scripts, [
            "1.28.2",
            "swiftly",
            "gst-inspect-1.0",
            "gst-launch-1.0",
        ])
        #expect(scripts.contains("command -v") || scripts.contains("which "))

        // Then validation reports the missing requirement clearly
        #expect(
            scripts.localizedCaseInsensitiveContains("missing")
                || scripts.localizedCaseInsensitiveContains("unavailable")
                || scripts.localizedCaseInsensitiveContains("not found")
        )

        // And it does not report a successful external discovery result on missing requirements
        #expect(scripts.contains("exit 1") || scripts.contains("return 1"))
    }

    private static func registerTestPlugin(
        name: String,
        probe: DynamicPluginCallbackProbe
    ) throws {
        let registered = name.withCString { pluginName in
            swift_gst_test_register_static_plugin_with_init_callback(
                pluginName,
                swiftGstTestDynamicPluginInitCallback,
                Unmanaged.passUnretained(probe).toOpaque()
            ) != 0
        }

        guard registered else {
            throw DynamicPluginSupportTestError.testPluginRegistrationFailed(
                name,
                probe.snapshot().errorDescription
            )
        }
    }

    private static func prepareExistingRegistration(
        for invalidCase: DynamicInvalidGroupCase,
        prefix: String
    ) throws {
        switch invalidCase {
        case .emptyElementGroup,
             .invalidElementDefinition,
             .duplicateFactoryNamesWithinGroup,
             .duplicateExplicitGTypeNamesWithinGroup,
             .duplicateGeneratedGTypeNamesWithinGroup,
             .explicitAndGeneratedGTypeNamesCollideWithinGroup:
            return
        case .factoryNameAlreadyRegisteredInProcess:
            try GStreamer.register(
                Self.makeSink(
                    factoryName: "\(prefix)_existing_factory",
                    typeName: "SwiftGstDynamicInvalidRegisteredFactoryExistingSink"
                )
            )
        case .gTypeNameAlreadyRegisteredInProcess:
            try GStreamer.register(
                Self.makeSink(
                    factoryName: "\(prefix)_existing_type_owner",
                    typeName: "SwiftGstDynamicInvalidRegisteredTypeSink"
                )
            )
        }
    }

    fileprivate static func makeSink(
        factoryName: String,
        typeName: String? = nil,
        sinkCaps: String = videoCaps
    ) -> SwiftBaseSinkElement {
        SwiftBaseSinkElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.sinkMetadata(),
            sinkCaps: sinkCaps,
            makeInstance: { DynamicPluginNoopSink() }
        )
    }

    fileprivate static func makeInPlaceTransform(
        factoryName: String,
        typeName: String? = nil,
        sinkCaps: String = videoCaps,
        srcCaps: String = videoCaps
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.transformMetadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            passthroughOptions: SwiftBaseTransformPassthroughOptions(
                passthroughOnSameCaps: false,
                transformInPlaceOnPassthrough: false
            ),
            makeInstance: { DynamicPluginNoopTransform() }
        )
    }

    fileprivate static func makeFixedOutOfPlaceTransform(
        factoryName: String,
        typeName: String? = nil,
        sinkCaps: String = videoCaps,
        srcCaps: String = videoCaps
    ) -> SwiftBaseTransformOutOfPlaceElement {
        SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.transformMetadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            options: .fixedSize,
            makeInstance: { DynamicPluginNoopOutOfPlaceTransform() }
        )
    }

    fileprivate static func makeGeneralOutOfPlaceTransform(
        factoryName: String,
        typeName: String? = nil,
        sinkCaps: String = videoCaps,
        srcCaps: String = videoCaps
    ) -> SwiftBaseTransformOutOfPlaceElement {
        SwiftBaseTransformOutOfPlaceElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.transformMetadata(),
            sinkCaps: sinkCaps,
            srcCaps: srcCaps,
            options: .general,
            makeInstance: { DynamicPluginNoopOutOfPlaceTransform() }
        )
    }

    private static func sinkMetadata() -> NativeElementMetadata {
        NativeElementMetadata(
            klass: "Sink/Video",
            longName: "Swift dynamic plugin test BaseSink",
            description: "Swift dynamic plugin test BaseSink element",
            author: "gstreamer-swift-tests"
        )
    }

    private static func transformMetadata() -> NativeElementMetadata {
        NativeElementMetadata(
            klass: "Filter/Effect/Video",
            longName: "Swift dynamic plugin test BaseTransform",
            description: "Swift dynamic plugin test BaseTransform element",
            author: "gstreamer-swift-tests"
        )
    }

    private static func expectInvalidArgument(
        _ state: DynamicPluginCallbackState,
        parameter expectedParameter: String?
    ) {
        #expect(state.errorDescription != nil)
        if let expectedParameter {
            #expect(
                state.invalidArgumentParameter == expectedParameter
                    || state.invalidArgumentParameter?.hasSuffix(".\(expectedParameter)") == true
            )
        } else {
            #expect(
                state.invalidArgumentParameter == "factoryName"
                    || state.invalidArgumentParameter == "typeName"
            )
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

    private static func contents(of relativePath: String) throws -> String {
        try String(
            contentsOf: try Self.packageRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func workflowJob(named jobName: String, in workflow: String) throws -> String {
        let jobHeader = "  \(jobName):"
        var lines: [Substring] = []
        var isCollecting = false

        for line in workflow.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == jobHeader {
                isCollecting = true
            } else if isCollecting,
                      line.hasPrefix("  "),
                      !line.hasPrefix("    "),
                      line.hasSuffix(":") {
                break
            }

            if isCollecting {
                lines.append(line)
            }
        }

        guard !lines.isEmpty else {
            throw DynamicPluginSupportTestError.workflowJobNotFound(jobName)
        }
        return lines.joined(separator: "\n")
    }

    private static func workflowStep(named stepName: String, in workflowOrJob: String) throws -> String {
        let marker = "- name: \(stepName)"
        guard let stepStart = workflowOrJob.range(of: marker)?.lowerBound else {
            throw DynamicPluginSupportTestError.workflowStepNotFound(stepName)
        }

        let remaining = workflowOrJob[stepStart...]
        let searchRange = remaining.index(after: remaining.startIndex)..<remaining.endIndex
        let nextStepStart = remaining
            .range(of: "\n      - name: ", options: [], range: searchRange)?
            .lowerBound ?? workflowOrJob.endIndex

        return String(workflowOrJob[stepStart..<nextStepStart])
    }

    private static func hasSwiftlyAndLinuxbrewEnvironmentBefore(
        _ command: String,
        in step: String
    ) -> Bool {
        snippetsAppearInOrder(
            [
                #". "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh""#,
                #"eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)""#,
                command,
            ],
            in: step
        )
    }

    private static func snippetsAppearInOrder(_ snippets: [String], in source: String) -> Bool {
        var searchStart = source.startIndex

        for snippet in snippets {
            guard let range = source.range(of: snippet, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }

        return true
    }

    private static func templateContents(_ relativePath: String) throws -> String {
        try Self.contents(of: "\(templateRoot)/\(relativePath)")
    }

    private static func concatenatedTemplateContents() throws -> String {
        try Self.files(under: templateRoot)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func templateSourceFile(
        containing requiredTerms: [String]
    ) throws -> TemplateFile {
        let sourceExtensions: Set<String> = ["swift", "c", "h"]
        for url in try Self.files(under: templateRoot)
            where sourceExtensions.contains(url.pathExtension.lowercased()) {
            let contents = try String(contentsOf: url, encoding: .utf8)
            if requiredTerms.allSatisfy({ contents.contains($0) }) {
                return TemplateFile(path: try Self.relativePath(for: url), url: url, contents: contents)
            }
        }

        throw DynamicPluginSupportTestError.templateSourceNotFound(requiredTerms)
    }

    private static func templateScript(
        preferredNameContaining preferredName: String,
        containing requiredTerms: [String]
    ) throws -> TemplateFile {
        let preferredName = preferredName.lowercased()
        let requiredTerms = requiredTerms.map { $0.lowercased() }
        let scripts = try Self.templateScriptFiles().map { url -> TemplateFile in
            TemplateFile(
                path: try Self.relativePath(for: url),
                url: url,
                contents: try String(contentsOf: url, encoding: .utf8)
            )
        }

        if let exact = scripts.first(where: { script in
            script.url.lastPathComponent.lowercased().contains(preferredName)
                && requiredTerms.allSatisfy { script.contents.lowercased().contains($0) }
        }) {
            return exact
        }

        if let fallback = scripts.first(where: { script in
            requiredTerms.allSatisfy { script.contents.lowercased().contains($0) }
        }) {
            return fallback
        }

        throw DynamicPluginSupportTestError.templateScriptNotFound(requiredTerms.joined(separator: ", "))
    }

    private static func allTemplateScriptContents() throws -> String {
        let scripts = try Self.templateScriptFiles()
        guard !scripts.isEmpty else {
            throw DynamicPluginSupportTestError.templateScriptNotFound("any template script")
        }

        return try scripts
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func templateScriptFiles() throws -> [URL] {
        try Self.files(under: templateRoot).filter { url in
            let path = url.path.lowercased()
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".sh")
                || path.contains("/script")
                || name.contains("validate")
                || name.contains("install")
        }
    }

    private static func files(under relativePath: String) throws -> [URL] {
        let fileManager = FileManager.default
        let root = try Self.packageRoot().appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw DynamicPluginSupportTestError.templateDirectoryNotFound(relativePath)
        }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DynamicPluginSupportTestError.templateDirectoryNotFound(relativePath)
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                urls.append(url)
            }
        }
        return urls.sorted { $0.path < $1.path }
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
                throw DynamicPluginSupportTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func relativePath(for url: URL) throws -> String {
        let root = try Self.packageRoot().path
        guard url.path.hasPrefix(root) else {
            return url.path
        }
        return String(url.path.dropFirst(root.count + 1))
    }

    private static func bracedDeclarationBlock(
        in source: String,
        startingAt marker: String
    ) throws -> String {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.lowerBound...].firstIndex(of: "{")
        else {
            throw DynamicPluginSupportTestError.declarationNotFound(marker)
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[markerRange.lowerBound...index])
                }
            }
            index = source.index(after: index)
        }

        throw DynamicPluginSupportTestError.unbalancedDeclaration(marker)
    }

    private static func runShellScript(_ script: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            error: String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private static func expectContains(
        _ contents: String,
        _ requiredTerms: [String]
    ) {
        for term in requiredTerms {
            #expect(contents.contains(term), "Missing expected content: \(term)")
        }
    }

    private static func expectDoesNotContain(
        _ contents: String,
        _ forbiddenTerms: [String]
    ) {
        for term in forbiddenTerms {
            #expect(!contents.contains(term), "Found forbidden content: \(term)")
        }
    }

    private static let requiredGStreamerModules = [
        "gstreamer-1.0",
        "gstreamer-app-1.0",
        "gstreamer-video-1.0",
        "gstreamer-base-1.0",
    ]
}

private func swiftGstTestDynamicPluginInitCallback(
    _ rawPlugin: OpaquePointer?,
    _ userData: UnsafeMutableRawPointer?
) -> gboolean {
    guard let userData else {
        return 0
    }

    let probe = Unmanaged<DynamicPluginCallbackProbe>.fromOpaque(userData).takeUnretainedValue()
    return probe.run(rawPlugin: rawPlugin)
}

private final class DynamicPluginCallbackProbe: @unchecked Sendable {
    let operation: DynamicPluginProbeOperation
    let prefix: String
    private let state = Mutex(DynamicPluginCallbackState())

    init(operation: DynamicPluginProbeOperation, prefix: String) {
        self.operation = operation
        self.prefix = prefix
    }

    var expectedFactoryNames: [String] {
        switch operation {
        case .registerAllKinds:
            [
                "\(prefix)_sink",
                "\(prefix)_in_place",
                "\(prefix)_fixed",
                "\(prefix)_general",
            ]
        case .invalidGroup(let invalidCase):
            invalidCase.factoriesExpectedAbsent(prefix: prefix)
        }
    }

    func snapshot() -> DynamicPluginCallbackState {
        state.withLock { $0 }
    }

    func run(rawPlugin: OpaquePointer?) -> gboolean {
        state.withLock {
            $0.wasCalled = true
            $0.rawPluginWasNonNil = rawPlugin != nil
        }

        guard let rawPlugin else {
            record(error: DynamicPluginSupportTestError.missingPluginPointer)
            return 0
        }

        do {
            try GStreamer.withDynamicPluginContext(rawPlugin: rawPlugin) { plugin in
                switch operation {
                case .registerAllKinds:
                    try registerAllKinds(into: plugin)
                case .invalidGroup(let invalidCase):
                    try registerInvalidGroup(invalidCase, into: plugin)
                }
            }
            state.withLock { $0.succeeded = true }
            return 1
        } catch {
            record(error: error)
            return 0
        }
    }

    private func registerAllKinds(
        into plugin: borrowing NativeElementDynamicPluginContext
    ) throws {
        try GStreamer.registerDynamicPluginElements(into: plugin) {
            DynamicPluginSupportTests.makeSink(
                factoryName: "\(prefix)_sink",
                typeName: "SwiftGstDynamicAllKindsSink"
            )
            DynamicPluginSupportTests.makeInPlaceTransform(
                factoryName: "\(prefix)_in_place",
                typeName: "SwiftGstDynamicAllKindsInPlaceTransform"
            )
            DynamicPluginSupportTests.makeFixedOutOfPlaceTransform(
                factoryName: "\(prefix)_fixed",
                typeName: "SwiftGstDynamicAllKindsFixedTransform"
            )
            DynamicPluginSupportTests.makeGeneralOutOfPlaceTransform(
                factoryName: "\(prefix)_general",
                typeName: "SwiftGstDynamicAllKindsGeneralTransform"
            )
        }
    }

    private func registerInvalidGroup(
        _ invalidCase: DynamicInvalidGroupCase,
        into plugin: borrowing NativeElementDynamicPluginContext
    ) throws {
        switch invalidCase {
        case .emptyElementGroup:
            try GStreamer.registerDynamicPluginElements(into: plugin) {}
        case .invalidElementDefinition:
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_bad_caps",
                    typeName: "SwiftGstDynamicInvalidBadCapsSink",
                    sinkCaps: "video/x-raw,format=(string"
                )
            }
        case .duplicateFactoryNamesWithinGroup:
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_duplicate",
                    typeName: "SwiftGstDynamicInvalidDuplicateFactoryOneSink"
                )
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_duplicate",
                    typeName: "SwiftGstDynamicInvalidDuplicateFactoryTwoSink"
                )
            }
        case .duplicateExplicitGTypeNamesWithinGroup:
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_explicit_one",
                    typeName: "SwiftGstDynamicInvalidDuplicateTypeSink"
                )
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_explicit_two",
                    typeName: "SwiftGstDynamicInvalidDuplicateTypeSink"
                )
            }
        case .duplicateGeneratedGTypeNamesWithinGroup:
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(factoryName: "\(prefix)_generated_duplicate")
                DynamicPluginSupportTests.makeSink(factoryName: "\(prefix)_generated_duplicate")
            }
        case .explicitAndGeneratedGTypeNamesCollideWithinGroup:
            let generatedFactory = "\(prefix)_generated"
            let generatedType = NativeElementTypeName.generatedBaseSinkTypeName(factoryName: generatedFactory)
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(factoryName: generatedFactory)
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_explicit",
                    typeName: generatedType
                )
            }
        case .factoryNameAlreadyRegisteredInProcess:
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_existing_factory",
                    typeName: "SwiftGstDynamicInvalidRegisteredFactoryGroupedSink"
                )
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_new_factory",
                    typeName: "SwiftGstDynamicInvalidRegisteredFactoryNewSink"
                )
            }
        case .gTypeNameAlreadyRegisteredInProcess:
            try GStreamer.registerDynamicPluginElements(into: plugin) {
                DynamicPluginSupportTests.makeSink(
                    factoryName: "\(prefix)_new_type_user",
                    typeName: "SwiftGstDynamicInvalidRegisteredTypeSink"
                )
            }
        }
    }

    private func record(error: Error) {
        let description: String
        let invalidParameter: String?

        if case GStreamerError.invalidArgument(let parameter, let reason) = error {
            description = reason
            invalidParameter = parameter
        } else {
            description = String(describing: error)
            invalidParameter = nil
        }

        state.withLock {
            $0.errorDescription = description
            $0.invalidArgumentParameter = invalidParameter
        }
    }
}

private enum DynamicPluginProbeOperation: Sendable {
    case registerAllKinds
    case invalidGroup(DynamicInvalidGroupCase)
}

private struct DynamicPluginCallbackState: Sendable {
    var wasCalled = false
    var rawPluginWasNonNil = false
    var succeeded = false
    var errorDescription: String?
    var invalidArgumentParameter: String?
}

private enum DynamicInvalidGroupCase: String, CaseIterable, Sendable {
    case emptyElementGroup
    case invalidElementDefinition
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
        case .invalidElementDefinition:
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

    var suffix: String {
        switch self {
        case .emptyElementGroup:
            "empty"
        case .invalidElementDefinition:
            "bad_caps"
        case .duplicateFactoryNamesWithinGroup:
            "duplicate_factory"
        case .duplicateExplicitGTypeNamesWithinGroup:
            "duplicate_type"
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

    func factoriesExpectedAbsent(prefix: String) -> [String] {
        switch self {
        case .emptyElementGroup:
            []
        case .invalidElementDefinition:
            ["\(prefix)_bad_caps"]
        case .duplicateFactoryNamesWithinGroup:
            ["\(prefix)_duplicate"]
        case .duplicateExplicitGTypeNamesWithinGroup:
            ["\(prefix)_explicit_one", "\(prefix)_explicit_two"]
        case .duplicateGeneratedGTypeNamesWithinGroup:
            ["\(prefix)_generated_duplicate"]
        case .explicitAndGeneratedGTypeNamesCollideWithinGroup:
            ["\(prefix)_generated", "\(prefix)_explicit"]
        case .factoryNameAlreadyRegisteredInProcess:
            ["\(prefix)_new_factory"]
        case .gTypeNameAlreadyRegisteredInProcess:
            ["\(prefix)_new_type_user"]
        }
    }
}

private struct TemplateFile: Sendable {
    var path: String
    var url: URL
    var contents: String
}

private struct ProcessResult: Sendable {
    var exitCode: Int32
    var output: String
    var error: String

    var combinedOutput: String {
        "\(output)\n\(error)"
    }
}

private final class DynamicPluginNoopSink: SwiftBaseSinkInstance {
    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}

private final class DynamicPluginNoopTransform: SwiftBaseTransformInstance {
    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}

private final class DynamicPluginNoopOutOfPlaceTransform: SwiftBaseTransformOutOfPlaceInstance {
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
        return .ok
    }
}

private enum DynamicPluginSupportTestError: Error, CustomStringConvertible, Sendable {
    case packageRootNotFound(String)
    case templateDirectoryNotFound(String)
    case templateScriptNotFound(String)
    case templateSourceNotFound([String])
    case declarationNotFound(String)
    case unbalancedDeclaration(String)
    case workflowJobNotFound(String)
    case workflowStepNotFound(String)
    case testPluginRegistrationFailed(String, String?)
    case missingPluginPointer

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not find Package.swift while walking up from \(filePath)"
        case .templateDirectoryNotFound(let path):
            "Could not find dynamic plugin template directory at \(path)"
        case .templateScriptNotFound(let terms):
            "Could not find dynamic plugin template script containing \(terms)"
        case .templateSourceNotFound(let terms):
            "Could not find dynamic plugin template source containing \(terms.joined(separator: ", "))"
        case .declarationNotFound(let marker):
            "Could not find declaration starting with \(marker)"
        case .unbalancedDeclaration(let marker):
            "Could not parse declaration block starting with \(marker)"
        case .workflowJobNotFound(let jobName):
            "Could not find workflow job named \(jobName)"
        case .workflowStepNotFound(let stepName):
            "Could not find workflow step named \(stepName)"
        case .testPluginRegistrationFailed(let name, let diagnostic):
            "Could not register test plugin \(name): \(diagnostic ?? "no callback diagnostic")"
        case .missingPluginPointer:
            "Test static plugin callback received a nil GstPlugin pointer"
        }
    }
}
