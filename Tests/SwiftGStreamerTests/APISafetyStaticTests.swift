import Foundation
import Testing

@Suite("API Safety Static Tests")
struct APISafetyStaticTests {

    @Test("VideoFrame exposes only retained read-only byte access")
    func videoFrameMutableAPIDeclarationsAreRemoved() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/VideoFrame.swift"))
        let mutablePropertyDeclaration = "public var " + "mutableBytes"
        let mutablePointerDeclaration = "public func " + "withUnsafeMutableBytes"

        #expect(!source.contains(mutablePropertyDeclaration))
        #expect(!source.contains(mutablePointerDeclaration))
    }

    @Test("Docs and samples do not reference stale VideoFrame byte access")
    func staleVideoFrameByteAccessReferencesAreRemoved() throws {
        let root = try Self.packageRoot()
        let files = try Self.videoFrameReferenceScanFiles(in: root)
        let stalePatterns = Self.staleVideoFrameReferencePatterns()
        var violations: [String] = []

        for file in files {
            let fileContents = try Self.contents(of: file)
            for pattern in stalePatterns where fileContents.contains(pattern) {
                violations.append("\(Self.relativePath(file, to: root)): \(pattern)")
            }
        }

        #expect(
            violations.isEmpty,
            "Remove stale VideoFrame byte access references:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Video frame documentation explains mutable migration path")
    func workingWithVideoFramesDocumentsMutableMigrationPath() throws {
        let root = try Self.packageRoot()
        let documentation = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/Documentation.docc/WorkingWithVideoFrames.md")
        )

        #expect(Self.containsMutableMigrationGuidance(documentation))
    }

    @Test("Buffer mutable span delegates uniqueness to shared helper")
    func bufferMutableSpanUsesEnsureUniqueWithoutDirectStorageCopy() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Buffer.swift"))
        let implementation = try Self.bracedDeclaration(
            beginningWith: "public var " + "mutableBytes: MutableRawSpan",
            in: source
        )

        #expect(implementation.contains("guard ensureUnique() else"))
        #expect(!implementation.contains("storage.copy()"))
    }

    @Test("Realtime media streams use bounded backpressure policies")
    func realtimeMediaStreamsUseBoundedBackpressurePolicies() throws {
        let root = try Self.packageRoot()
        let audioBufferSinkSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioBufferSink.swift")
        )
        let audioSourceSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift")
        )
        let rawBuffersImplementation = try Self.bracedDeclaration(
            beginningWith: "public func buffers() -> AsyncStream<AudioBuffer>",
            in: audioBufferSinkSource
        )
        let audioPacketSinkSource = try Self.bracedDeclaration(
            beginningWith: "private final class AudioPacketSink",
            in: audioSourceSource
        )
        let encodedPacketsImplementation = try Self.bracedDeclaration(
            beginningWith: "func packets() -> AsyncStream<Buffer>",
            in: audioPacketSinkSource
        )

        #expect(
            Self.containsBufferingNewestPolicy(
                source: audioBufferSinkSource,
                implementation: rawBuffersImplementation,
                expectedCount: 1
            ),
            "AudioBufferSink.buffers() should use .bufferingNewest(1) or a named constant with value 1"
        )
        #expect(
            Self.containsBufferingNewestPolicy(
                source: audioSourceSource,
                implementation: encodedPacketsImplementation,
                expectedCount: 8
            ),
            "AudioPacketSink.packets() should use .bufferingNewest(8) or a named constant with value 8"
        )
    }

    @Test("Public stream return types remain source-compatible")
    func publicStreamReturnTypesRemainSourceCompatible() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let audioBufferSink = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioBufferSink.swift"))
        let bus = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let appSink = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AppSink.swift"))

        #expect(audioSource.contains("public func buffers() -> AsyncStream<AudioBuffer>"))
        #expect(audioSource.contains("public func packets() -> AsyncStream<Buffer>"))
        #expect(audioBufferSink.contains("public func buffers() -> AsyncStream<AudioBuffer>"))
        #expect(bus.contains("public func messages(filter: Filter = [.error, .eos, .stateChanged]) -> AsyncStream<BusMessage>"))
        #expect(appSink.contains("public func frames() -> Frames"))
    }

    @Test("Bus-derived streams keep non-dropping buffering behavior")
    func busDerivedStreamsDoNotUseDroppingBufferPolicies() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/Bus.swift"))
        let declarations = [
            "public func messages",
            "public func errors()",
            "public func warnings()",
            "public func stateChanges()",
        ]
        var violations: [String] = []

        for declaration in declarations {
            let implementation = try Self.bracedDeclaration(beginningWith: declaration, in: source)
            if implementation.contains(".bufferingNewest") || implementation.contains(".bufferingOldest") {
                violations.append(declaration)
            }
        }

        #expect(
            violations.isEmpty,
            "Bus-derived streams must not use dropping AsyncStream policies:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Encoded packet docs describe best-effort realtime backpressure")
    func audioSourcePacketDocsDescribeBestEffortRealtimeBackpressure() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let docs = try Self.leadingDocumentationComment(
            for: "public func packets() -> AsyncStream<Buffer>",
            in: source
        )
        let normalized = docs.lowercased()

        #expect(normalized.contains("best-effort") || normalized.contains("best effort"))
        #expect(normalized.contains("realtime") || normalized.contains("real-time"))
        #expect(normalized.contains("drop"))
        #expect(normalized.contains("older"))
        #expect(
            normalized.contains("slow-consumer")
                || normalized.contains("slow consumer")
                || normalized.contains("backpressure")
        )
    }

    @Test("README documents GStreamer dependency preflight")
    func readmeDocumentsGStreamerDependencyPreflight() throws {
        let root = try Self.packageRoot()
        let readme = try Self.contents(of: root.appendingPathComponent("README.md"))
        let normalized = readme.lowercased()
        let requiredSnippets = [
            "pkgconf",
            "pkg-config",
            "gstreamer-1.0",
            "gstreamer-app-1.0",
            "gstreamer-video-1.0",
            "pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0",
            "brew install pkgconf gstreamer",
            "libgstreamer1.0-dev",
            "libgstreamer-plugins-base1.0-dev",
            "pkgconf-pkg-config",
            "gstreamer1-devel",
            "gstreamer1-plugins-base-devel",
        ]
        let missing = requiredSnippets.filter { !normalized.contains($0) }

        #expect(
            missing.isEmpty,
            "README is missing dependency/preflight guidance:\n\(missing.joined(separator: "\n"))"
        )
    }

    @Test("Device monitor tests do not silently skip on macOS CI")
    func deviceMonitorTestsDoNotUseSilentCISkipReturns() throws {
        let root = try Self.packageRoot()
        let source = try Self.contents(
            of: root.appendingPathComponent("Tests/SwiftGStreamerTests/DeviceMonitorTests.swift")
        )
        let disallowedSnippets = [
            "shouldSkipOnMacOSCI",
            "guard !shouldSkipOnMacOSCI() else { return }",
        ]
        let violations = disallowedSnippets.filter { source.contains($0) }

        #expect(
            violations.isEmpty,
            "DeviceMonitorTests must use deterministic zero-or-more assertions or Swift Testing traits, not silent returns:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Async media smoke tests keep post-loop evidence assertions")
    func asyncMediaSmokeTestsKeepPostLoopEvidenceAssertions() throws {
        let root = try Self.packageRoot()
        let requirements: [(file: String, declaration: String, snippets: [String])] = [
            (
                "Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift",
                "func videoFrameData() async throws",
                ["#require(firstFrame", "#expect(frame.bytes.byteCount == 4 * 4 * 4)"]
            ),
            (
                "Tests/SwiftGStreamerTests/AppSinkSmokeTests.swift",
                "func consistentFormat() async throws",
                ["#require(formats.count >= 3", "#expect(formats.allSatisfy"]
            ),
            (
                "Tests/SwiftGStreamerTests/CVPixelBufferTests.swift",
                "func convertBGRAFrame() async throws",
                ["#require(firstFrame", "#require(pixelBuffer"]
            ),
            (
                "Tests/SwiftGStreamerTests/CVPixelBufferTests.swift",
                "func convertNV12Frame() async throws",
                ["#require(firstFrame", "#require(pixelBuffer"]
            ),
            (
                "Tests/SwiftGStreamerTests/CVPixelBufferTests.swift",
                "func convertI420Frame() async throws",
                ["#require(firstFrame", "#require(pixelBuffer"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func videoFrameHasPTS() async throws",
                ["#require(frame.pts", "#expect(frameCount == 3)"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func videoFrameHasDuration() async throws",
                ["#require(firstFrame", "#require(frame.duration"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func appSourcePTSPreserved() async throws",
                ["#require(firstFrame", "#require(frame.pts", "#require(frame.duration"]
            ),
            (
                "Tests/SwiftGStreamerTests/TimestampTests.swift",
                "func calculateFPS() async throws",
                ["#require(firstFrame", "#require(frame.duration"]
            ),
            (
                "Tests/SwiftGStreamerTests/AudioTests.swift",
                "func audioBufferHasTimestamps() async throws",
                ["#require(firstBuffer", "#require(buffer.pts"]
            ),
            (
                "Tests/SwiftGStreamerTests/AudioTests.swift",
                "func audioBufferSampleCount() async throws",
                ["#require(firstBuffer", "#require(buffer.format == .s16le", "#require(buffer.channels == 2"]
            ),
        ]

        var missing: [String] = []
        for requirement in requirements {
            let source = try Self.contents(of: root.appendingPathComponent(requirement.file))
            let declaration = try Self.bracedDeclaration(beginningWith: requirement.declaration, in: source)

            for snippet in requirement.snippets where !declaration.contains(snippet) {
                missing.append("\(requirement.file) \(requirement.declaration): \(snippet)")
            }
        }

        #expect(
            missing.isEmpty,
            "Async smoke tests must prove awaited evidence before dependent assertions:\n\(missing.joined(separator: "\n"))"
        )
    }

    private static func staleVideoFrameReferencePatterns() -> [String] {
        let frameReceiver = "frame."
        let mappedAccess = "withMappedBytes"
        return [
            frameReceiver + mappedAccess,
            "VideoFrame/" + mappedAccess,
            frameReceiver + "mutableBytes",
            frameReceiver + "withUnsafeMutableBytes",
        ]
    }

    private static func containsMutableMigrationGuidance(_ documentation: String) -> Bool {
        let normalized = documentation.lowercased()
        let mentionsMutation = [
            "mutation",
            "mutate",
            "mutating",
            "modify",
            "modifying",
            "write",
            "writable",
        ].contains { normalized.contains($0) }
        let explainsCopy = normalized.contains("copy") || normalized.contains("copying")
        let namesBuffer = normalized.contains("buffer")
        let namesMutableDestination = normalized.contains("mutable structure")
            || normalized.contains("mutable data structure")
            || normalized.contains("another mutable")

        return mentionsMutation && explainsCopy && namesBuffer && namesMutableDestination
    }

    private static func videoFrameReferenceScanFiles(in root: URL) throws -> [URL] {
        var files = [root.appendingPathComponent("README.md")]
        files += try recursiveRegularFiles(in: root.appendingPathComponent("Examples")) { _ in
            true
        }
        files += try recursiveRegularFiles(in: root.appendingPathComponent("Tests")) { _ in
            true
        }
        files += try recursiveRegularFiles(in: root.appendingPathComponent("Sources/GStreamer")) { file in
            file.pathExtension == "swift" || file.path.contains(".docc/")
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func recursiveRegularFiles(
        in directory: URL,
        including shouldInclude: (URL) -> Bool
    ) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, shouldInclude(file) else {
                continue
            }
            files.append(file)
        }
        return files
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
                throw StaticAPISafetyError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
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

    private static func bracedDeclaration(beginningWith declaration: String, in source: String) throws -> String {
        guard let declarationRange = source.range(of: declaration) else {
            throw StaticAPISafetyError.declarationNotFound(declaration)
        }
        guard let openBrace = source[declarationRange.upperBound...].firstIndex(of: "{") else {
            throw StaticAPISafetyError.declarationNotFound(declaration)
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

        throw StaticAPISafetyError.unbalancedDeclaration(declaration)
    }

    private static func leadingDocumentationComment(for declaration: String, in source: String) throws -> String {
        guard let declarationRange = source.range(of: declaration) else {
            throw StaticAPISafetyError.declarationNotFound(declaration)
        }

        let prefix = source[..<declarationRange.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        var documentationLines: [String] = []

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("///") {
                documentationLines.append(trimmed)
                continue
            }
            if trimmed.isEmpty && documentationLines.isEmpty {
                continue
            }
            break
        }

        return documentationLines.reversed().joined(separator: "\n")
    }

    private static func containsBufferingNewestPolicy(
        source: String,
        implementation: String,
        expectedCount: Int
    ) -> Bool {
        if implementation.contains(".bufferingNewest(\(expectedCount))") {
            return true
        }

        let newestArguments = bufferingNewestArguments(in: implementation)
        if newestArguments.contains(where: { sourceDefinesIntegerConstant($0, in: source, equalTo: expectedCount) }) {
            return true
        }

        let policyArguments = bufferingPolicyArguments(in: implementation)
        return policyArguments.contains { argument in
            sourceDefinesBufferingPolicyConstant(argument, in: source, newestCount: expectedCount)
        }
    }

    private static func bufferingNewestArguments(in source: String) -> [String] {
        arguments(after: ".bufferingNewest(", in: source)
    }

    private static func bufferingPolicyArguments(in source: String) -> [String] {
        arguments(after: "bufferingPolicy:", in: source)
            .map { argument in
                if let commaIndex = argument.firstIndex(of: ",") {
                    return String(argument[..<commaIndex])
                }
                return argument
            }
    }

    private static func arguments(after marker: String, in source: String) -> [String] {
        var arguments: [String] = []
        var searchStart = source.startIndex

        while let markerRange = source.range(of: marker, range: searchStart..<source.endIndex) {
            if marker.hasSuffix("(") {
                var index = markerRange.upperBound
                let argumentStart = index
                var depth = 1

                while index < source.endIndex {
                    switch source[index] {
                    case "(":
                        depth += 1
                    case ")":
                        depth -= 1
                        if depth == 0 {
                            arguments.append(String(source[argumentStart..<index]))
                            searchStart = source.index(after: index)
                            break
                        }
                    default:
                        break
                    }
                    index = source.index(after: index)
                }

                if depth != 0 {
                    break
                }
            } else {
                var index = markerRange.upperBound
                while index < source.endIndex, source[index].isWhitespace {
                    index = source.index(after: index)
                }
                let argumentStart = index
                while index < source.endIndex, source[index] != ")" && source[index] != "\n" {
                    index = source.index(after: index)
                }
                arguments.append(String(source[argumentStart..<index]))
                searchStart = index
            }
        }

        return arguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func sourceDefinesIntegerConstant(_ expression: String, in source: String, equalTo value: Int) -> Bool {
        let names = candidateConstantNames(from: expression)
        return names.contains { name in
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"(?m)\b(?:public\s+|internal\s+|fileprivate\s+|private\s+|static\s+)*let\s+\#(escapedName)\b[^\n=]*=\s*\#(value)\b"#
            return source.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func sourceDefinesBufferingPolicyConstant(
        _ expression: String,
        in source: String,
        newestCount: Int
    ) -> Bool {
        let names = candidateConstantNames(from: expression)
        return names.contains { name in
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = #"(?m)\b(?:public\s+|internal\s+|fileprivate\s+|private\s+|static\s+)*let\s+\#(escapedName)\b[^\n=]*=[^\n]*\.bufferingNewest\(\s*\#(newestCount)\s*\)"#
            return source.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func candidateConstantNames(from expression: String) -> [String] {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedPrefixes = ["Self.", "AudioSource.", "AudioBufferSink.", "AudioPacketSink."]
            .reduce(into: trimmed) { result, prefix in
                if result.hasPrefix(prefix) {
                    result = String(result.dropFirst(prefix.count))
                }
            }
        var names = [trimmed, strippedPrefixes]

        if let lastComponent = trimmed.split(separator: ".").last {
            names.append(String(lastComponent))
        }

        return Array(Set(names)).filter { !$0.isEmpty }
    }
}

private enum StaticAPISafetyError: Error {
    case packageRootNotFound(String)
    case declarationNotFound(String)
    case unbalancedDeclaration(String)
}
