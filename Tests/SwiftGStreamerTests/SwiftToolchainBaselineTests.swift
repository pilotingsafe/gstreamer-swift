import Foundation
import Testing

@Suite("Swift 6.3.1 Toolchain Baseline Tests")
struct SwiftToolchainBaselineTests {

    @Test("Package manifest declares the Swift 6.3.1 minimum")
    func packageManifestDeclaresSwift631Minimum() throws {
        let manifest = try Self.contents(of: "Package.swift")

        #expect(
            manifest.hasPrefix("// swift-tools-version:6.3.1"),
            "Package.swift must declare Swift 6.3.1 as the minimum tools version"
        )
    }

    @Test("CI validates Swift 6.3.1")
    func ciValidatesSwift631() throws {
        let workflow = try Self.contents(of: ".github/workflows/ci.yml")

        #expect(
            workflow.range(
                of: #"SWIFT_VERSION:\s*6\.3\.1"#,
                options: .regularExpression
            ) != nil,
            "CI must validate Swift 6.3.1"
        )
    }

    @Test("Documentation states the Swift 6.3.1 baseline")
    func documentationStatesSwift631Baseline() throws {
        let readme = try Self.contents(of: "README.md")

        let requiredReadmeSnippets = [
            "Swift-6.3.1-orange.svg",
            "A Swift 6.3.1 package",
            "Swift 6.3.1+",
            "GitHub Actions CI runs Swift 6.3.1",
        ]
        let missingReadmeSnippets = requiredReadmeSnippets.filter { !readme.contains($0) }

        #expect(
            missingReadmeSnippets.isEmpty,
            "README is missing Swift 6.3.1 baseline snippets:\n\(missingReadmeSnippets.joined(separator: "\n"))"
        )
    }

    @Test("VideoFrame byte APIs remain public")
    func videoFrameByteAPIsRemainPublic() throws {
        let videoFrameSource = try Self.contents(of: "Sources/GStreamer/VideoFrame.swift")

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
                throw SwiftToolchainBaselineTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }
}

private enum SwiftToolchainBaselineTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not locate Package.swift from \(filePath)"
        }
    }
}
