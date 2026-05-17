import Foundation
import Testing
import CGStreamerTestSupport
@testable import GStreamer

@Suite("Pad Direction Importability Tests", .serialized, .timeLimit(.minutes(1)))
struct PadDirectionImportabilityTests {
    init() throws {
        try GStreamer.initialize()
    }

    @Test
    func staticSourcePadsExposeStableDirections() throws {
        // Given a GStreamer element has a static source pad
        let queue = try Element.make(factory: "queue")
        let sourcePad = try #require(queue.staticPad("src"))

        // When Swift reads the pad direction
        let direction = sourcePad.direction

        // Then the public pad direction is source
        #expect(direction == .source)
    }

    @Test
    func staticSinkPadsExposeStableDirections() throws {
        // Given a GStreamer element has a static sink pad
        let queue = try Element.make(factory: "queue")
        let sinkPad = try #require(queue.staticPad("sink"))

        // When Swift reads the pad direction
        let direction = sinkPad.direction

        // Then the public pad direction is sink
        #expect(direction == .sink)
    }

    @Test
    func requestPadsExposeStableSourceDirection() throws {
        // Given a tee element creates a requested source pad
        let tee = try Element.make(factory: "tee")
        let requestPad = try #require(tee.requestPad("src_%u"))
        defer { tee.releasePad(requestPad) }

        // When Swift reads the requested pad direction
        let direction = requestPad.direction

        // Then the public pad direction is source
        #expect(direction == .source)
    }

    @Test
    func unknownPadDirectionsRemainRepresentable() {
        // Given GStreamer reports a pad direction that is neither source nor sink
        let unknownDirection = GstPadDirection(rawValue: 0)

        // When Swift maps the pad direction into the public API
        let direction = Pad.Direction(gstPadDirection: unknownDirection)

        // Then the public pad direction is unknown
        #expect(direction == .unknown)
    }

    @Test
    func importerSensitiveEnvironmentsCompilePadDirectionSupport() throws {
        // Given the package is built with a Swift importer that does not expose GStreamer pad direction constants as top-level Swift names
        let root = try Self.packageRoot()
        let swiftSources = try Self.swiftSourcesUnderGStreamer(in: root)
        let forbiddenTokens = ["GST_PAD_SRC", "GST_PAD_SINK"]

        // When Swift compiles the GStreamer target
        var violations: [String] = []
        for source in swiftSources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            for token in forbiddenTokens where contents.contains(token) {
                violations.append("\(Self.relativePath(source, to: root)): \(token)")
            }
        }

        // Then the package still compiles
        // And Swift callers can read source, sink, and unknown pad directions
        #expect(
            violations.isEmpty,
            "Remove importer-sensitive GStreamer pad direction constants from Swift source:\n\(violations.sorted().joined(separator: "\n"))"
        )
    }

    private static func swiftSourcesUnderGStreamer(in root: URL) throws -> [URL] {
        let sourceRoot = root.appendingPathComponent("Sources/GStreamer")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [URL] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, file.pathExtension == "swift" else {
                continue
            }
            sources.append(file)
        }
        return sources.sorted { $0.path < $1.path }
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
                throw PadDirectionImportabilityTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
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

private enum PadDirectionImportabilityTestError: Error {
    case packageRootNotFound(String)
}
