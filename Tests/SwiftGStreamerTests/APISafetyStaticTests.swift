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

    @Test("ReliablePackets public API surface remains source-compatible")
    func reliablePacketsPublicAPISurfaceRemainsSourceCompatible() throws {
        let root = try Self.packageRoot()
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))

        #expect(
            Self.containsStructConformance(
                typeName: "ReliablePackets",
                genericClause: "<Element: Sendable>",
                conformances: ["AsyncSequence", "Sendable"],
                in: source
            ),
            "ReliablePackets must be public, generic over Sendable elements, and conform to AsyncSequence + Sendable"
        )
        #expect(
            Self.containsNestedIteratorConformance(in: source),
            "ReliablePackets.AsyncIterator must conform to AsyncIteratorProtocol + Sendable"
        )
        #expect(
            Self.containsReliableNextSignature(in: source),
            "ReliablePackets.AsyncIterator.next() must be @concurrent/equivalent and async throws -> Element?"
        )
        #expect(
            source.range(
                of: #"public\s+func\s+makeAsyncIterator\(\)\s*->\s*AsyncIterator"#,
                options: .regularExpression
            ) != nil,
            "ReliablePackets must expose public makeAsyncIterator() -> AsyncIterator"
        )
    }

    @Test("Audio file source API exposes only the reliable file/decode surface")
    func audioFileSourceAPIExposesOnlyReliableFileDecodeSurface() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let microphoneBuilder = try Self.bracedDeclaration(beginningWith: "public struct AudioSourceBuilder", in: audioSource)

        #expect(source.contains("public static func file(path: String) -> AudioFileSourceBuilder"))
        #expect(Self.containsSendableType("AudioFileSourceBuilder", in: source))
        #expect(Self.containsSendableType("AudioFileSource", in: source))
        #expect(source.contains("public func build() throws -> AudioFileSource"))
        #expect(source.contains("public func withEncoding(_ encoding: AudioSource.Encoding) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withOpusEncoding(bitrate: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withAACEncoding(bitrate: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withFormat(_ format: AudioFormat) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withSampleRate(_ rate: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("public func withChannels(_ channels: Int) -> AudioFileSourceBuilder"))
        #expect(source.contains("case raw"))
        #expect(source.contains("case opus(bitrate: Int)"))
        #expect(source.contains("case aac(bitrate: Int)"))
        #expect(source.contains("public func reliablePackets() -> ReliablePackets<Buffer>"))
        #expect(!microphoneBuilder.contains("reliablePackets("))
    }

    @Test("RFC-002 live reliable audio public API surface is additive and scoped")
    func rfc002LiveReliableAudioPublicAPISurfaceIsAdditiveAndScoped() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let audioFileSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let videoSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/VideoSource.swift"))
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let audioSourceClass = try Self.bracedDeclaration(beginningWith: "public final class AudioSource", in: audioSource)
        let audioBuilder = try Self.bracedDeclaration(beginningWith: "public struct AudioSourceBuilder", in: audioSource)
        let videoSourceClass = try Self.bracedDeclaration(beginningWith: "public final class VideoSource", in: videoSource)
        let videoBuilder = try Self.bracedDeclaration(beginningWith: "public struct VideoSourceBuilder", in: videoSource)
        let audioFileSourceType = try Self.bracedDeclaration(beginningWith: "public struct AudioFileSource", in: audioFileSource)

        #expect(
            Self.containsReliableDeliveryBuilderSignature(in: audioBuilder),
            "AudioSourceBuilder.withReliableDelivery must default to leaky: .none, maxBuffers: 256, maxBytes: nil, maxTime: .seconds(2)"
        )
        #expect(
            audioSourceClass.range(
                of: #"public\s+func\s+reliablePackets\(\)\s+throws\s*->\s*ReliablePackets<\s*ReliablePacket<\s*Buffer\s*>\s*>"#,
                options: .regularExpression
            ) != nil,
            "AudioSource must expose reliablePackets() throws -> ReliablePackets<ReliablePacket<Buffer>>"
        )
        #expect(
            audioSourceClass.range(
                of: #"public\s+func\s+finalize\(\s*timeout:\s*Duration\s*=\s*\.seconds\(\s*5\s*\)\s*\)\s+async\s+throws"#,
                options: .regularExpression
            ) != nil,
            "AudioSource.finalize(timeout:) must default to .seconds(5)"
        )
        #expect(
            Self.containsReliablePacketDeclaration(in: source),
            "ReliablePacket must be public, generic over Sendable payloads, and Sendable"
        )
        #expect(
            Self.containsDiscontinuityDeclarationWithExactKinds(in: source),
            "Discontinuity.Kind must expose exactly formatChange, discont, gap, and dropped"
        )
        #expect(
            !source.contains("public enum LiveSourceDeliveryPolicy")
                && !source.contains("public struct LiveSourceDeliveryPolicy")
                && !source.contains("public final class LiveSourceDeliveryPolicy"),
            "RFC-002 must not add a public LiveSourceDeliveryPolicy type"
        )
        #expect(
            !videoSourceClass.contains("public func reliablePackets("),
            "RFC-002 is audio-only; VideoSource must not expose reliablePackets()"
        )
        #expect(
            !videoBuilder.contains("public func withReliableDelivery("),
            "RFC-002 is audio-only; VideoSourceBuilder must not expose withReliableDelivery(...)"
        )
        #expect(
            audioFileSourceType.contains("public func reliablePackets() -> ReliablePackets<Buffer>"),
            "AudioFileSource.reliablePackets() must remain source-compatible"
        )
    }

    @Test("Audio file build remains lazy until reliable packet iteration starts")
    func audioFileBuildRemainsLazyUntilReliablePacketIterationStarts() throws {
        let root = try Self.packageRoot()
        let source = try Self.combinedSwiftSources(in: root.appendingPathComponent("Sources/GStreamer"))
        let builder = try Self.bracedDeclaration(beginningWith: "public struct AudioFileSourceBuilder", in: source)
        let build = try Self.bracedDeclaration(beginningWith: "public func build() throws -> AudioFileSource", in: builder)

        #expect(build.contains("GStreamerError.invalidArgument"))
        #expect(!build.contains("Pipeline("))
        #expect(!build.contains(".play()"))
        #expect(!build.contains("setState(.playing)"))
    }

    @Test("Reliable audio file construction does not interpolate raw file paths or URIs")
    func reliableAudioFileConstructionDoesNotInterpolateRawFilePathsOrURIs() throws {
        let root = try Self.packageRoot()
        let files = try Self.recursiveRegularFiles(in: root.appendingPathComponent("Sources/GStreamer")) { file in
            file.pathExtension == "swift"
        }
        let disallowedSnippets = [
            #"file://\(path)"#,
            #"file://\(url.path)"#,
            #"uri=\(uri)"#,
            #"uri=\(path)"#,
            #"uri=\(filePath)"#,
            #"location=\(path)"#,
            #"URIDecodeSource(uri: "file://\(path)")"#,
        ]
        var violations: [String] = []

        for file in files {
            let contents = try Self.contents(of: file)
            let scansReliableAudioConstruction = contents.contains("AudioFileSource")
                || contents.contains("ReliablePackets")
                || file.lastPathComponent == "URIDecodeSource.swift"

            guard scansReliableAudioConstruction else { continue }

            for snippet in disallowedSnippets where contents.contains(snippet) {
                violations.append("\(Self.relativePath(file, to: root)): \(snippet)")
            }
        }

        #expect(
            violations.isEmpty,
            "Use URL/path property escaping instead of raw interpolation in file/decode pipeline construction:\n\(violations.joined(separator: "\n"))"
        )
    }

    @Test("Reliable bridge is pull based, cancellable, and non-dropping")
    func reliableBridgeIsPullBasedCancellableAndNonDropping() throws {
        let root = try Self.packageRoot()
        let reliablePackets = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/ReliablePackets.swift")
        )
        let audioFileSource = try Self.contents(
            of: root.appendingPathComponent("Sources/GStreamer/AudioFileSource.swift")
        )
        let reliableSource = try Self.bracedDeclaration(
            beginningWith: "private final class AudioFileReliablePacketSource",
            in: audioFileSource
        )
        let activeCandidate = try Self.bracedDeclaration(
            beginningWith: "private final class ActiveCandidate",
            in: audioFileSource
        )
        let source = [reliablePackets, reliableSource, activeCandidate].joined(separator: "\n")

        #expect(source.contains("withTaskCancellationHandler"))
        #expect(source.contains("swift_gst_app_sink_try_pull_sample"))
        #expect(!source.contains("swift_gst_app_sink_pull_sample"))
        #expect(!source.contains(".bufferingNewest"))
        #expect(!source.contains(".bufferingOldest"))
    }

    @Test("Realtime AudioSource.packets stays delegated and lossy")
    func realtimeAudioSourcePacketsStaysDelegatedAndLossy() throws {
        let root = try Self.packageRoot()
        let audioSource = try Self.contents(of: root.appendingPathComponent("Sources/GStreamer/AudioSource.swift"))
        let publicPackets = try Self.bracedDeclaration(
            beginningWith: "public func packets() -> AsyncStream<Buffer>",
            in: audioSource
        )
        let audioPacketSink = try Self.bracedDeclaration(
            beginningWith: "private final class AudioPacketSink",
            in: audioSource
        )
        let delegatedPackets = try Self.bracedDeclaration(
            beginningWith: "func packets() -> AsyncStream<Buffer>",
            in: audioPacketSink
        )

        #expect(publicPackets.contains("return packetSink.packets()"))
        #expect(
            Self.containsBufferingNewestPolicy(
                source: audioSource,
                implementation: delegatedPackets,
                expectedCount: 8
            )
        )
        #expect(audioSource.contains("drop=true"))
        #expect(audioSource.contains("max-buffers=1"))
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

    private static func combinedSwiftSources(in directory: URL) throws -> String {
        let files = try recursiveRegularFiles(in: directory) { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        let chunks = try files.map { file in
            try "// \(file.lastPathComponent)\n" + contents(of: file)
        }
        return chunks.joined(separator: "\n")
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

    private static func containsStructConformance(
        typeName: String,
        genericClause: String,
        conformances: [String],
        in source: String
    ) -> Bool {
        guard let declarationLine = source
            .split(separator: "\n")
            .first(where: {
                $0.contains("public struct \(typeName)\(genericClause)")
            })
        else {
            return false
        }

        return conformances.allSatisfy { declarationLine.contains($0) }
    }

    private static func containsNestedIteratorConformance(in source: String) -> Bool {
        guard let reliablePackets = try? bracedDeclaration(beginningWith: "public struct ReliablePackets", in: source),
              let iteratorLine = reliablePackets
                .split(separator: "\n")
                .first(where: { $0.contains("struct AsyncIterator") || $0.contains("public struct AsyncIterator") })
        else {
            return false
        }

        return iteratorLine.contains("AsyncIteratorProtocol") && iteratorLine.contains("Sendable")
    }

    private static func containsReliableNextSignature(in source: String) -> Bool {
        guard let reliablePackets = try? bracedDeclaration(beginningWith: "public struct ReliablePackets", in: source),
              let iterator = try? bracedDeclaration(beginningWith: "public struct AsyncIterator", in: reliablePackets)
        else {
            return false
        }

        let normalized = iterator.replacingOccurrences(of: "\n", with: " ")
        let hasThrowingSignature = normalized.range(
            of: #"(?:mutating\s+)?func\s+next\(\)\s+async\s+throws\s*->\s*Element\?"#,
            options: .regularExpression
        ) != nil
        let hasConcurrentIsolation = normalized.contains("@concurrent")
            || normalized.contains("nonisolated")

        return hasThrowingSignature && hasConcurrentIsolation
    }

    private static func containsSendableType(_ typeName: String, in source: String) -> Bool {
        source.range(
            of: #"public\s+(?:struct|final\s+class|actor)\s+\#(typeName)\b[^\n{]*(?:@unchecked\s+)?Sendable"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsReliableDeliveryBuilderSignature(in source: String) -> Bool {
        guard let declaration = try? bracedDeclaration(
            beginningWith: "public func withReliableDelivery",
            in: source
        ) else {
            return false
        }

        let signatureSource = declaration.split(separator: "{", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? declaration
        let signature = signatureSource.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return signature.range(of: #"->\s*AudioSourceBuilder"#, options: .regularExpression) != nil
            && signature.range(
                of: #"leaky:\s*QueueLeaky\s*=\s*\.none"#,
                options: .regularExpression
            ) != nil
            && signature.range(
                of: #"maxBuffers:\s*(?:UInt|Int)\?\s*=\s*256"#,
                options: .regularExpression
            ) != nil
            && signature.range(
                of: #"maxBytes:\s*(?:UInt|Int)\?\s*=\s*nil"#,
                options: .regularExpression
            ) != nil
            && signature.range(
                of: #"maxTime:\s*Duration\?\s*=\s*\.seconds\(\s*2\s*\)"#,
                options: .regularExpression
            ) != nil
    }

    private static func containsReliablePacketDeclaration(in source: String) -> Bool {
        source.range(
            of: #"public\s+struct\s+ReliablePacket\s*<\s*Payload\s*:\s*Sendable\s*>\s*:\s*Sendable\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func containsDiscontinuityDeclarationWithExactKinds(in source: String) -> Bool {
        guard source.range(
            of: #"public\s+struct\s+Discontinuity\s*:\s*Sendable\b"#,
            options: .regularExpression
        ) != nil,
            let discontinuity = try? bracedDeclaration(beginningWith: "public struct Discontinuity", in: source),
            let kind = try? bracedDeclaration(beginningWith: "public enum Kind", in: discontinuity)
        else {
            return false
        }

        let cases = kind
            .split(separator: "\n")
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("case ") else { return [] }
                return trimmed
                    .dropFirst("case ".count)
                    .split(separator: ",")
                    .map { String($0.trimmingCharacters(in: .whitespaces)) }
                    .map { name in
                        if let paren = name.firstIndex(of: "(") {
                            return String(name[..<paren])
                        }
                        return name
                    }
            }

        let requiredFields = [
            "public let kind: Kind",
            "public let priorPTS: UInt64?",
            "public let priorDuration: UInt64?",
            "public let nextPTS: UInt64?",
            "public let duration: UInt64?",
            "public let droppedCount: Int?",
        ]

        return cases == ["formatChange", "discont", "gap", "dropped"]
            && kind.split(separator: "\n").first(where: { $0.contains("public enum Kind") })?.contains("Sendable") == true
            && requiredFields.allSatisfy { discontinuity.contains($0) }
            && discontinuity.range(of: #"public\s+var\s+pts\b"#, options: .regularExpression) == nil
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
