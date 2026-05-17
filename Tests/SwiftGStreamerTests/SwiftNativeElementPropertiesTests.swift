import Foundation
import Synchronization
import Testing
import CGStreamer
import CGStreamerShim
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Swift Native Element GObject Property Tests", .serialized, .timeLimit(.minutes(1)))
struct SwiftNativeElementPropertiesTests {
    init() throws {
        try GStreamer.initialize()
    }

    @Test("Native element authors declare supported properties")
    func nativeElementAuthorsDeclareSupportedProperties() throws {
        // Given a Swift native BaseSink or in-place BaseTransform author has valid element metadata and caps
        let enumCase = NativeElementEnumCase(
            name: "fast",
            nick: "quick",
            blurb: "Fast mode"
        )
        #expect(enumCase.name == "fast")
        #expect(enumCase.nick == "quick")
        #expect(enumCase.blurb == "Fast mode")

        // When the author registers the element with Bool, Int, Double, nullable String, and string-backed enum properties
        let sinkRecorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: "swiftnativeprops_authors_sink",
                typeName: "SwiftGstTestNativePropertiesAuthorsSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: sinkRecorder
            )
        )
        let transformRecorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeTransformElement(
                factoryName: "swiftnativeprops_authors_transform",
                typeName: "SwiftGstTestNativePropertiesAuthorsTransform",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: transformRecorder
            )
        )

        // Then registration accepts the supported property declarations
        #expect(Self.elementFactoryExists("swiftnativeprops_authors_sink"))
        #expect(Self.elementFactoryExists("swiftnativeprops_authors_transform"))

        // And enum case declarations preserve canonical names, optional nicks, and optional blurbs
        let nickedDefault = NativeElementProperty.stringEnum(
            name: "mode",
            default: "quick",
            cases: [
                NativeElementEnumCase(name: "balanced", nick: "bal", blurb: "Balanced mode"),
                enumCase,
            ],
            blurb: "Processing mode"
        )
        _ = nickedDefault

        // And existing registrations without properties still compile and register unchanged
        try GStreamer.register(
            Self.makeNoPropertySinkElement(
                factoryName: "swiftnativeprops_no_property_sink",
                typeName: "SwiftGstTestNativePropertiesNoPropertySink"
            )
        )
        try GStreamer.register(
            Self.makeNoPropertyTransformElement(
                factoryName: "swiftnativeprops_no_property_transform",
                typeName: "SwiftGstTestNativePropertiesNoPropertyTransform"
            )
        )
        #expect(Self.elementFactoryExists("swiftnativeprops_no_property_sink"))
        #expect(Self.elementFactoryExists("swiftnativeprops_no_property_transform"))

        // And invalid property names, duplicate names, inherited names, invalid ranges, and invalid enum schemas fail before C registration
        for scenario in NativePropertyTestSchema.invalidPropertyScenarios() {
            try Self.expectInvalidSinkProperties(
                scenario.properties,
                factoryName: "swiftnativeprops_invalid_sink_\(scenario.suffix)",
                typeName: "SwiftGstTestInvalidSink\(scenario.typeSuffix)Properties"
            )
        }
        try Self.expectInvalidTransformProperties(
            [
                .bool(
                    name: "name",
                    default: true,
                    blurb: "Collides with inherited GstObject name"
                ),
            ],
            factoryName: "swiftnativeprops_invalid_transform_inherited",
            typeName: "SwiftGstTestInvalidTransformInheritedProperties"
        )
    }

    @Test("Generated classes expose real GObject properties")
    func generatedClassesExposeRealGObjectProperties() throws {
        // Given a Swift-backed native element is registered with declared properties
        let factoryName = "swiftnativeprops_param_specs_sink"
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesParamSpecsSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: NativePropertyObservationRecorder()
            )
        )

        // When GStreamer initializes the generated element class
        let element = try Element.make(factory: factoryName)

        // Then one readable and writable GObject property is installed for each declaration
        for propertyName in NativePropertyTestSchema.propertyNames {
            let property = try #require(element.property(named: propertyName))
            #expect(property.isReadable)
            #expect(property.isWritable)
        }

        // And Bool, Int, Double, and String declarations use matching GObject param spec value types
        try Self.expectProperty(
            element,
            name: NativePropertyTestSchema.boolName,
            type: .boolean,
            defaultValue: "true",
            description: "Enable processing"
        )
        try Self.expectProperty(
            element,
            name: NativePropertyTestSchema.intName,
            type: .int,
            defaultValue: "3",
            description: "Processing count"
        )
        try Self.expectProperty(
            element,
            name: NativePropertyTestSchema.doubleName,
            type: .double,
            defaultValue: "0.25",
            description: "Processing strength"
        )
        try Self.expectProperty(
            element,
            name: NativePropertyTestSchema.stringName,
            type: .string,
            defaultValue: nil,
            description: "Optional label"
        )

        let intSpec = try #require(Self.intSpec(element, propertyName: NativePropertyTestSchema.intName))
        #expect(intSpec.pointee.minimum == 0)
        #expect(intSpec.pointee.maximum == 10)

        let doubleSpec = try #require(
            Self.doubleSpec(element, propertyName: NativePropertyTestSchema.doubleName)
        )
        #expect(doubleSpec.pointee.minimum == 0.0)
        #expect(doubleSpec.pointee.maximum == 1.0)

        // And string-backed enum declarations are exposed as string properties with canonical case-name defaults
        try Self.expectProperty(
            element,
            name: NativePropertyTestSchema.enumName,
            type: .string,
            defaultValue: nil,
            description: "Processing mode"
        )
        #expect(
            Self.stringDefaultValue(element, propertyName: NativePropertyTestSchema.enumName) == "balanced"
        )

        // And all declared properties are mutable while the element is playing
        for propertyName in NativePropertyTestSchema.propertyNames {
            #expect(try Self.propertyIsMutableWhilePlaying(element, propertyName: propertyName))
        }
    }

    @Test("Generated numeric properties expose declared GParamSpec ranges")
    func generatedNumericPropertiesExposeDeclaredGParamSpecRanges() throws {
        // Given a Swift-backed native element is registered with Int and Double property declarations
        let factoryName = "swiftnativeprops_declared_ranges_sink"
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesDeclaredRangesSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: NativePropertyObservationRecorder()
            )
        )

        // When GStreamer initializes the generated element class
        let element = try Element.make(factory: factoryName)

        // Then the installed Int GObject param spec exposes the declared minimum and maximum
        let intSpec = try #require(Self.intSpec(element, propertyName: NativePropertyTestSchema.intName))
        #expect(intSpec.pointee.minimum == 0)
        #expect(intSpec.pointee.maximum == 10)

        // And the installed Double GObject param spec exposes the declared minimum and maximum
        let doubleSpec = try #require(
            Self.doubleSpec(element, propertyName: NativePropertyTestSchema.doubleName)
        )
        #expect(doubleSpec.pointee.minimum == 0.0)
        #expect(doubleSpec.pointee.maximum == 1.0)
    }

    @Test("Invalid internal numeric callback values preserve the previous valid value")
    func invalidInternalNumericCallbackValuesPreserveThePreviousValidValue() throws {
        // Given a Swift-backed native element has current valid Int and Double property values
        let factoryName = "swiftnativeprops_internal_numeric_callback_sink"
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesInternalNumericCallbackSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: NativePropertyObservationRecorder()
            )
        )
        let element = try Element.make(factory: factoryName)
        element.set(NativePropertyTestSchema.intName, 7)
        element.set(NativePropertyTestSchema.doubleName, 0.7)
        #expect(element.getInt(NativePropertyTestSchema.intName) == 7)
        #expect(abs(element.getDouble(NativePropertyTestSchema.doubleName) - 0.7) < 0.000_001)

        // When the generated class property callback receives numeric values outside the declared ranges
        #expect(
            Self.invokeInternalNumericSetPropertyCallbacks(
                element,
                intValue: 99,
                doubleValue: 9.9
            )
        )

        // Then the Swift property store preserves the previous valid values
        #expect(element.getInt(NativePropertyTestSchema.intName) == 7)
        #expect(abs(element.getDouble(NativePropertyTestSchema.doubleName) - 0.7) < 0.000_001)
    }

    @Test("Public numeric Element.set out-of-range values preserve previous values")
    func publicNumericElementSetOutOfRangeValuesPreservePreviousValues() throws {
        // Given a Swift-backed native element has current valid Int and Double property values
        let factoryName = "swiftnativeprops_public_numeric_range_sink"
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesPublicNumericRangeSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: NativePropertyObservationRecorder()
            )
        )
        let element = try Element.make(factory: factoryName)
        element.set(NativePropertyTestSchema.intName, 7)
        element.set(NativePropertyTestSchema.doubleName, 0.7)
        #expect(element.getInt(NativePropertyTestSchema.intName) == 7)
        #expect(abs(element.getDouble(NativePropertyTestSchema.doubleName) - 0.7) < 0.000_001)

        // When the caller sets Int and Double values outside the declared ranges through public Element.set
        #expect(
            Self.withExpectedGObjectCriticals(
                firstFragment: "property 'count'",
                secondFragment: "property 'strength'"
            ) {
                element.set(NativePropertyTestSchema.intName, 99)
                element.set(NativePropertyTestSchema.doubleName, 9.9)
            }
        )

        // Then the public Element getters still return the previous valid numeric values
        #expect(element.getInt(NativePropertyTestSchema.intName) == 7)
        #expect(abs(element.getDouble(NativePropertyTestSchema.doubleName) - 0.7) < 0.000_001)

        // Given the element has rejected out-of-range numeric setter calls
        // When the caller sets valid numeric boundary values through public Element.set
        element.set(NativePropertyTestSchema.intName, 10)
        element.set(NativePropertyTestSchema.doubleName, 1.0)

        // Then the public Element getters return the valid boundary values
        #expect(element.getInt(NativePropertyTestSchema.intName) == 10)
        #expect(abs(element.getDouble(NativePropertyTestSchema.doubleName) - 1.0) < 0.000_001)
    }

    @Test("GLib critical log helpers use shared synchronization")
    func glibCriticalLogHelpersUseSharedSynchronization() throws {
        // Given one test helper temporarily makes GLib critical logs fatal
        let root = try Self.packageRoot()
        let elementTests = try Self.contents(
            of: root.appendingPathComponent("Tests/SwiftGStreamerTests/ElementTests.swift")
        )
        let fatalCriticalHelper = try Self.functionBody(
            named: "withFatalGStreamerCriticalTrap",
            in: elementTests
        )

        #expect(
            Self.tokensAppearInOrder(
                [
                    "swift_gst_test_lock_glib_log_state",
                    "swift_gst_test_enable_fatal_criticals",
                ],
                in: fatalCriticalHelper
            )
        )
        #expect(
            Self.tokensAppearInOrder(
                [
                    "swift_gst_test_restore_fatal_mask",
                    "swift_gst_test_unlock_glib_log_state",
                ],
                in: fatalCriticalHelper
            )
        )

        // When another test helper expects public setter GLib-GObject critical diagnostics
        let nativePropertiesTests = try Self.contents(
            of: root.appendingPathComponent("Tests/SwiftGStreamerTests/SwiftNativeElementPropertiesTests.swift")
        )
        let publicSetterTest = try Self.functionBody(
            named: "publicNumericElementSetOutOfRangeValuesPreservePreviousValues",
            in: nativePropertiesTests
        )
        let expectedCriticalHelper = try Self.functionBody(
            named: "withExpectedGObjectCriticals",
            in: nativePropertiesTests
        )

        #expect(
            Self.tokensAppearInOrder(
                [
                    "Self.withExpectedGObjectCriticals",
                    "element.set(NativePropertyTestSchema.intName, 99)",
                    "element.set(NativePropertyTestSchema.doubleName, 9.9)",
                ],
                in: publicSetterTest
            )
        )
        #expect(
            Self.tokensAppearInOrder(
                [
                    "swift_gst_test_lock_glib_log_state",
                    "swift_gst_test_expect_gobject_criticals_begin",
                    "body()",
                    "swift_gst_test_expect_gobject_criticals_end",
                    "swift_gst_test_unlock_glib_log_state",
                ],
                in: expectedCriticalHelper
            )
        )

        // Then both affected tests coordinate through the same shared log-state synchronization point
        let testSupportHeader = try Self.contents(
            of: root.appendingPathComponent("Tests/CGStreamerTestSupport/include/CGStreamerTestSupport.h")
        )
        #expect(
            Self.containsRegex(
                #"typedef\s+struct\s+SwiftGstTestExpectedCriticals\s+SwiftGstTestExpectedCriticals\s*;"#,
                in: testSupportHeader
            )
        )
        #expect(
            Self.containsRegex(
                #"void\s+swift_gst_test_lock_glib_log_state\s*\(\s*void\s*\)\s*;"#,
                in: testSupportHeader
            )
        )
        #expect(
            Self.containsRegex(
                #"void\s+swift_gst_test_unlock_glib_log_state\s*\(\s*void\s*\)\s*;"#,
                in: testSupportHeader
            )
        )
        #expect(
            Self.containsRegex(
                #"SwiftGstTestExpectedCriticals\s*\*\s*swift_gst_test_expect_gobject_criticals_begin\s*\(\s*const\s+gchar\s*\*\s*\w+\s*,\s*const\s+gchar\s*\*\s*\w+\s*\)\s*;"#,
                in: testSupportHeader
            )
        )
        #expect(
            Self.containsRegex(
                #"gboolean\s+swift_gst_test_expect_gobject_criticals_end\s*\(\s*SwiftGstTestExpectedCriticals\s*\*\s*\w+\s*\)\s*;"#,
                in: testSupportHeader
            )
        )
        #expect(
            Self.containsRegex(
                #"void\s+swift_gst_test_emit_gobject_critical\s*\(\s*const\s+gchar\s*\*\s*\w+\s*\)\s*;"#,
                in: testSupportHeader
            )
        )
    }

    @Test("Expected GObject critical helper fails when expected message is missing")
    func expectedGObjectCriticalHelperFailsWhenExpectedMessageIsMissing() throws {
        // Given a test helper expects a specific GLib-GObject critical diagnostic
        // When the expected diagnostic is not emitted
        // Then the helper reports the missing diagnostic as a test failure signal
        #expect(
            !Self.withExpectedGObjectCriticals(
                firstFragment: "expected missing native property critical",
                secondFragment: "expected missing native property critical"
            ) {}
        )
    }

    @Test("Expected GObject critical helper fails when unexpected message is observed")
    func expectedGObjectCriticalHelperFailsWhenUnexpectedMessageIsObserved() throws {
        // Given a test helper expects a specific GLib-GObject critical diagnostic
        // When a different GLib-GObject critical diagnostic is emitted
        // Then the helper reports the unexpected diagnostic as a test failure signal
        #expect(
            !Self.withExpectedGObjectCriticals(
                firstFragment: "expected native property critical",
                secondFragment: "expected native property critical"
            ) {
                "different native property critical".withCString {
                    swift_gst_test_emit_gobject_critical($0)
                }
            }
        )
    }

    @Test("Property values bridge deterministically between GObject and Swift")
    func propertyValuesBridgeDeterministicallyBetweenGObjectAndSwift() throws {
        // Given a registered Swift-backed native element has declared properties and a Swift property store
        let factoryName = "swiftnativeprops_bridge_sink"
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesBridgeSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: NativePropertyObservationRecorder()
            )
        )
        let element = try Element.make(factory: factoryName)

        // When GObject sets or gets Bool, Int, Double, nullable String, and string-backed enum values by property ID
        let propertyIDs = NativePropertyTestSchema.propertyNames.map {
            Self.propertyID(element, propertyName: $0)
        }

        // Then property ID zero remains reserved and declared property IDs map to declaration order
        #expect(propertyIDs == [1, 2, 3, 4, 5])
        #expect(!propertyIDs.contains(0))

        // And valid set operations update the Swift store using copied values at the callback boundary
        element.set(NativePropertyTestSchema.boolName, false)
        element.set(NativePropertyTestSchema.intName, 9)
        element.set(NativePropertyTestSchema.doubleName, 0.75)
        element.set(NativePropertyTestSchema.stringName, "runtime-label")
        element.set(NativePropertyTestSchema.enumName, "fast")
        #expect(element.getBool(NativePropertyTestSchema.boolName) == false)
        #expect(element.getInt(NativePropertyTestSchema.intName) == 9)
        #expect(abs(element.getDouble(NativePropertyTestSchema.doubleName) - 0.75) < 0.000_001)
        #expect(element.getString(NativePropertyTestSchema.stringName) == "runtime-label")
        #expect(element.getString(NativePropertyTestSchema.enumName) == "fast")

        // And get operations return current store values or descriptor defaults when no Swift instance context exists
        var defaults = Self.missingInstanceDefaultsProbe(element, isBaseTransform: false)
        defer { swift_gst_test_native_property_defaults_probe_result_clear(&defaults) }
        #expect(defaults.success != 0)
        #expect(defaults.bool_value != 0)
        #expect(defaults.int_value == 3)
        #expect(abs(defaults.double_value - 0.25) < 0.000_001)
        #expect(Self.copiedString(defaults.string_value) == nil)
        #expect(Self.copiedString(defaults.enum_value) == "balanced")

        // And raw GValue pointers and borrowed C strings do not escape into public Swift APIs
        let nativeSource = try NativeElementSourceLayoutTestSupport.nativeElementSwiftSource()
        #expect(!Self.containsRegex(#"public\s+[^\n]*(GValue|gchar|CChar)"#, in: nativeSource))
    }

    @Test("Swift callbacks read defaults and configured values")
    func swiftCallbacksReadDefaultsAndConfiguredValues() async throws {
        // Given a Swift-backed native element instance receives an injected property reader
        let factoryName = "swiftnativeprops_callbacks_sink"
        let recorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesCallbacksSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: recorder
            )
        )
        _ = try Element.make(factory: factoryName)

        // When lifecycle and buffer callbacks run before and after valid property updates
        try await Self.runFiniteVideoPipeline(
            """
            videotestsrc num-buffers=1 ! \(NativePropertyTestSchema.videoCaps) ! \
            \(factoryName) enabled=false count=8 strength=0.8 label=callback-label mode=quick
            """
        )
        let snapshot = recorder.snapshot()
        let initialObservation = try #require(snapshot.makeInstanceObservations.first)
        let renderObservation = try #require(snapshot.renderObservations.last)

        // Then the reader returns declared defaults before updates
        Self.expectObservation(initialObservation, matches: .defaults)

        // And the reader returns the latest valid Bool, Int, Double, String, and enum values after updates
        Self.expectObservation(
            renderObservation,
            matches: .configured(
                bool: false,
                int: 8,
                double: 0.8,
                string: "callback-label",
                enumCase: "fast"
            )
        )

        // And string reads return nil for unknown properties, enum properties, and nil string values
        #expect(initialObservation.stringValue == nil)
        #expect(initialObservation.unknownStringValue == nil)
        #expect(initialObservation.enumStringValue == nil)
        #expect(renderObservation.unknownStringValue == nil)
        #expect(renderObservation.enumStringValue == nil)

        // And enum reads return canonical case names for exact case-name or nick inputs
        #expect(renderObservation.enumValue == "fast")
    }

    @Test("Pipeline strings configure Swift-backed elements")
    func pipelineStringsConfigureSwiftBackedElements() async throws {
        // Given Swift-backed BaseSink and in-place BaseTransform factories declare properties
        let sinkFactoryName = "swiftnativeprops_pipeline_sink"
        let sinkRecorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: sinkFactoryName,
                typeName: "SwiftGstTestNativePropertiesPipelineSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: sinkRecorder
            )
        )

        let transformFactoryName = "swiftnativeprops_pipeline_transform"
        let transformRecorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeTransformElement(
                factoryName: transformFactoryName,
                typeName: "SwiftGstTestNativePropertiesPipelineTransform",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: transformRecorder
            )
        )

        // When finite GStreamer pipeline strings set those properties through normal launch syntax
        try await Self.runFiniteVideoPipeline(
            """
            videotestsrc num-buffers=1 ! \(NativePropertyTestSchema.videoCaps) ! \
            \(sinkFactoryName) enabled=false count=4 strength=0.5 label=sink-label mode=fast
            """
        )
        try await Self.runFiniteVideoPipeline(
            """
            videotestsrc num-buffers=1 ! \(NativePropertyTestSchema.videoCaps) ! \
            \(transformFactoryName) enabled=false count=6 strength=0.6 label=transform-label mode=quick ! \
            fakesink sync=false
            """
        )

        // Then the pipelines reach end-of-stream
        let sinkSnapshot = sinkRecorder.snapshot()
        let transformSnapshot = transformRecorder.snapshot()
        #expect(sinkSnapshot.renderObservations.count == 1)
        #expect(transformSnapshot.transformObservations.count == 1)

        // And the BaseSink render callback observes the configured values
        Self.expectObservation(
            try #require(sinkSnapshot.renderObservations.last),
            matches: .configured(
                bool: false,
                int: 4,
                double: 0.5,
                string: "sink-label",
                enumCase: "fast"
            )
        )

        // And the BaseTransform transform callback is exercised and observes the configured values
        Self.expectObservation(
            try #require(transformSnapshot.transformObservations.last),
            matches: .configured(
                bool: false,
                int: 6,
                double: 0.6,
                string: "transform-label",
                enumCase: "fast"
            )
        )

        // And unknown properties fail through normal GStreamer parse behavior
        let error = Self.captureError {
            _ = try Pipeline(
                """
                videotestsrc num-buffers=1 ! \(NativePropertyTestSchema.videoCaps) ! \
                \(sinkFactoryName) does-not-exist=1
                """
            )
        }
        Self.expectParsePipelineError(try #require(error))
    }

    @Test("Runtime property updates are visible and safe")
    func runtimePropertyUpdatesAreVisibleAndSafe() async throws {
        // Given a pipeline has created a Swift-backed native element with declared properties
        let factoryName = "swiftnativeprops_runtime_sink"
        let recorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesRuntimeSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: recorder
            )
        )
        let pipeline = try Pipeline(
            """
            appsrc name=src is-live=false format=time do-timestamp=false ! \
            \(NativePropertyTestSchema.videoCaps) ! \(factoryName) name=target
            """
        )
        let source = try AppSource(pipeline: pipeline, name: "src")
        let target = try #require(pipeline.element(named: "target"))
        source.setCaps(NativePropertyTestSchema.videoCaps)

        try pipeline.play()
        defer { pipeline.stop() }

        // When a controller updates Bool, Int, Double, String, and enum properties through existing Element APIs
        try await Self.stressRuntimePropertyAccess(element: target, source: source, recorder: recorder)
        let concurrentObservationCount = recorder.snapshot().renderObservations.count
        #expect(concurrentObservationCount > 0)

        target.set(NativePropertyTestSchema.boolName, false)
        target.set(NativePropertyTestSchema.intName, 10)
        target.set(NativePropertyTestSchema.doubleName, 1.0)
        target.set(NativePropertyTestSchema.stringName, "runtime-updated")
        target.set(NativePropertyTestSchema.enumName, "quick")

        // Then Element getters return the current values for matching properties
        #expect(target.getBool(NativePropertyTestSchema.boolName) == false)
        #expect(target.getInt(NativePropertyTestSchema.intName) == 10)
        #expect(abs(target.getDouble(NativePropertyTestSchema.doubleName) - 1.0) < 0.000_001)
        #expect(target.getString(NativePropertyTestSchema.stringName) == "runtime-updated")
        #expect(target.getString(NativePropertyTestSchema.enumName) == "fast")

        // And later Swift callbacks observe the valid runtime updates
        try source.push(
            data: NativePropertyTestSchema.rgbFrame,
            pts: 0,
            duration: NativePropertyTestSchema.frameDuration
        )
        source.endOfStream()
        try await Self.withTimeout(.seconds(2)) {
            try await pipeline.bus.waitForEOSOrError()
        }
        Self.expectObservation(
            try #require(recorder.snapshot().renderObservations.last),
            matches: .configured(
                bool: false,
                int: 10,
                double: 1.0,
                string: "runtime-updated",
                enumCase: "fast"
            )
        )

        // And concurrent property sets, gets, and callback reads do not crash or expose partial values
        for observation in recorder.snapshot().renderObservations {
            #expect(observation.intValue.map { (0...10).contains($0) } ?? false)
            #expect(observation.doubleValue.map { (0.0...1.0).contains($0) } ?? false)
            #expect(observation.enumValue.map { ["balanced", "fast"].contains($0) } ?? false)
        }
    }

    @Test("Invalid runtime enum values preserve the last valid value")
    func invalidRuntimeEnumValuesPreserveTheLastValidValue() async throws {
        // Given a Swift-backed native element has current valid Int, Double, and enum property values
        let factoryName = "swiftnativeprops_invalid_runtime_sink"
        let recorder = NativePropertyObservationRecorder()
        try GStreamer.register(
            Self.makeSinkElement(
                factoryName: factoryName,
                typeName: "SwiftGstTestNativePropertiesInvalidRuntimeSink",
                properties: NativePropertyTestSchema.supportedProperties(),
                recorder: recorder
            )
        )
        let pipeline = try Pipeline(
            """
            appsrc name=src is-live=false format=time do-timestamp=false ! \
            \(NativePropertyTestSchema.videoCaps) ! \(factoryName) name=target
            """
        )
        let source = try AppSource(pipeline: pipeline, name: "src")
        let target = try #require(pipeline.element(named: "target"))
        source.setCaps(NativePropertyTestSchema.videoCaps)
        target.set(NativePropertyTestSchema.intName, 7)
        target.set(NativePropertyTestSchema.doubleName, 0.7)
        target.set(NativePropertyTestSchema.enumName, "balanced")

        // When a runtime property set provides a value outside declared enum names and nicks
        target.set(NativePropertyTestSchema.enumName, "turbo")

        // Then the existing nonthrowing Element setter returns without throwing
        // And the Swift property store preserves the previous valid enum value and numeric values
        #expect(target.getInt(NativePropertyTestSchema.intName) == 7)
        #expect(abs(target.getDouble(NativePropertyTestSchema.doubleName) - 0.7) < 0.000_001)
        #expect(target.getString(NativePropertyTestSchema.enumName) == "balanced")

        // And enum values set by valid nick inputs are stored and returned as canonical case names
        target.set(NativePropertyTestSchema.enumName, "quick")
        #expect(target.getString(NativePropertyTestSchema.enumName) == "fast")

        // And Element getters and callback readers continue to return those previous valid values
        try pipeline.play()
        defer { pipeline.stop() }
        try source.push(
            data: NativePropertyTestSchema.rgbFrame,
            pts: 0,
            duration: NativePropertyTestSchema.frameDuration
        )
        source.endOfStream()
        try await Self.withTimeout(.seconds(2)) {
            try await pipeline.bus.waitForEOSOrError()
        }
        Self.expectObservation(
            try #require(recorder.snapshot().renderObservations.last),
            matches: .configured(
                bool: true,
                int: 7,
                double: 0.7,
                string: nil,
                enumCase: "fast"
            )
        )
    }

    private static func makeSinkElement(
        factoryName: String,
        typeName: String,
        properties: [NativeElementProperty],
        recorder: NativePropertyObservationRecorder
    ) -> SwiftBaseSinkElement {
        SwiftBaseSinkElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.sinkMetadata(),
            sinkCaps: NativePropertyTestSchema.videoCaps,
            properties: properties,
            makeInstance: { reader in
                NativePropertyRecordingSink(reader: reader, recorder: recorder)
            }
        )
    }

    private static func makeTransformElement(
        factoryName: String,
        typeName: String,
        properties: [NativeElementProperty],
        recorder: NativePropertyObservationRecorder
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.transformMetadata(),
            sinkCaps: NativePropertyTestSchema.videoCaps,
            srcCaps: NativePropertyTestSchema.videoCaps,
            passthroughOptions: Self.transformingOptions,
            properties: properties,
            makeInstance: { reader in
                NativePropertyRecordingTransform(reader: reader, recorder: recorder)
            }
        )
    }

    private static func makeNoPropertySinkElement(
        factoryName: String,
        typeName: String
    ) -> SwiftBaseSinkElement {
        SwiftBaseSinkElement(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.sinkMetadata(),
            sinkCaps: NativePropertyTestSchema.videoCaps,
            makeInstance: { MinimalNativePropertySink() }
        )
    }

    private static func makeNoPropertyTransformElement(
        factoryName: String,
        typeName: String
    ) -> SwiftBaseTransformElement {
        SwiftBaseTransformElement.inPlace(
            factoryName: factoryName,
            typeName: typeName,
            metadata: Self.transformMetadata(),
            sinkCaps: NativePropertyTestSchema.videoCaps,
            srcCaps: NativePropertyTestSchema.videoCaps,
            passthroughOptions: Self.transformingOptions,
            makeInstance: { MinimalNativePropertyTransform() }
        )
    }

    private static func sinkMetadata() -> NativeElementMetadata {
        NativeElementMetadata(
            klass: "Sink/Video",
            longName: "Swift native property test sink",
            description: "Swift native property test BaseSink element",
            author: "gstreamer-swift-tests"
        )
    }

    private static func transformMetadata() -> NativeElementMetadata {
        NativeElementMetadata(
            klass: "Filter/Effect/Video",
            longName: "Swift native property test transform",
            description: "Swift native property test BaseTransform element",
            author: "gstreamer-swift-tests"
        )
    }

    private static var transformingOptions: SwiftBaseTransformPassthroughOptions {
        SwiftBaseTransformPassthroughOptions(
            passthroughOnSameCaps: false,
            transformInPlaceOnPassthrough: false
        )
    }

    private static func expectInvalidSinkProperties(
        _ properties: [NativeElementProperty],
        factoryName: String,
        typeName: String
    ) throws {
        let capture = NativeElementRegistrationTestHooks.captureBaseSinkCRegistrationAttempts {
            try GStreamer.register(
                Self.makeSinkElement(
                    factoryName: factoryName,
                    typeName: typeName,
                    properties: properties,
                    recorder: NativePropertyObservationRecorder()
                )
            )
        }

        let error = try #require(capture.error)
        Self.expectInvalidArgument(error)
        #expect(capture.attemptCount == 0)
        #expect(!Self.elementFactoryExists(factoryName))
    }

    private static func expectInvalidTransformProperties(
        _ properties: [NativeElementProperty],
        factoryName: String,
        typeName: String
    ) throws {
        let capture = NativeElementRegistrationTestHooks.captureBaseTransformCRegistrationAttempts {
            try GStreamer.register(
                Self.makeTransformElement(
                    factoryName: factoryName,
                    typeName: typeName,
                    properties: properties,
                    recorder: NativePropertyObservationRecorder()
                )
            )
        }

        let error = try #require(capture.error)
        Self.expectInvalidArgument(error)
        #expect(capture.attemptCount == 0)
        #expect(!Self.elementFactoryExists(factoryName))
    }

    private static func expectInvalidArgument(_ error: Error) {
        guard case GStreamerError.invalidArgument(let parameter, let reason) = error else {
            Issue.record("Expected invalidArgument for property declaration, got \(error)")
            return
        }

        #expect(!parameter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func expectParsePipelineError(_ error: Error) {
        guard case GStreamerError.parsePipeline(let message) = error else {
            Issue.record("Expected parsePipeline for unknown native property, got \(error)")
            return
        }

        #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private static func expectProperty(
        _ element: Element,
        name: String,
        type: Element.PropertyType,
        defaultValue: String?,
        description: String
    ) throws {
        let property = try #require(element.property(named: name))
        #expect(property.valueType == type)
        #expect(property.defaultValue == defaultValue)
        #expect(property.description == description)
        #expect(property.isReadable)
        #expect(property.isWritable)
    }

    private static func expectObservation(
        _ observation: NativePropertyObservation,
        matches expected: NativePropertyExpectedObservation
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
        #expect(observation.unknownStringValue == nil)
        #expect(observation.enumStringValue == nil)
    }

    private static func paramSpec(
        _ element: Element,
        propertyName: String
    ) -> UnsafeMutablePointer<GParamSpec>? {
        let gtype = swift_g_type_from_instance(element.element)
        guard let klass = g_type_class_peek(gtype) else {
            return nil
        }

        return g_object_class_find_property(
            klass.assumingMemoryBound(to: GObjectClass.self),
            propertyName
        )
    }

    private static func intSpec(
        _ element: Element,
        propertyName: String
    ) -> UnsafeMutablePointer<GParamSpecInt>? {
        guard let spec = Self.paramSpec(element, propertyName: propertyName) else {
            return nil
        }

        return UnsafeMutableRawPointer(spec).assumingMemoryBound(to: GParamSpecInt.self)
    }

    private static func doubleSpec(
        _ element: Element,
        propertyName: String
    ) -> UnsafeMutablePointer<GParamSpecDouble>? {
        guard let spec = Self.paramSpec(element, propertyName: propertyName) else {
            return nil
        }

        return UnsafeMutableRawPointer(spec).assumingMemoryBound(to: GParamSpecDouble.self)
    }

    private static func stringDefaultValue(_ element: Element, propertyName: String) -> String? {
        guard let spec = Self.paramSpec(element, propertyName: propertyName) else {
            return nil
        }
        let stringSpec = UnsafeMutableRawPointer(spec).assumingMemoryBound(to: GParamSpecString.self)
        guard let defaultValue = stringSpec.pointee.default_value else {
            return nil
        }

        return String(cString: defaultValue)
    }

    private static func propertyIsMutableWhilePlaying(
        _ element: Element,
        propertyName: String
    ) throws -> Bool {
        let spec = try #require(Self.paramSpec(element, propertyName: propertyName))
        let mutablePlaying = swift_gst_test_param_mutable_playing().rawValue
        return (spec.pointee.flags.rawValue & mutablePlaying) != 0
    }

    private static func propertyID(_ element: Element, propertyName: String) -> UInt32 {
        propertyName.withCString { propertyName in
            swift_gst_test_element_property_id(element.element, propertyName)
        }
    }

    private static func missingInstanceDefaultsProbe(
        _ element: Element,
        isBaseTransform: Bool
    ) -> SwiftGstTestNativePropertyDefaultsProbeResult {
        NativePropertyTestSchema.boolName.withCString { boolName in
            NativePropertyTestSchema.intName.withCString { intName in
                NativePropertyTestSchema.doubleName.withCString { doubleName in
                    NativePropertyTestSchema.stringName.withCString { stringName in
                        NativePropertyTestSchema.enumName.withCString { enumName in
                            swift_gst_test_native_property_missing_instance_defaults_probe(
                                element.element,
                                isBaseTransform ? 1 : 0,
                                boolName,
                                intName,
                                doubleName,
                                stringName,
                                enumName
                            )
                        }
                    }
                }
            }
        }
    }

    private static func invokeInternalNumericSetPropertyCallbacks(
        _ element: Element,
        intValue: Int32,
        doubleValue: Double
    ) -> Bool {
        NativePropertyTestSchema.intName.withCString { intName in
            NativePropertyTestSchema.doubleName.withCString { doubleName in
                swift_gst_test_native_property_invoke_numeric_set_property_callbacks(
                    element.element,
                    intName,
                    gint(intValue),
                    doubleName,
                    gdouble(doubleValue)
                ) != 0
            }
        }
    }

    private static func withExpectedGObjectCriticals(
        firstFragment: String,
        secondFragment: String,
        _ body: () -> Void
    ) -> Bool {
        swift_gst_test_lock_glib_log_state()
        var shouldUnlock = true
        defer {
            if shouldUnlock {
                swift_gst_test_unlock_glib_log_state()
            }
        }

        let expectation = firstFragment.withCString { firstFragment in
            secondFragment.withCString { secondFragment in
                swift_gst_test_expect_gobject_criticals_begin(firstFragment, secondFragment)
            }
        }

        guard let expectation else {
            return false
        }

        body()
        let consumedExpectedCriticals = swift_gst_test_expect_gobject_criticals_end(expectation) != 0
        swift_gst_test_unlock_glib_log_state()
        shouldUnlock = false
        return consumedExpectedCriticals
    }

    private static func copiedString(_ pointer: UnsafePointer<CChar>?) -> String? {
        guard let pointer else {
            return nil
        }

        return String(cString: pointer)
    }

    private static func runFiniteVideoPipeline(_ description: String) async throws {
        let pipeline = try Pipeline(description)
        try pipeline.play()
        defer { pipeline.stop() }
        try await Self.withTimeout(.seconds(2)) {
            try await pipeline.bus.waitForEOSOrError()
        }
    }

    private static func stressRuntimePropertyAccess(
        element: Element,
        source: AppSource,
        recorder: NativePropertyObservationRecorder
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for iteration in 0..<30 {
                    try source.push(
                        data: NativePropertyTestSchema.rgbFrame,
                        pts: UInt64(iteration) * NativePropertyTestSchema.frameDuration,
                        duration: NativePropertyTestSchema.frameDuration
                    )
                    await Task.yield()
                }
            }

            for worker in 0..<4 {
                group.addTask {
                    for iteration in 0..<25 {
                        let value = (worker + iteration) % 11
                        element.set(NativePropertyTestSchema.intName, value)
                        element.set(NativePropertyTestSchema.doubleName, Double(value) / 10.0)
                        element.set(
                            NativePropertyTestSchema.enumName,
                            value.isMultiple(of: 2) ? "balanced" : "quick"
                        )
                        _ = element.getInt(NativePropertyTestSchema.intName)
                        _ = element.getDouble(NativePropertyTestSchema.doubleName)
                        _ = element.getString(NativePropertyTestSchema.enumName)
                        _ = recorder.snapshot()
                        await Task.yield()
                    }
                }
            }

            try await group.waitForAll()
        }

        try await Self.withTimeout(.seconds(2)) {
            while recorder.snapshot().renderObservations.isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
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
                throw SwiftNativeElementPropertiesTimeoutError(timeout: timeout)
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                throw SwiftNativeElementPropertiesTimeoutError(timeout: timeout)
            }
            return result
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

    private static func packageRoot(filePath: String = #filePath) throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

        while true {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                throw SwiftNativeElementPropertiesStaticError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private static func functionBody(named name: String, in source: String) throws -> String {
        guard let declaration = source.range(of: "func \(name)") else {
            throw SwiftNativeElementPropertiesStaticError.functionDeclarationNotFound(name)
        }
        guard let openingBrace = source[declaration.upperBound...].firstIndex(of: "{") else {
            throw SwiftNativeElementPropertiesStaticError.functionOpeningBraceNotFound(name)
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw SwiftNativeElementPropertiesStaticError.functionClosingBraceNotFound(name)
    }

    private static func tokensAppearInOrder(_ tokens: [String], in source: String) -> Bool {
        var lowerBound = source.startIndex
        for token in tokens {
            guard let range = source[lowerBound...].range(of: token) else {
                return false
            }
            lowerBound = range.upperBound
        }
        return true
    }

    private static func containsRegex(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}

private enum NativePropertyTestSchema {
    static let boolName = "enabled"
    static let intName = "count"
    static let doubleName = "strength"
    static let stringName = "label"
    static let enumName = "mode"
    static let propertyNames = [boolName, intName, doubleName, stringName, enumName]
    static let videoCaps = "video/x-raw,format=RGB,width=2,height=2,framerate=1/1"
    static let frameDuration: UInt64 = 33_333_333
    static let rgbFrame: [UInt8] = [
        10, 20, 30,
        40, 50, 60,
        70, 80, 90,
        100, 110, 120,
    ]

    static func supportedProperties() -> [NativeElementProperty] {
        [
            .bool(
                name: boolName,
                default: true,
                blurb: "Enable processing"
            ),
            .int(
                name: intName,
                default: 3,
                min: 0,
                max: 10,
                blurb: "Processing count"
            ),
            .double(
                name: doubleName,
                default: 0.25,
                min: 0.0,
                max: 1.0,
                blurb: "Processing strength"
            ),
            .string(
                name: stringName,
                default: Optional<String>.none,
                blurb: "Optional label"
            ),
            .stringEnum(
                name: enumName,
                default: "balanced",
                cases: [
                    NativeElementEnumCase(
                        name: "balanced",
                        nick: "bal",
                        blurb: "Balanced mode"
                    ),
                    NativeElementEnumCase(
                        name: "fast",
                        nick: "quick",
                        blurb: "Fast mode"
                    ),
                ],
                blurb: "Processing mode"
            ),
        ]
    }

    static func invalidPropertyScenarios() -> [InvalidNativePropertyScenario] {
        var scenarios: [InvalidNativePropertyScenario] = []
        let justAboveInt32Max = Int(Int32.max) + 1
        let twoAboveInt32Max = Int(Int32.max) + 2

        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "empty_name",
                typeSuffix: "EmptyName",
                properties: [
                    .bool(name: "", default: true, blurb: "Empty name"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "numeric_start",
                typeSuffix: "NumericStart",
                properties: [
                    .bool(name: "1bad", default: true, blurb: "Invalid start"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "invalid_character",
                typeSuffix: "InvalidCharacter",
                properties: [
                    .bool(name: "bad_name", default: true, blurb: "Invalid character"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "duplicate_name",
                typeSuffix: "DuplicateName",
                properties: [
                    .bool(name: boolName, default: true, blurb: "First declaration"),
                    .int(name: boolName, default: 1, min: 0, max: 10, blurb: "Duplicate"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "inherited_name",
                typeSuffix: "InheritedName",
                properties: [
                    .string(
                        name: "name",
                        default: Optional<String>.none,
                        blurb: "Inherited GstObject name"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "int_min_gt_max",
                typeSuffix: "IntMinGreaterThanMax",
                properties: [
                    .int(name: intName, default: 3, min: 10, max: 1, blurb: "Bad range"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "int_default_out_of_range",
                typeSuffix: "IntDefaultOutOfRange",
                properties: [
                    .int(name: intName, default: 11, min: 0, max: 10, blurb: "Bad default"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "int_outside_int32",
                typeSuffix: "IntOutsideInt32",
                properties: [
                    .int(
                        name: intName,
                        default: justAboveInt32Max,
                        min: 0,
                        max: twoAboveInt32Max,
                        blurb: "Out of Int32 range"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "double_not_finite",
                typeSuffix: "DoubleNotFinite",
                properties: [
                    .double(
                        name: doubleName,
                        default: Double.infinity,
                        min: 0.0,
                        max: 1.0,
                        blurb: "Non-finite default"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "double_default_out_of_range",
                typeSuffix: "DoubleDefaultOutOfRange",
                properties: [
                    .double(
                        name: doubleName,
                        default: 2.0,
                        min: 0.0,
                        max: 1.0,
                        blurb: "Bad default"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "enum_empty_cases",
                typeSuffix: "EnumEmptyCases",
                properties: [
                    .stringEnum(name: enumName, default: "balanced", cases: [], blurb: "No cases"),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "enum_duplicate_case",
                typeSuffix: "EnumDuplicateCase",
                properties: [
                    .stringEnum(
                        name: enumName,
                        default: "balanced",
                        cases: [
                            NativeElementEnumCase(name: "balanced"),
                            NativeElementEnumCase(name: "balanced"),
                        ],
                        blurb: "Duplicate case"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "enum_duplicate_nick",
                typeSuffix: "EnumDuplicateNick",
                properties: [
                    .stringEnum(
                        name: enumName,
                        default: "balanced",
                        cases: [
                            NativeElementEnumCase(name: "balanced", nick: "dup"),
                            NativeElementEnumCase(name: "fast", nick: "dup"),
                        ],
                        blurb: "Duplicate nick"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "enum_name_nick_collision",
                typeSuffix: "EnumNameNickCollision",
                properties: [
                    .stringEnum(
                        name: enumName,
                        default: "balanced",
                        cases: [
                            NativeElementEnumCase(name: "balanced", nick: "fast"),
                            NativeElementEnumCase(name: "fast"),
                        ],
                        blurb: "Name and nick collision"
                    ),
                ]
            )
        )
        scenarios.append(
            InvalidNativePropertyScenario(
                suffix: "enum_bad_default",
                typeSuffix: "EnumBadDefault",
                properties: [
                    .stringEnum(
                        name: enumName,
                        default: "turbo",
                        cases: [
                            NativeElementEnumCase(name: "balanced"),
                            NativeElementEnumCase(name: "fast"),
                        ],
                        blurb: "Invalid default"
                    ),
                ]
            )
        )

        return scenarios
    }
}

private struct InvalidNativePropertyScenario {
    var suffix: String
    var typeSuffix: String
    var properties: [NativeElementProperty]
}

private struct NativePropertyExpectedObservation {
    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringValue: String?
    var enumValue: String?

    static let defaults = NativePropertyExpectedObservation(
        boolValue: true,
        intValue: 3,
        doubleValue: 0.25,
        stringValue: nil,
        enumValue: "balanced"
    )

    static func configured(
        bool: Bool,
        int: Int,
        double: Double,
        string: String?,
        enumCase: String
    ) -> NativePropertyExpectedObservation {
        NativePropertyExpectedObservation(
            boolValue: bool,
            intValue: int,
            doubleValue: double,
            stringValue: string,
            enumValue: enumCase
        )
    }
}

private struct NativePropertyObservation: Sendable {
    var boolValue: Bool?
    var intValue: Int?
    var doubleValue: Double?
    var stringValue: String?
    var enumValue: String?
    var unknownStringValue: String?
    var enumStringValue: String?

    init(reader: NativeElementPropertyReader) {
        self.boolValue = reader.bool(NativePropertyTestSchema.boolName)
        self.intValue = reader.int(NativePropertyTestSchema.intName)
        self.doubleValue = reader.double(NativePropertyTestSchema.doubleName)
        self.stringValue = reader.string(NativePropertyTestSchema.stringName)
        self.enumValue = reader.enumCase(NativePropertyTestSchema.enumName)
        self.unknownStringValue = reader.string("unknown-property")
        self.enumStringValue = reader.string(NativePropertyTestSchema.enumName)
    }
}

private final class NativePropertyObservationRecorder: @unchecked Sendable {
    private let state = Mutex(Snapshot())

    struct Snapshot: Sendable {
        var makeInstanceObservations: [NativePropertyObservation] = []
        var startObservations: [NativePropertyObservation] = []
        var renderObservations: [NativePropertyObservation] = []
        var transformObservations: [NativePropertyObservation] = []
    }

    func recordMakeInstance(_ observation: NativePropertyObservation) {
        state.withLock { $0.makeInstanceObservations.append(observation) }
    }

    func recordStart(_ observation: NativePropertyObservation) {
        state.withLock { $0.startObservations.append(observation) }
    }

    func recordRender(_ observation: NativePropertyObservation) {
        state.withLock { $0.renderObservations.append(observation) }
    }

    func recordTransform(_ observation: NativePropertyObservation) {
        state.withLock { $0.transformObservations.append(observation) }
    }

    func snapshot() -> Snapshot {
        state.withLock { $0 }
    }
}

private final class NativePropertyRecordingSink: SwiftBaseSinkInstance {
    private let reader: NativeElementPropertyReader
    private let recorder: NativePropertyObservationRecorder

    init(reader: NativeElementPropertyReader, recorder: NativePropertyObservationRecorder) {
        self.reader = reader
        self.recorder = recorder
        recorder.recordMakeInstance(NativePropertyObservation(reader: reader))
    }

    func start() throws {
        recorder.recordStart(NativePropertyObservation(reader: reader))
    }

    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        recorder.recordRender(NativePropertyObservation(reader: reader))
        return .ok
    }
}

private final class NativePropertyRecordingTransform: SwiftBaseTransformInstance {
    private let reader: NativeElementPropertyReader
    private let recorder: NativePropertyObservationRecorder

    init(reader: NativeElementPropertyReader, recorder: NativePropertyObservationRecorder) {
        self.reader = reader
        self.recorder = recorder
        recorder.recordMakeInstance(NativePropertyObservation(reader: reader))
    }

    func start() throws {
        recorder.recordStart(NativePropertyObservation(reader: reader))
    }

    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        recorder.recordTransform(NativePropertyObservation(reader: reader))
        return .ok
    }
}

private final class MinimalNativePropertySink: SwiftBaseSinkInstance {
    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}

private final class MinimalNativePropertyTransform: SwiftBaseTransformInstance {
    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}

private struct SwiftNativeElementPropertiesTimeoutError: Error, CustomStringConvertible, Sendable {
    let timeout: Duration

    var description: String {
        "Timed out after \(timeout)"
    }
}

private enum SwiftNativeElementPropertiesStaticError: Error, CustomStringConvertible {
    case packageRootNotFound(String)
    case functionDeclarationNotFound(String)
    case functionOpeningBraceNotFound(String)
    case functionClosingBraceNotFound(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not find Package.swift while walking up from \(filePath)"
        case .functionDeclarationNotFound(let name):
            "Could not find function declaration for \(name)"
        case .functionOpeningBraceNotFound(let name):
            "Could not find opening brace for function \(name)"
        case .functionClosingBraceNotFound(let name):
            "Could not find closing brace for function \(name)"
        }
    }
}
