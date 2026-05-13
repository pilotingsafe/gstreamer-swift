import Foundation
import Testing

@Suite("Swift 6.2 VideoFrame Byte Count BDD Tests")
struct Swift62VideoFrameByteCountBDDTests {

    @Test("AppSink smoke tests validate frame byte counts without lifetime-bound macro access")
    func appSinkSmokeTestsValidateFrameByteCountsWithoutLifetimeBoundMacroAccess() throws {
        // Given an AppSink smoke test awaits a VideoFrame from a video pipeline
        let appSinkSource = try Self.contents(of: "Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift")
        let videoFrameData = try Self.bracedDeclaration(
            beginningWith: "func videoFrameData() async throws",
            in: appSinkSource
        )
        let pullFrames = try Self.bracedDeclaration(
            beginningWith: "func pullFrames() async throws",
            in: appSinkSource
        )

        // When the test validates the frame byte count
        // Then the test computes the byte count outside the Swift Testing macro
        #expect(
            !Self.containsDirectFrameBytesByteCountExpectation(in: videoFrameData),
            "videoFrameData must not assert directly on frame.bytes.byteCount inside #expect"
        )
        #expect(
            !Self.containsDirectFrameBytesByteCountExpectation(in: pullFrames),
            "pullFrames must not assert directly on frame.bytes.byteCount inside #expect"
        )

        // And the test asserts on a plain local byte-count value
        #expect(
            try Self.containsLocalWithUnsafeByteCountExpectation(
                in: videoFrameData,
                expectedPatterns: [
                    #"==\s*4\s*\*\s*4\s*\*\s*4"#,
                    #"==\s*64"#,
                    #"==\s*expectedByteCount"#,
                ]
            ),
            "videoFrameData must compute a local count with frame.withUnsafeBytes { ... .count } before asserting the 4x4 BGRA byte count"
        )
        #expect(
            try Self.containsLocalWithUnsafeByteCountExpectation(
                in: pullFrames,
                expectedPatterns: [
                    #">\s*0"#,
                    #">=\s*1"#,
                    #"!=\s*0"#,
                ]
            ),
            "pullFrames must compute a local count with frame.withUnsafeBytes { ... .count } before asserting non-empty frame data"
        )
    }

    @Test("AppSource roundtrip tests validate frame byte counts without lifetime-bound macro access")
    func appSourceRoundtripTestsValidateFrameByteCountsWithoutLifetimeBoundMacroAccess() throws {
        // Given an AppSource/AppSink roundtrip test awaits a VideoFrame
        let appSourceSource = try Self.contents(of: "Tests/SwiftGStreamerTests/AppSourceTests.swift")
        let roundtrip = try Self.bracedDeclaration(
            beginningWith: "func roundtrip() async throws",
            in: appSourceSource
        )

        // When the test validates the roundtripped frame byte count
        // Then the test computes the byte count outside the Swift Testing macro
        #expect(
            !Self.containsDirectFrameBytesByteCountExpectation(in: roundtrip),
            "roundtrip must not assert directly on frame.bytes.byteCount inside #expect"
        )

        // And the test asserts on a plain local byte-count value
        #expect(
            try Self.containsLocalWithUnsafeByteCountExpectation(
                in: roundtrip,
                expectedPatterns: [
                    #"==\s*16"#,
                    #"==\s*2\s*\*\s*2\s*\*\s*4"#,
                    #"==\s*pixels\.count"#,
                    #"==\s*expectedByteCount"#,
                ]
            ),
            "roundtrip must compute a local count with frame.withUnsafeBytes { ... .count } before asserting the 2x2 BGRA byte count"
        )
    }

    @Test("Read-only API tests preserve coverage for both VideoFrame byte APIs")
    func readOnlyAPITestsPreserveCoverageForBothVideoFrameByteAPIs() throws {
        // Given a read-only VideoFrame API test awaits a BGRA frame
        let readOnlySource = try Self.contents(of: "Tests/SwiftGStreamerTests/VideoFrameReadOnlyAPITests.swift")
        let readOnlyTest = try Self.bracedDeclaration(
            beginningWith: "func bgraFrameReadOnlyByteViewsExposeExpectedCount() async throws",
            in: readOnlySource
        )

        // When the test validates read-only byte access
        // Then the test reads bytes.byteCount into a local value before asserting
        #expect(
            !Self.containsDirectFrameBytesByteCountExpectation(in: readOnlyTest),
            "Read-only API coverage must not assert directly on frame.bytes.byteCount inside #expect"
        )
        #expect(
            try Self.containsLocalBytesByteCountExpectation(
                in: readOnlyTest,
                expectedPatterns: [#"==\s*expectedByteCount"#]
            ),
            "Read-only API coverage must read frame.bytes.byteCount into a local before asserting"
        )

        // And the test separately validates the withUnsafeBytes byte count
        #expect(
            try Self.containsLocalWithUnsafeByteCountExpectation(
                in: readOnlyTest,
                expectedPatterns: [#"==\s*expectedByteCount"#]
            ),
            "Read-only API coverage must separately assert a local count from frame.withUnsafeBytes { ... .count }"
        )
    }

    @Test("Static safety guards accept equivalent byte-count evidence")
    func staticSafetyGuardsAcceptEquivalentByteCountEvidence() throws {
        // Given a static safety test guards async media smoke test evidence
        let apiSafetySource = try Self.contents(of: "Tests/SwiftGStreamerTests/APISafetyStaticTests.swift")
        let staticGuard = try Self.bracedDeclaration(
            beginningWith: "func asyncMediaSmokeTestsKeepPostLoopEvidenceAssertions() throws",
            in: apiSafetySource
        )

        // When the AppSink byte-count assertion is reshaped for Swift 6.2 compatibility
        // Then the guard accepts post-loop byte-count validation through withUnsafeBytes
        let normalizedStaticGuard = Self.normalizedWhitespace(staticGuard)
        #expect(
            normalizedStaticGuard.contains("\"Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift\"")
                && normalizedStaticGuard.contains("\"func videoFrameData() async throws\""),
            "APISafetyStaticTests must keep a guard for AppSinkSmokeTests.videoFrameData"
        )
        #expect(
            normalizedStaticGuard.contains("withUnsafeBytes")
                && normalizedStaticGuard.contains("byteCount")
                && (
                    normalizedStaticGuard.contains("4 * 4 * 4")
                        || normalizedStaticGuard.contains("64")
                        || normalizedStaticGuard.contains("expectedByteCount")
                ),
            "APISafetyStaticTests must require equivalent local withUnsafeBytes byte-count evidence"
        )

        // And the guard does not require the old direct bytes.byteCount macro snippet
        let oldSnippet = "#expect(" + "frame.bytes.byteCount == 4 * 4 * 4)"
        #expect(
            !staticGuard.contains(oldSnippet),
            "APISafetyStaticTests must not require the old direct frame.bytes.byteCount macro snippet"
        )
    }

    @Test("CI continues to validate Swift 6.2 compatibility")
    func ciContinuesToValidateSwift62Compatibility() throws {
        // Given macOS CI intentionally validates Swift 6.2 compatibility
        let ciWorkflow = try Self.contents(of: ".github/workflows/ci.yml")
        let videoFrameSource = try Self.contents(of: "Sources/GStreamer/VideoFrame.swift")

        // When the compiler crash workaround is implemented
        // Then the CI workflow keeps Swift 6.2.4 as the selected Swift version
        #expect(
            ciWorkflow.range(
                of: #"SWIFT_VERSION:\s*6\.2\.4"#,
                options: .regularExpression
            ) != nil,
            "CI must keep validating Swift 6.2.4"
        )

        // And no public VideoFrame API is changed to avoid the crash
        #expect(
            videoFrameSource.range(
                of: #"public\s+var\s+bytes\s*:\s*RawSpan\b"#,
                options: .regularExpression
            ) != nil,
            "VideoFrame.bytes must remain public"
        )
        #expect(
            videoFrameSource.range(
                of: #"public\s+func\s+withUnsafeBytes\s*<\s*R\s*>\s*\(\s*_ body:\s*\(UnsafeRawBufferPointer\)\s*throws\s*->\s*R\s*\)\s*throws\s*->\s*R\b"#,
                options: .regularExpression
            ) != nil,
            "VideoFrame.withUnsafeBytes(_:) must remain public"
        )
    }

    private struct LocalCountAssignment {
        let variableName: String
        let trailingSource: String
    }

    private static func contents(of relativePath: String) throws -> String {
        let root = try packageRoot()
        let file = root.appendingPathComponent(relativePath)
        return try String(contentsOf: file, encoding: .utf8)
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
                throw Swift62VideoFrameByteCountBDDTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func bracedDeclaration(beginningWith declaration: String, in source: String) throws -> String {
        guard let declarationRange = source.range(of: declaration) else {
            throw Swift62VideoFrameByteCountBDDTestError.declarationNotFound(declaration)
        }
        guard let openBrace = source[declarationRange.upperBound...].firstIndex(of: "{") else {
            throw Swift62VideoFrameByteCountBDDTestError.declarationNotFound(declaration)
        }

        var index = openBrace
        var depth = 0

        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[declarationRange.lowerBound...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw Swift62VideoFrameByteCountBDDTestError.unbalancedDeclaration(declaration)
    }

    private static func containsDirectFrameBytesByteCountExpectation(in declaration: String) -> Bool {
        declaration.range(
            of: #"#expect\s*\(\s*frame\s*\.\s*bytes\s*\.\s*byteCount\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsLocalWithUnsafeByteCountExpectation(
        in declaration: String,
        receiver: String = "frame",
        expectedPatterns: [String]
    ) throws -> Bool {
        try localWithUnsafeByteCountAssignments(in: declaration, receiver: receiver).contains { assignment in
            containsExpectation(
                forVariable: assignment.variableName,
                in: assignment.trailingSource,
                expectedPatterns: expectedPatterns
            )
        }
    }

    private static func containsLocalBytesByteCountExpectation(
        in declaration: String,
        receiver: String = "frame",
        expectedPatterns: [String]
    ) throws -> Bool {
        try localBytesByteCountAssignments(in: declaration, receiver: receiver).contains { assignment in
            containsExpectation(
                forVariable: assignment.variableName,
                in: assignment.trailingSource,
                expectedPatterns: expectedPatterns
            )
        }
    }

    private static func localWithUnsafeByteCountAssignments(
        in declaration: String,
        receiver: String
    ) throws -> [LocalCountAssignment] {
        let escapedReceiver = NSRegularExpression.escapedPattern(for: receiver)
        let pattern = #"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*try\s+\#(escapedReceiver)\.withUnsafeBytes\s*\{[^}]*(?:\$0|[A-Za-z_][A-Za-z0-9_]*)\.count\b[^}]*\}"#
        return try localCountAssignments(matching: pattern, in: declaration)
    }

    private static func localBytesByteCountAssignments(
        in declaration: String,
        receiver: String
    ) throws -> [LocalCountAssignment] {
        let escapedReceiver = NSRegularExpression.escapedPattern(for: receiver)
        let pattern = #"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\#(escapedReceiver)\.bytes\.byteCount\b"#
        return try localCountAssignments(matching: pattern, in: declaration)
    }

    private static func localCountAssignments(
        matching pattern: String,
        in declaration: String
    ) throws -> [LocalCountAssignment] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(declaration.startIndex..<declaration.endIndex, in: declaration)

        return regex.matches(in: declaration, range: range).compactMap { match in
            guard let variableRange = Range(match.range(at: 1), in: declaration),
                  let matchRange = Range(match.range, in: declaration)
            else {
                return nil
            }

            return LocalCountAssignment(
                variableName: String(declaration[variableRange]),
                trailingSource: String(declaration[matchRange.upperBound...])
            )
        }
    }

    private static func containsExpectation(
        forVariable variableName: String,
        in source: String,
        expectedPatterns: [String]
    ) -> Bool {
        let escapedVariable = NSRegularExpression.escapedPattern(for: variableName)

        return expectedPatterns.contains { expectedPattern in
            let pattern = #"#expect\s*\(\s*"# + escapedVariable + #"\s*(?:"# + expectedPattern + #")"#
            return source.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func normalizedWhitespace(_ source: String) -> String {
        source.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum Swift62VideoFrameByteCountBDDTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)
    case declarationNotFound(String)
    case unbalancedDeclaration(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not locate Package.swift from \(filePath)"
        case .declarationNotFound(let declaration):
            "Could not find declaration beginning with \(declaration)"
        case .unbalancedDeclaration(let declaration):
            "Declaration has unbalanced braces: \(declaration)"
        }
    }
}
