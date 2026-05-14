import Foundation
import Testing

@Suite("CGStreamerBase Introduction BDD Tests")
struct CGStreamerBaseIntroductionBDDTests {

    @Test("Maintainer adds the GStreamer Base system library")
    func maintainerAddsTheGStreamerBaseSystemLibrary() throws {
        // Given the package already resolves GStreamer core, app, and video libraries
        let manifest = try Self.contents(of: "Package.swift")
        let baseTarget = try Self.packageTarget(named: "CGStreamerBase", in: manifest)
        let gstreamerTarget = try Self.packageTarget(named: "GStreamer", in: manifest)
        let baseHeader = try Self.contents(of: "Sources/CGStreamerBase/gstreamer_base.h")
        let moduleMap = try Self.contents(of: "Sources/CGStreamerBase/module.modulemap")

        // When the maintainer prepares Phase 0 native elements dependency plumbing
        let normalizedBaseTarget = Self.normalizedWhitespace(baseTarget)
        let normalizedGStreamerTarget = Self.normalizedWhitespace(gstreamerTarget)

        // Then SwiftPM can resolve the GStreamer Base system library
        #expect(normalizedBaseTarget.contains(#".systemLibrary( name: "CGStreamerBase""#))
        #expect(normalizedBaseTarget.contains(#"pkgConfig: "gstreamer-base-1.0""#))
        #expect(normalizedBaseTarget.contains(#".brew(["gstreamer"])"#))
        #expect(normalizedBaseTarget.contains(#".apt(["libgstreamer-plugins-base1.0-dev"])"#))
        #expect(Self.containsIncludeGuard(named: "CGSTREAMER_BASE_H", in: baseHeader))
        #expect(baseHeader.contains("#include <gst/base/gstbase.h>"))
        #expect(Self.normalizedWhitespace(moduleMap).contains("module CGStreamerBase [system]"))
        #expect(moduleMap.contains(#"header "gstreamer_base.h""#))
        #expect(moduleMap.contains(#"link "gstbase-1.0""#))
        #expect(moduleMap.contains("export *"))

        // And the public GStreamer target includes the Base dependency layer
        #expect(normalizedGStreamerTarget.contains(#"name: "GStreamer""#))
        #expect(gstreamerTarget.contains(#""CGStreamerBase""#))
        #expect(gstreamerTarget.contains(#""CGStreamerBaseShim""#))
    }

    @Test("Native elements implementer gets an empty Base shim target")
    func nativeElementsImplementerGetsAnEmptyBaseShimTarget() throws {
        // Given future native element phases need BaseSink and BaseTransform headers
        let manifest = try Self.contents(of: "Package.swift")
        let shimTarget = try Self.packageTarget(named: "CGStreamerBaseShim", in: manifest)
        let gstreamerTarget = try Self.packageTarget(named: "GStreamer", in: manifest)
        let shimHeader = try Self.contents(of: "Sources/CGStreamerBaseShim/include/GStreamerBaseShim.h")
        let shimSource = try Self.contents(of: "Sources/CGStreamerBaseShim/GStreamerBaseShim.c")

        // When Phase 0 adds the dedicated Base shim target
        let normalizedShimTarget = Self.normalizedWhitespace(shimTarget)

        // Then the shim compiles the GStreamer Base header surface
        #expect(normalizedShimTarget.contains(#".target( name: "CGStreamerBaseShim""#))
        #expect(normalizedShimTarget.contains(#"dependencies: ["CGStreamer", "CGStreamerBase"]"#))
        #expect(normalizedShimTarget.contains(#"path: "Sources/CGStreamerBaseShim""#))
        #expect(normalizedShimTarget.contains(#"publicHeadersPath: "include""#))
        #expect(gstreamerTarget.contains(#""CGStreamerBaseShim""#))
        #expect(Self.containsIncludeGuard(named: "GSTREAMER_BASE_SHIM_H", in: shimHeader))
        #expect(shimHeader.contains("#include <gst/gst.h>"))
        #expect(shimHeader.contains("#include <gst/base/gstbasesink.h>"))
        #expect(shimHeader.contains("#include <gst/base/gstbasetransform.h>"))
        #expect(shimSource.contains(#"#include "include/GStreamerBaseShim.h""#))

        // And the shim exports no native element behavior yet
        #expect(!shimHeader.contains("swift_gst_"))
        #expect(!shimSource.contains("swift_gst_"))
        #expect(
            Self.nonCommentNonPreprocessorLines(in: shimSource).isEmpty,
            "Phase 0 GStreamerBaseShim.c should contain only its public-header include and comments"
        )
    }

    @Test("CI verifies the Native Elements dependency baseline")
    func ciVerifiesTheNativeElementsDependencyBaseline() throws {
        // Given native elements require GStreamer core, app, video, and base modules at 1.28.2 or newer
        let workflow = try Self.contents(of: ".github/workflows/ci.yml")
        let ubuntuDependencyStep = try Self.workflowStep(
            namedAnyOf: [
                "Install Swift and GStreamer dependencies (Ubuntu)",
                "Install GStreamer dependencies (Ubuntu)",
                "Install Linuxbrew GStreamer dependencies (Ubuntu)",
            ],
            in: workflow
        )
        let macOSDependencyStep = try Self.workflowStep(
            named: "Install GStreamer dependencies (macOS)",
            in: workflow
        )
        let preflightStep = try Self.workflowStep(named: "Preflight GStreamer dependencies", in: workflow)
        let buildStep = try Self.workflowStep(named: "Build", in: workflow)
        let testStep = try Self.workflowStep(named: "Test serially", in: workflow)
        let symbolGraphStep = try Self.workflowStep(named: "Dump public symbol graph", in: workflow)

        // When CI installs and preflights this package's GStreamer dependencies
        let normalizedPreflightStep = Self.normalizedWhitespace(preflightStep)

        // Then macOS uses Homebrew and Ubuntu uses Linuxbrew for GStreamer development libraries and tools
        #expect(ubuntuDependencyStep.contains("if: runner.os == 'Linux'"))
        #expect(Self.normalizedWhitespace(ubuntuDependencyStep).contains("brew install pkgconf gstreamer"))
        #expect(
            Self.disallowedUbuntuAptGStreamerPackages.filter { workflow.contains($0) }.isEmpty,
            "Ubuntu CI should source this package's GStreamer modules from Linuxbrew, not apt packages"
        )
        #expect(macOSDependencyStep.contains("if: runner.os == 'macOS'"))
        #expect(Self.normalizedWhitespace(macOSDependencyStep).contains("brew install pkgconf gstreamer"))

        // And every CI step that needs GStreamer sees the same package-manager environment
        #expect(Self.hasLinuxbrewEnvironmentBefore("pkg-config --exists", in: preflightStep))
        #expect(Self.hasLinuxbrewEnvironmentBefore("gst-inspect-1.0 --version", in: preflightStep))
        #expect(Self.hasLinuxbrewEnvironmentBefore("swiftly run swift build", in: buildStep))
        #expect(Self.hasLinuxbrewEnvironmentBefore("swiftly run swift test --no-parallel", in: testStep))
        #expect(
            Self.hasLinuxbrewEnvironmentBefore("swiftly run swift package dump-symbol-graph", in: symbolGraphStep)
        )

        // And CI reports and enforces the version baseline for all four pkg-config modules
        #expect(
            normalizedPreflightStep.contains(
                "pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gstreamer-base-1.0"
            )
        )
        for module in Self.requiredGStreamerModules {
            #expect(
                normalizedPreflightStep.contains("pkg-config --atleast-version=1.28.2 \(module)"),
                "CI must enforce GStreamer 1.28.2+ for \(module)"
            )
            #expect(
                normalizedPreflightStep.contains("pkg-config --modversion \(module)"),
                "CI must print the resolved pkg-config version for \(module)"
            )
            #expect(
                preflightStep.contains("\(module):"),
                "CI modversion output should label \(module)"
            )
        }
    }

    @Test("Dependency documentation names the required Base module")
    func dependencyDocumentationNamesTheRequiredBaseModule() throws {
        // Given package users follow README setup instructions before building
        let readme = try Self.contents(of: "README.md")

        // When the Base dependency layer becomes part of the package target graph
        let normalizedReadme = Self.normalizedWhitespace(readme)

        // Then the documented dependency preflight includes the GStreamer Base pkg-config module
        #expect(readme.contains("gstreamer-base-1.0"))
        #expect(
            normalizedReadme.contains(
                "pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gstreamer-base-1.0"
            )
        )
        #expect(
            normalizedReadme.contains(
                "pkg-config --modversion gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0 gstreamer-base-1.0"
            )
        )
    }

    private static let requiredGStreamerModules = [
        "gstreamer-1.0",
        "gstreamer-app-1.0",
        "gstreamer-video-1.0",
        "gstreamer-base-1.0",
    ]

    private static let disallowedUbuntuAptGStreamerPackages = [
        "libgstreamer1.0-dev",
        "libgstreamer-plugins-base1.0-dev",
        "gstreamer1.0-tools",
        "gstreamer1.0-plugins-base",
        "gstreamer1.0-plugins-good",
        "gstreamer1.0-plugins-bad",
        "gstreamer1.0-plugins-ugly",
        "gstreamer1.0-libav",
    ]

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
                throw CGStreamerBaseIntroductionBDDTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func packageTarget(named targetName: String, in manifest: String) throws -> String {
        let nameMarker = #"name: "\#(targetName)""#
        let targetKinds = [
            ".systemLibrary(",
            ".target(",
            ".testTarget(",
            ".executableTarget(",
        ]

        for kind in targetKinds {
            var searchStart = manifest.startIndex
            while let kindRange = manifest.range(of: kind, range: searchStart..<manifest.endIndex) {
                let declaration = try Self.balancedParenthesesDeclaration(
                    startingAt: kindRange.lowerBound,
                    in: manifest
                )
                if declaration.contains(nameMarker) {
                    return declaration
                }

                searchStart = kindRange.upperBound
            }
        }

        throw CGStreamerBaseIntroductionBDDTestError.packageTargetNotFound(targetName)
    }

    private static func balancedParenthesesDeclaration(
        startingAt start: String.Index,
        in source: String
    ) throws -> String {
        guard let openParen = source[start...].firstIndex(of: "(") else {
            throw CGStreamerBaseIntroductionBDDTestError.unbalancedDeclaration
        }

        var depth = 0
        var index = openParen
        while index < source.endIndex {
            let character = source[index]
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 {
                    return String(source[start...index])
                }
            }

            index = source.index(after: index)
        }

        throw CGStreamerBaseIntroductionBDDTestError.unbalancedDeclaration
    }

    private static func workflowStep(named stepName: String, in workflow: String) throws -> String {
        try workflowStep(namedAnyOf: [stepName], in: workflow)
    }

    private static func workflowStep(namedAnyOf stepNames: [String], in workflow: String) throws -> String {
        for stepName in stepNames {
            let marker = "- name: \(stepName)"
            guard let stepStart = workflow.range(of: marker)?.lowerBound else {
                continue
            }

            let remaining = workflow[stepStart...]
            let searchRange = remaining.index(after: remaining.startIndex)..<remaining.endIndex
            let nextStepStart = remaining
                .range(of: "\n      - name: ", options: [], range: searchRange)?
                .lowerBound ?? workflow.endIndex

            return String(workflow[stepStart..<nextStepStart])
        }

        throw CGStreamerBaseIntroductionBDDTestError.workflowStepNotFound(stepNames.joined(separator: ", "))
    }

    private static func hasLinuxbrewEnvironmentBefore(_ command: String, in step: String) -> Bool {
        step.contains(Self.linuxRunnerGuard)
            && Self.snippetsAppearInOrder([Self.linuxbrewShellenv, command], in: step)
    }

    private static var linuxRunnerGuard: String {
        #"if [[ "$RUNNER_OS" == "Linux" ]]"#
    }

    private static var linuxbrewShellenv: String {
        #"eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)""#
    }

    private static func containsIncludeGuard(named guardName: String, in source: String) -> Bool {
        let trimmedLines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return trimmedLines.contains("#ifndef \(guardName)")
            && trimmedLines.contains("#define \(guardName)")
            && trimmedLines.contains { line in
                line == "#endif" || line == "#endif /* \(guardName) */"
            }
    }

    private static func nonCommentNonPreprocessorLines(in source: String) -> [String] {
        let withoutBlockComments = Self.removingBlockComments(from: source)

        return withoutBlockComments
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                let withoutLineComment = line
                    .split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init) ?? ""
                let trimmed = withoutLineComment.trimmingCharacters(in: .whitespaces)

                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                    return nil
                }

                return trimmed
            }
    }

    private static func removingBlockComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index...].hasPrefix("/*") {
                let searchStart = source.index(index, offsetBy: 2)
                guard let commentEnd = source.range(of: "*/", range: searchStart..<source.endIndex) else {
                    break
                }
                index = commentEnd.upperBound
            } else {
                result.append(source[index])
                index = source.index(after: index)
            }
        }

        return result
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

    private static func normalizedWhitespace(_ source: String) -> String {
        source
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private enum CGStreamerBaseIntroductionBDDTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)
    case packageTargetNotFound(String)
    case unbalancedDeclaration
    case workflowStepNotFound(String)

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not locate Package.swift from \(filePath)"
        case .packageTargetNotFound(let targetName):
            "Could not find Package.swift target named \(targetName)"
        case .unbalancedDeclaration:
            "Could not parse a balanced Package.swift target declaration"
        case .workflowStepNotFound(let stepName):
            "Could not find workflow step named \(stepName)"
        }
    }
}
