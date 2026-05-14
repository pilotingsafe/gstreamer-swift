import Testing
import Foundation

@Suite("Linux CI Ubuntu Dependency BDD Tests")
struct LinuxCIUbuntuDependencyBDDTests {

    @Test("Ubuntu dependency setup resolves the GStreamer libunwind dependency")
    func ubuntuDependencySetupResolvesGStreamerLibunwindDependency() throws {
        // Given the Ubuntu 22.04 CI runner may have versioned LLVM libunwind development packages installed
        // And GStreamer development headers require the unversioned libunwind development package
        let workflow = try Self.contents(of: ".github/workflows/ci.yml")
        let ubuntuStep = try Self.workflowStep(
            named: "Install Swift and GStreamer dependencies (Ubuntu)",
            in: workflow
        )

        // When Linux CI installs Swift support and GStreamer dependencies
        // Then the workflow removes conflicting versioned libunwind development packages first
        #expect(ubuntuStep.contains("if: runner.os == 'Linux'"))
        #expect(
            try Self.snippetsAppearInOrder(
                [
                    "sudo apt-get update",
                    "sudo apt-get remove -y libunwind-13-dev libunwind-14-dev",
                    "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y",
                ],
                in: ubuntuStep
            ),
            "Ubuntu CI must remove versioned libunwind development packages before the apt install transaction"
        )

        // And the workflow installs the unversioned libunwind development package before GStreamer development headers
        let packageList = try Self.aptInstallPackageList(in: ubuntuStep)
        #expect(
            try Self.snippetsAppearInOrder(
                [
                    "libunwind-dev",
                    "libgstreamer1.0-dev",
                ],
                in: packageList
            ),
            "Ubuntu CI must install libunwind-dev before libgstreamer1.0-dev"
        )
    }

    @Test("Ubuntu setup keeps existing Swift and GStreamer dependencies")
    func ubuntuSetupKeepsExistingSwiftAndGStreamerDependencies() throws {
        // Given the package still needs Swift support libraries and GStreamer runtime plugins on Ubuntu
        let workflow = try Self.contents(of: ".github/workflows/ci.yml")
        let ubuntuStep = try Self.workflowStep(
            named: "Install Swift and GStreamer dependencies (Ubuntu)",
            in: workflow
        )
        let packageList = try Self.aptInstallPackageList(in: ubuntuStep)

        // When Linux CI installs dependencies
        // Then the workflow keeps the existing Swift support packages
        let requiredPackages = [
            "libcurl4-openssl-dev",
            "pkg-config",
            "python3-lldb-13",
            "libunwind-dev",
            "libgstreamer1.0-dev",
            "libgstreamer-plugins-base1.0-dev",
            "gstreamer1.0-tools",
            "gstreamer1.0-plugins-base",
            "gstreamer1.0-plugins-good",
            "gstreamer1.0-plugins-bad",
            "gstreamer1.0-plugins-ugly",
            "gstreamer1.0-libav",
        ]
        let missingPackages = requiredPackages.filter { !packageList.contains($0) }
        #expect(
            missingPackages.isEmpty,
            "Ubuntu CI dependency install is missing packages:\n\(missingPackages.joined(separator: "\n"))"
        )

        // And the workflow keeps the existing GStreamer development, tool, and plugin packages
        #expect(
            packageList.contains("libgstreamer1.0-dev")
                && packageList.contains("libgstreamer-plugins-base1.0-dev")
                && packageList.contains("gstreamer1.0-tools")
                && packageList.contains("gstreamer1.0-plugins-base")
                && packageList.contains("gstreamer1.0-plugins-good")
                && packageList.contains("gstreamer1.0-plugins-bad")
                && packageList.contains("gstreamer1.0-plugins-ugly")
                && packageList.contains("gstreamer1.0-libav")
        )
    }

    @Test("macOS dependency setup is unaffected")
    func macOSDependencySetupIsUnaffected() throws {
        // Given macOS CI installs GStreamer through Homebrew
        let workflow = try Self.contents(of: ".github/workflows/ci.yml")
        let macOSStep = try Self.workflowStep(
            named: "Install GStreamer dependencies (macOS)",
            in: workflow
        )

        // When the Linux libunwind dependency fix is applied
        // Then the macOS dependency step still installs only the existing Homebrew packages
        #expect(macOSStep.contains("if: runner.os == 'macOS'"))
        #expect(macOSStep.contains("brew install pkgconf gstreamer"))

        // And macOS CI does not run Ubuntu libunwind conflict handling
        #expect(!macOSStep.contains("libunwind"))
        #expect(!macOSStep.contains("apt-get"))
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
                throw LinuxCIUbuntuDependencyBDDTestError.packageRootNotFound(filePath)
            }
            directory = parent
        }
    }

    private static func workflowStep(named stepName: String, in workflow: String) throws -> String {
        let marker = "- name: \(stepName)"
        guard let stepStart = workflow.range(of: marker)?.lowerBound else {
            throw LinuxCIUbuntuDependencyBDDTestError.workflowStepNotFound(stepName)
        }

        let remaining = workflow[stepStart...]
        let nextStepStart = remaining
            .range(of: "\n      - name: ", options: [], range: remaining.index(after: remaining.startIndex)..<remaining.endIndex)?
            .lowerBound ?? workflow.endIndex

        return String(workflow[stepStart..<nextStepStart])
    }

    private static func aptInstallPackageList(in step: String) throws -> String {
        guard let installStart = step.range(of: "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y") else {
            throw LinuxCIUbuntuDependencyBDDTestError.aptInstallNotFound
        }
        return String(step[installStart.lowerBound...])
    }

    private static func snippetsAppearInOrder(_ snippets: [String], in source: String) throws -> Bool {
        var searchStart = source.startIndex

        for snippet in snippets {
            guard let range = source.range(of: snippet, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }

        return true
    }
}

private enum LinuxCIUbuntuDependencyBDDTestError: Error, CustomStringConvertible {
    case packageRootNotFound(String)
    case workflowStepNotFound(String)
    case aptInstallNotFound

    var description: String {
        switch self {
        case .packageRootNotFound(let filePath):
            "Could not locate Package.swift from \(filePath)"
        case .workflowStepNotFound(let stepName):
            "Could not find workflow step named \(stepName)"
        case .aptInstallNotFound:
            "Could not find Ubuntu apt install command"
        }
    }
}
