import Foundation
import Testing
import CGStreamer
import CGStreamerBaseShim
@testable import GStreamer

@Suite("Contextual Dropped Flow Return Tests")
struct ContextualDroppedFlowReturnTests {
    @Test("BaseSink dropped render results use the BaseSink dropped flow return")
    func baseSinkDroppedRenderUsesBaseSinkDroppedFlowReturn() throws {
        // Given a Swift-backed BaseSink render callback returns a dropped flow result
        try Self.expectBaseSinkDroppedShimHelperUsesSemanticMacro()

        // When the Swift bridge converts the callback result for GStreamer
        let converted = FlowReturn.dropped.baseSinkRenderGstFlowReturn

        // Then the result matches GStreamer's BaseSink dropped flow return
        #expect(converted.rawValue == swift_gst_base_sink_flow_dropped().rawValue)
    }

    @Test("In-place BaseTransform dropped results use the BaseTransform dropped flow return")
    func inPlaceBaseTransformDroppedUsesBaseTransformDroppedFlowReturn() throws {
        // Given a Swift-backed in-place BaseTransform callback returns a dropped flow result
        try Self.expectBaseTransformDroppedShimHelperUsesSemanticMacro()

        // When the Swift bridge converts the callback result for GStreamer
        let converted = FlowReturn.dropped.baseTransformGstFlowReturn

        // Then the result matches GStreamer's BaseTransform dropped flow return
        #expect(converted.rawValue == swift_gst_base_transform_flow_dropped().rawValue)
    }

    @Test("Out-of-place BaseTransform dropped results use the BaseTransform dropped flow return")
    func outOfPlaceBaseTransformDroppedUsesBaseTransformDroppedFlowReturn() {
        // Given a Swift-backed out-of-place BaseTransform callback returns a dropped flow result

        // When the Swift bridge converts the callback result for GStreamer
        let converted = FlowReturn.dropped.baseTransformGstFlowReturn

        // Then the result matches GStreamer's BaseTransform dropped flow return
        #expect(converted.rawValue == swift_gst_base_transform_flow_dropped().rawValue)
    }

    @Test("Context-independent flow results keep their existing values")
    func contextIndependentFlowResultsKeepExistingValues() {
        // Given a Swift-backed native element callback returns a non-dropped flow result

        // When the Swift bridge converts the callback result for GStreamer

        // Then ok, error, not-negotiated, flushing, and end-of-stream results keep their existing values
        Self.expectContextIndependentMappings(
            "BaseSink render",
            using: { $0.baseSinkRenderGstFlowReturn }
        )
        Self.expectContextIndependentMappings(
            "BaseTransform transform",
            using: { $0.baseTransformGstFlowReturn }
        )

        // And custom flow results pass through their raw values
        #expect(FlowReturn.custom(73).baseSinkRenderGstFlowReturn.rawValue == 73)
        #expect(FlowReturn.custom(-123).baseSinkRenderGstFlowReturn.rawValue == -123)
        #expect(FlowReturn.custom(73).baseTransformGstFlowReturn.rawValue == 73)
        #expect(FlowReturn.custom(-123).baseTransformGstFlowReturn.rawValue == -123)
    }

    @Test("Callback bridges use contextual flow-return conversions")
    func callbackBridgesUseContextualFlowReturnConversions() throws {
        // Given the BaseSink and BaseTransform callback bridges convert Swift flow results
        let source = try NativeElementSourceLayoutTestSupport.nativeElementSwiftSource()
        let baseSinkRender = try Self.functionBody(
            named: "swiftGstBaseSinkRender",
            declarationMarker: "func swiftGstBaseSinkRender",
            in: source
        )
        let baseTransformInPlace = try Self.functionBody(
            named: "swiftGstBaseTransformIP",
            declarationMarker: "func swiftGstBaseTransformIP",
            in: source
        )
        let baseTransformOutOfPlace = try Self.functionBody(
            named: "swiftGstBaseTransformOutOfPlaceTransform",
            declarationMarker: "func swiftGstBaseTransformOutOfPlaceTransform",
            in: source
        )

        // When the implementation maps dropped flow results for GStreamer

        // Then the BaseSink render bridge uses the BaseSink conversion
        #expect(baseSinkRender.contains(".baseSinkRenderGstFlowReturn"))
        #expect(!baseSinkRender.contains(".gstFlowReturn"))

        // And the in-place and out-of-place BaseTransform bridges use the BaseTransform conversion
        #expect(baseTransformInPlace.contains(".baseTransformGstFlowReturn"))
        #expect(!baseTransformInPlace.contains(".gstFlowReturn"))
        #expect(baseTransformOutOfPlace.contains(".baseTransformGstFlowReturn"))
        #expect(!baseTransformOutOfPlace.contains(".gstFlowReturn"))
    }

    private static func expectContextIndependentMappings(
        _ contextName: String,
        using convert: (FlowReturn) -> GstFlowReturn
    ) {
        #expect(convert(.ok).rawValue == GST_FLOW_OK.rawValue, "\(contextName) .ok must keep GST_FLOW_OK")
        #expect(convert(.error).rawValue == GST_FLOW_ERROR.rawValue, "\(contextName) .error must keep GST_FLOW_ERROR")
        #expect(
            convert(.notNegotiated).rawValue == GST_FLOW_NOT_NEGOTIATED.rawValue,
            "\(contextName) .notNegotiated must keep GST_FLOW_NOT_NEGOTIATED"
        )
        #expect(
            convert(.flushing).rawValue == GST_FLOW_FLUSHING.rawValue,
            "\(contextName) .flushing must keep GST_FLOW_FLUSHING"
        )
        #expect(convert(.eos).rawValue == GST_FLOW_EOS.rawValue, "\(contextName) .eos must keep GST_FLOW_EOS")
    }

    private static func expectBaseSinkDroppedShimHelperUsesSemanticMacro() throws {
        let header = try contents(of: "Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        let source = try NativeElementSourceLayoutTestSupport.baseShimCSource()
        let body = try functionBody(
            named: "swift_gst_base_sink_flow_dropped",
            declarationMarker: "swift_gst_base_sink_flow_dropped",
            in: source
        )

        #expect(
            header.containsRegex(#"GstFlowReturn\s+swift_gst_base_sink_flow_dropped\s*\(\s*void\s*\)\s*;"#)
        )
        #expect(body.contains("#ifdef GST_BASE_SINK_FLOW_DROPPED"))
        #expect(body.contains("GST_BASE_SINK_FLOW_DROPPED"))
        #expect(body.contains("GST_FLOW_CUSTOM_SUCCESS"))
    }

    private static func expectBaseTransformDroppedShimHelperUsesSemanticMacro() throws {
        let header = try contents(of: "Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        let source = try NativeElementSourceLayoutTestSupport.baseShimCSource()
        let body = try functionBody(
            named: "swift_gst_base_transform_flow_dropped",
            declarationMarker: "swift_gst_base_transform_flow_dropped",
            in: source
        )

        #expect(
            header.containsRegex(#"GstFlowReturn\s+swift_gst_base_transform_flow_dropped\s*\(\s*void\s*\)\s*;"#)
        )
        #expect(body.contains("GST_BASE_TRANSFORM_FLOW_DROPPED"))
        #expect(!body.contains("GST_FLOW_CUSTOM_SUCCESS"))
    }

    private static func contents(of relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func functionBody(
        named name: String,
        declarationMarker: String,
        in source: String
    ) throws -> String {
        guard let declarationRange = source.range(of: declarationMarker),
              let openBrace = source[declarationRange.upperBound...].firstIndex(of: "{")
        else {
            throw ContextualDroppedFlowReturnTestError.functionNotFound(name)
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw ContextualDroppedFlowReturnTestError.unbalancedFunctionBody(name)
    }
}

private extension String {
    func containsRegex(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

private enum ContextualDroppedFlowReturnTestError: Error, CustomStringConvertible {
    case functionNotFound(String)
    case unbalancedFunctionBody(String)

    var description: String {
        switch self {
        case .functionNotFound(let name):
            return "Could not find function body for \(name)"
        case .unbalancedFunctionBody(let name):
            return "Could not find balanced function body for \(name)"
        }
    }
}
