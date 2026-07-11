import Foundation
import MacAlarmCore

struct FileSnapshot: Sendable {
    var agentBinary: FileProbe
    var controlBinary: FileProbe
    var configFile: FileProbe
    var plistFile: FileProbe
    var logDirectory: FileProbe

    static func capture(paths: MacAlarmInstallationPaths, configURL: URL) async -> FileSnapshot {
        await Task.detached(priority: .utility) {
            FileSnapshot(
                agentBinary: FileProbe(url: paths.agentExecutableURL, expectsExecutable: true),
                controlBinary: FileProbe(url: paths.controlExecutableURL, expectsExecutable: true),
                configFile: FileProbe(url: configURL, expectsExecutable: false),
                plistFile: FileProbe(url: paths.plistURL, expectsExecutable: false),
                logDirectory: FileProbe(url: paths.logDirectory, expectsDirectory: true)
            )
        }.value
    }

    func check(name: String, file keyPath: KeyPath<FileSnapshot, FileProbe>, required: Bool) -> DoctorCheck {
        let probe = self[keyPath: keyPath]
        if probe.exists && probe.kindMatches && probe.executableMatches {
            return .pass(name, probe.url.path, required: required)
        }

        return DoctorCheck(
            name: name,
            status: required ? .fail : .warning,
            required: required,
            message: probe.issueMessage
        )
    }
}

struct FileProbe: Sendable {
    var url: URL
    var exists: Bool
    var kindMatches: Bool
    var executableMatches: Bool
    var expectsExecutable: Bool
    var expectsDirectory: Bool

    init(url: URL, expectsExecutable: Bool = false, expectsDirectory: Bool = false) {
        self.url = url
        self.expectsExecutable = expectsExecutable
        self.expectsDirectory = expectsDirectory

        var isDirectory: ObjCBool = false
        self.exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        self.kindMatches = !expectsDirectory || isDirectory.boolValue
        self.executableMatches = !expectsExecutable || FileManager.default.isExecutableFile(atPath: url.path)
    }

    var issueMessage: String {
        if !exists {
            return "missing: \(url.path)"
        }
        if !kindMatches {
            return "wrong file type: \(url.path)"
        }
        if !executableMatches {
            return "not executable: \(url.path)"
        }
        return url.path
    }
}
