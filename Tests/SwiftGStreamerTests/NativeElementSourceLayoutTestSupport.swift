import Foundation

enum NativeElementSourceLayoutTestSupport {
    static func nativeElementSwiftSource() throws -> String {
        try concatenatedSourceFiles(
            in: "Sources/GStreamer/NativeElements",
            withPathExtension: "swift"
        )
    }

    static func baseShimCSource() throws -> String {
        try concatenatedSourceFiles(
            in: "Sources/CGStreamerBaseShim",
            withPathExtension: "c"
        )
    }

    static func contents(of relativePath: String) throws -> String {
        let file = try packageRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func concatenatedSourceFiles(
        in relativeDirectory: String,
        withPathExtension pathExtension: String
    ) throws -> String {
        let directory = try packageRoot().appendingPathComponent(relativeDirectory)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try files
            .filter { $0.pathExtension == pathExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
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
                throw NativeElementSourceLayoutTestSupportError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }
}

private enum NativeElementSourceLayoutTestSupportError: Error {
    case packageRootNotFound(String)
}
