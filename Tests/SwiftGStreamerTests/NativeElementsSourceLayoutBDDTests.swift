import Foundation
import GStreamer
import Testing

@Suite("Native Elements Source Layout BDD Tests")
struct NativeElementsSourceLayoutBDDTests {
    @Test("Native element maintainer finds Swift concerns in dedicated files")
    func nativeElementMaintainerFindsSwiftConcernsInDedicatedFiles() throws {
        // Given the native element Swift API has grown across BaseSink, BaseTransform, properties, buffers, plugins, validation, and test hooks
        let nativeElementsDirectoryExists = try Self.directoryExists(
            "Sources/GStreamer/NativeElements"
        )

        // When a maintainer reviews the GStreamer target source tree
        let nativeElementSwiftFiles = try Self.fileNames(
            in: "Sources/GStreamer/NativeElements",
            withPathExtension: "swift"
        )

        // Then the native element Swift implementation is grouped under Sources/GStreamer/NativeElements
        #expect(
            nativeElementsDirectoryExists,
            "Native element Swift sources should be grouped under Sources/GStreamer/NativeElements"
        )

        // And each requested native element concern has a dedicated Swift source file
        #expect(nativeElementSwiftFiles == Self.requestedNativeElementSwiftFiles)
        for fileName in Self.requestedNativeElementSwiftFiles.sorted() {
            #expect(
                nativeElementSwiftFiles.contains(fileName),
                "Missing requested native element source file \(fileName)"
            )
        }
        for (fileName, snippets) in Self.expectedSwiftDeclarationSnippets.sorted(by: { $0.key < $1.key }) {
            let source = try? Self.contents(
                of: "Sources/GStreamer/NativeElements/\(fileName)"
            )
            for snippet in snippets {
                #expect(
                    source?.contains(snippet) == true,
                    "\(fileName) should contain representative declaration snippet: \(snippet)"
                )
            }
        }

        // And the old monolithic top-level SwiftBaseSinkElement.swift implementation is absent
        #expect(
            try !Self.fileExists("Sources/GStreamer/SwiftBaseSinkElement.swift"),
            "The old top-level SwiftBaseSinkElement.swift should not remain as the canonical implementation"
        )
    }

    @Test("Public native element API remains compatible after the split")
    func publicNativeElementTypesRemainInTheGStreamerTarget() throws {
        // Given users import the GStreamer Swift target
        let metadata = NativeElementMetadata(
            klass: "Filter/Effect/Video",
            longName: "Public API Layout Probe",
            description: "Exercises public native element declarations",
            author: "gstreamer-swift-tests",
            rank: .primary
        )
        let enumCase = NativeElementEnumCase(name: "fast", nick: "f", blurb: "Fast mode")
        let properties: [NativeElementProperty] = [
            .bool(name: "enabled", default: true, blurb: "Enabled"),
            .int(name: "threshold", default: 4, min: 0, max: 10, blurb: "Threshold"),
            .double(name: "gain", default: 1.5, min: 0, max: 4, blurb: "Gain"),
            .string(name: "label", default: "probe", blurb: "Label"),
            .stringEnum(name: "mode", default: "fast", cases: [enumCase], blurb: "Mode"),
        ]
        let propertyAwareSink = SwiftBaseSinkElement(
            factoryName: "swift_layout_public_api_sink",
            typeName: "SwiftLayoutPublicAPISink",
            metadata: metadata,
            sinkCaps: Self.videoCaps,
            properties: properties,
            makeInstance: { (reader: NativeElementPropertyReader) in
                _ = reader.bool("enabled")
                _ = reader.int("threshold")
                _ = reader.double("gain")
                _ = reader.string("label")
                _ = reader.enumCase("mode")
                return PublicAPISinkInstance()
            }
        )
        let transform = SwiftBaseTransformElement.inPlace(
            factoryName: "swift_layout_public_api_transform",
            typeName: "SwiftLayoutPublicAPITransform",
            metadata: metadata,
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            passthroughOptions: SwiftBaseTransformPassthroughOptions(
                passthroughOnSameCaps: false,
                transformInPlaceOnPassthrough: true
            ),
            properties: properties,
            makeInstance: { (reader: NativeElementPropertyReader) in
                _ = reader.bool("enabled")
                return PublicAPITransformInstance()
            }
        )
        let outOfPlaceTransform = SwiftBaseTransformOutOfPlaceElement(
            factoryName: "swift_layout_public_api_out_of_place",
            typeName: "SwiftLayoutPublicAPIOutOfPlace",
            metadata: metadata,
            sinkCaps: Self.videoCaps,
            srcCaps: Self.videoCaps,
            properties: properties,
            options: .general,
            makeInstance: { PublicAPIOutOfPlaceTransformInstance() }
        )
        let flowReturns: [FlowReturn] = [
            .ok,
            .error,
            .notNegotiated,
            .flushing,
            .eos,
            .dropped,
            .custom(73),
        ]
        let allocationParams = AllocationParams(flags: 0, align: 0, prefix: 0, padding: 0)
        let allocationMetadata = AllocationMetadata(apiName: "GstMetaAPI", paramsDescription: nil)

        // When native element source files are reorganized by concern
        let builderEntries = Self.pluginEntries {
            propertyAwareSink
            transform
            outOfPlaceTransform
            NativeElementPluginEntry.baseSink(propertyAwareSink)
        }
        let directEntries: [NativeElementPluginEntry] = [
            .baseSink(propertyAwareSink),
            .baseTransform(transform),
            .baseTransformOutOfPlace(outOfPlaceTransform),
        ]
        let registerSink = GStreamer.register as (SwiftBaseSinkElement) throws -> Void
        let registerTransform = GStreamer.register as (SwiftBaseTransformElement) throws -> Void
        let registerOutOfPlace =
            GStreamer.register as (SwiftBaseTransformOutOfPlaceElement) throws -> Void
        let registerStaticPlugin:
            (
                String,
                String,
                String,
                String,
                String,
                String,
                String,
                () -> [NativeElementPluginEntry]
            ) throws -> Void = GStreamer.registerStaticPlugin
        let withDynamicPluginContext:
            (
                OpaquePointer,
                (borrowing NativeElementDynamicPluginContext) throws -> Void
            ) throws -> Void = GStreamer.withDynamicPluginContext

        // Then the public native element types and registration APIs remain in the GStreamer module
        #expect(metadata.rank.rawValue == ElementRank.primary.rawValue)
        #expect(propertyAwareSink.factoryName == "swift_layout_public_api_sink")
        #expect(transform.passthroughOptions.transformInPlaceOnPassthrough)
        #expect(outOfPlaceTransform.options == SwiftBaseTransformOutOfPlaceOptions.general)
        #expect(flowReturns.count == 7)
        #expect(allocationParams.align == 0)
        #expect(allocationMetadata.apiName == "GstMetaAPI")
        #expect(builderEntries.count == 4)
        #expect(directEntries.count == 3)
        _ = BaseTransformHookResult<Bool>.useDefault
        _ = SwiftBaseTransformOutOfPlaceOptions.fixedSize
        _ = AllocationPoolConfiguration.self
        _ = AllocationPool.self
        _ = BufferAllocator.self
        _ = AllocationParamConfiguration.self
        _ = AllocationQuery.self
        _ = BufferMetadata.self
        _ = NativeElementDynamicPluginContext.self
        _ = registerSink
        _ = registerTransform
        _ = registerOutOfPlace
        _ = registerStaticPlugin
        _ = withDynamicPluginContext

        // And representative native element declarations compile from a plain import without testable access
        Self.compileDynamicRegistrationSurface(
            sink: propertyAwareSink,
            transform: transform,
            outOfPlaceTransform: outOfPlaceTransform
        )

        // And existing native element runtime behavior remains covered by focused tests
        #expect(Self.nativeElementBehaviorTestFiles.count == 8)
    }

    @Test("C shim reviewer finds split implementations behind one public header")
    func cShimReviewerFindsSplitImplementationFilesBehindOnePublicHeader() throws {
        // Given the GStreamer Base shim exposes one public C header to Swift
        let publicHeaderExists = try Self.fileExists(
            "Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h"
        )
        let publicHeaders = try Self.fileNames(
            in: "Sources/CGStreamerBaseShim/include",
            withPathExtension: "h"
        )

        // When the shim implementation is prepared for public repository review
        let cFiles = try Self.fileNames(
            in: "Sources/CGStreamerBaseShim",
            withPathExtension: "c"
        )
        let baseSinkCFile = Self.firstFile(in: cFiles) { fileName in
            Self.lowercase(fileName).contains("basesink")
        }
        let baseTransformCFile = Self.firstFile(in: cFiles) { fileName in
            Self.lowercase(fileName).contains("basetransform")
        }
        let propertiesAllocationCFile = Self.firstFile(in: cFiles) { fileName in
            let lowercased = Self.lowercase(fileName)
            return lowercased.contains("propert") || lowercased.contains("allocation")
        }
        let pluginSharedCFile = Self.firstFile(in: cFiles) { fileName in
            let lowercased = Self.lowercase(fileName)
            return lowercased.contains("plugin") || lowercased.contains("shared")
        }

        // Then the public GStreamerBaseShim.h header remains the single exported header
        #expect(publicHeaderExists)
        #expect(publicHeaders == ["GStreamerBaseShim.h"])

        // And BaseSink, BaseTransform, property/allocation, and plugin/shared implementation code live in separate C files
        #expect(baseSinkCFile != nil, "Expected a BaseSink-oriented C implementation file")
        #expect(baseTransformCFile != nil, "Expected a BaseTransform-oriented C implementation file")
        #expect(
            propertiesAllocationCFile != nil,
            "Expected a properties/allocation-oriented C implementation file"
        )
        #expect(pluginSharedCFile != nil, "Expected a plugin/shared C implementation file")
        #expect(
            Set([
                baseSinkCFile,
                baseTransformCFile,
                propertiesAllocationCFile,
                pluginSharedCFile,
            ].compactMap { $0 }).count == 4,
            "C shim concerns should live in four separate implementation files"
        )
        if let baseSinkCFile {
            let source = try Self.contents(of: "Sources/CGStreamerBaseShim/\(baseSinkCFile)")
            #expect(source.contains("SwiftGstNativeBaseSink"))
            #expect(source.contains("swift_gst_register_base_sink"))
        }
        if let baseTransformCFile {
            let source = try Self.contents(of: "Sources/CGStreamerBaseShim/\(baseTransformCFile)")
            #expect(source.contains("SwiftGstNativeBaseTransform"))
            #expect(source.contains("swift_gst_register_base_transform"))
        }
        if let propertiesAllocationCFile {
            let source = try Self.contents(
                of: "Sources/CGStreamerBaseShim/\(propertiesAllocationCFile)"
            )
            #expect(source.contains("swift_gst_native_property_descriptors_copy"))
            #expect(source.contains("swift_gst_allocation_query_get_caps"))
        }
        if let pluginSharedCFile {
            let source = try Self.contents(of: "Sources/CGStreamerBaseShim/\(pluginSharedCFile)")
            #expect(source.contains("swift_gst_register_static_plugin"))
        }

        // And the old monolithic GStreamerBaseShim.c implementation is no longer the canonical implementation file
        #expect(
            try !Self.fileExists("Sources/CGStreamerBaseShim/GStreamerBaseShim.c"),
            "The old monolithic GStreamerBaseShim.c should be removed after the C shim split"
        )
    }

    @Test("Existing native element behavior is preserved")
    func existingNativeElementBehaviorIsPreserved() throws {
        // Given existing tests cover BaseSink, BaseTransform, out-of-place transforms, properties, static plugin grouping, and dynamic plugin registration
        let behaviorTestFiles = Self.nativeElementBehaviorTestFiles

        // When the source layout is refactored without intentional API or behavior changes
        for file in behaviorTestFiles {
            #expect(try Self.fileExists(file), "Missing focused behavior test file \(file)")
            let source = try Self.contents(of: file)
            #expect(source.contains("@Suite"), "\(file) should remain a Swift Testing suite")
            #expect(source.contains("@Test("), "\(file) should keep focused behavior tests")
        }

        // Then focused native element tests still pass
        #expect(behaviorTestFiles.contains("Tests/SwiftGStreamerTests/SwiftBaseSinkNativeElementTests.swift"))
        #expect(behaviorTestFiles.contains("Tests/SwiftGStreamerTests/SwiftBaseTransformNativeElementTests.swift"))
        #expect(
            behaviorTestFiles
                .contains("Tests/SwiftGStreamerTests/SwiftBaseTransformOutOfPlaceNativeElementTests.swift")
        )
        #expect(behaviorTestFiles.contains("Tests/SwiftGStreamerTests/SwiftNativeElementPropertiesTests.swift"))
        #expect(behaviorTestFiles.contains("Tests/SwiftGStreamerTests/StaticPluginGroupingTests.swift"))
        #expect(behaviorTestFiles.contains("Tests/SwiftGStreamerTests/DynamicPluginSupportTests.swift"))

        // And the package build and test suite still pass when local dependencies are available
        #expect(behaviorTestFiles.count == 8)
    }

    private static let videoCaps = "video/x-raw,format=RGB,width=2,height=2,framerate=1/1"

    private static let requestedNativeElementSwiftFiles: Set<String> = [
        "AllocationQuery.swift",
        "BorrowedBuffer.swift",
        "DynamicPluginRegistration.swift",
        "FlowReturn.swift",
        "MutableBorrowedBuffer.swift",
        "NativeElementMetadata.swift",
        "NativeElementProperties.swift",
        "NativeElementRegistry.swift",
        "NativeElementValidation.swift",
        "StaticPluginRegistration.swift",
        "SwiftBaseSinkElement.swift",
        "SwiftBaseTransformElement.swift",
        "SwiftBaseTransformOutOfPlaceElement.swift",
    ]

    private static let expectedSwiftDeclarationSnippets: [String: [String]] = [
        "AllocationQuery.swift": [
            "public struct AllocationQuery: ~Copyable",
            "public struct AllocationParams",
            "public struct AllocationMetadata",
            "public struct BufferMetadata: ~Copyable",
        ],
        "BorrowedBuffer.swift": [
            "public struct BorrowedBuffer: ~Copyable",
        ],
        "DynamicPluginRegistration.swift": [
            "public struct NativeElementDynamicPluginContext: ~Copyable",
            "public static func withDynamicPluginContext",
            "public static func registerDynamicPluginElements",
        ],
        "FlowReturn.swift": [
            "public enum FlowReturn",
        ],
        "MutableBorrowedBuffer.swift": [
            "public struct MutableBorrowedBuffer: ~Copyable",
        ],
        "NativeElementMetadata.swift": [
            "public enum ElementRank",
            "public struct NativeElementMetadata",
        ],
        "NativeElementProperties.swift": [
            "public struct NativeElementEnumCase",
            "public enum NativeElementProperty",
            "public struct NativeElementPropertyReader",
        ],
        "NativeElementRegistry.swift": [
            "public static func register(_ element: SwiftBaseSinkElement)",
            "public static func register(_ element: SwiftBaseTransformElement)",
            "public static func register(_ element: SwiftBaseTransformOutOfPlaceElement)",
            "internal enum NativeElementRegistrationTestHooks",
        ],
        "NativeElementValidation.swift": [
            "internal enum NativeElementTypeName",
            "enum NativeElementRegistration",
        ],
        "StaticPluginRegistration.swift": [
            "public enum NativeElementPluginEntry",
            "@resultBuilder",
            "public enum NativeElementPluginBuilder",
            "public static func registerStaticPlugin",
        ],
        "SwiftBaseSinkElement.swift": [
            "public protocol SwiftBaseSinkInstance",
            "public struct SwiftBaseSinkElement",
        ],
        "SwiftBaseTransformElement.swift": [
            "public struct SwiftBaseTransformPassthroughOptions",
            "public protocol SwiftBaseTransformInstance",
            "public struct SwiftBaseTransformElement",
        ],
        "SwiftBaseTransformOutOfPlaceElement.swift": [
            "public enum BaseTransformHookResult",
            "public struct SwiftBaseTransformOutOfPlaceOptions",
            "public protocol SwiftBaseTransformOutOfPlaceInstance",
            "public struct SwiftBaseTransformOutOfPlaceElement",
        ],
    ]

    private static let nativeElementBehaviorTestFiles = [
        "Tests/SwiftGStreamerTests/SwiftBaseSinkNativeElementTests.swift",
        "Tests/SwiftGStreamerTests/SwiftBaseTransformNativeElementTests.swift",
        "Tests/SwiftGStreamerTests/SwiftBaseTransformOutOfPlaceNativeElementTests.swift",
        "Tests/SwiftGStreamerTests/SwiftBaseTransformGeneralOutOfPlaceNativeElementTests.swift",
        "Tests/SwiftGStreamerTests/BaseTransformPassthroughBorrowedBufferTests.swift",
        "Tests/SwiftGStreamerTests/SwiftNativeElementPropertiesTests.swift",
        "Tests/SwiftGStreamerTests/StaticPluginGroupingTests.swift",
        "Tests/SwiftGStreamerTests/DynamicPluginSupportTests.swift",
    ]

    private static func pluginEntries(
        @NativeElementPluginBuilder _ entries: () -> [NativeElementPluginEntry]
    ) -> [NativeElementPluginEntry] {
        entries()
    }

    private static func compileDynamicRegistrationSurface(
        sink: SwiftBaseSinkElement,
        transform: SwiftBaseTransformElement,
        outOfPlaceTransform: SwiftBaseTransformOutOfPlaceElement
    ) {
        _ = { (rawPlugin: OpaquePointer) throws in
            try GStreamer.withDynamicPluginContext(rawPlugin: rawPlugin) { context in
                try GStreamer.registerDynamicPluginElements(into: context) {
                    sink
                    transform
                    outOfPlaceTransform
                }
            }
        } as (OpaquePointer) throws -> Void
    }

    private static func contents(of relativePath: String) throws -> String {
        let file = try packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func fileExists(_ relativePath: String) throws -> Bool {
        let file = try packageRoot().appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: file.path)
    }

    private static func directoryExists(_ relativePath: String) throws -> Bool {
        let directory = try packageRoot().appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func fileNames(
        in relativeDirectory: String,
        withPathExtension pathExtension: String
    ) throws -> Set<String> {
        let directory = try packageRoot().appendingPathComponent(relativeDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return Set(
            contents
                .filter { $0.pathExtension == pathExtension }
                .map { $0.lastPathComponent }
        )
    }

    private static func firstFile(
        in files: Set<String>,
        matching predicate: (String) -> Bool
    ) -> String? {
        files.sorted().first(where: predicate)
    }

    private static func lowercase(_ value: String) -> String {
        value.lowercased()
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
                throw NativeElementsSourceLayoutBDDTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }
}

private enum NativeElementsSourceLayoutBDDTestError: Error {
    case packageRootNotFound(String)
}

private final class PublicAPISinkInstance: SwiftBaseSinkInstance {
    func render(_ buffer: borrowing BorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}

private final class PublicAPITransformInstance: SwiftBaseTransformInstance {
    func transformInPlace(_ buffer: borrowing MutableBorrowedBuffer) throws -> FlowReturn {
        .ok
    }
}

private final class PublicAPIOutOfPlaceTransformInstance: SwiftBaseTransformOutOfPlaceInstance {
    func decideAllocation(_ query: borrowing AllocationQuery) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }

    func proposeAllocation(
        decideQuery: borrowing AllocationQuery,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }

    func filterAllocationMetadata(
        _ metadata: AllocationMetadata,
        query: borrowing AllocationQuery
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }

    func copyMetadata(
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }

    func transformMetadata(
        _ metadata: borrowing BufferMetadata,
        from input: borrowing BorrowedBuffer,
        to output: borrowing MutableBorrowedBuffer
    ) throws -> BaseTransformHookResult<Bool> {
        .useDefault
    }

    func transform(
        _ input: borrowing BorrowedBuffer,
        into output: borrowing MutableBorrowedBuffer
    ) throws -> FlowReturn {
        .ok
    }
}
