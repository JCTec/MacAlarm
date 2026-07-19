import Foundation

extension LaunchAgentManager {
    static func prepareInstall(
        paths: MacAlarmInstallationPaths,
        agentPath: String,
        configPath: String,
        createDefaultConfigIfMissing: Bool
    ) async throws -> MacAlarmConfig {
        try await Task.detached(priority: .utility) {
            // Sandboxed installs put all shared state in the App Group container.
            // Resolve it up front and fail loudly if it is unavailable, rather
            // than silently writing into a private container (the split-brain P1
            // forbids). Unsandboxed installs skip this entirely.
            if SandboxEnvironment.isSandboxed {
                _ = try MacAlarmSharedContainer.containerURL()
            }

            let agentURL = URL(fileURLWithPath: PathResolver.expandedPath(agentPath))
            let configURL = URL(fileURLWithPath: PathResolver.expandedPath(configPath))

            guard FileManager.default.isExecutableFile(atPath: agentURL.path) else {
                throw MacAlarmError.invalidConfiguration(
                    "agent executable is missing or not executable: \(agentURL.path)")
            }

            try FileManager.default.createDirectory(at: paths.installDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: paths.installDirectory.appendingPathComponent("runtime", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: paths.installDirectory.appendingPathComponent("outbox", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: paths.plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if !FileManager.default.fileExists(atPath: configURL.path) {
                guard createDefaultConfigIfMissing else {
                    throw MacAlarmError.invalidConfiguration("config is missing: \(configURL.path)")
                }
                try MacAlarmConfig.installedDefault(paths: paths).write(to: configURL)
            }

            let config = try MacAlarmConfig.load(from: configURL)
            let validation = ConfigValidator.validate(config)
            guard validation.isValid else {
                throw MacAlarmError.invalidConfiguration(
                    validation.issues.map(\.message).joined(separator: "\n")
                )
            }
            try rewriteConfigDroppingLegacyFieldsIfNeeded(config, at: configURL)
            return config
        }.value
    }

    static func requirePlistExists(_ url: URL) async throws {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MacAlarmError.invalidConfiguration("LaunchAgent plist is missing: \(url.path)")
            }
        }.value
    }

    static func writePlist(_ plist: LaunchAgentPlist, to url: URL) async throws {
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist.xmlString().write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }.value
    }

    private static func rewriteConfigDroppingLegacyFieldsIfNeeded(_ config: MacAlarmConfig, at url: URL) throws {
        let rawConfig = try Data(contentsOf: url)
        guard rawConfig.range(of: legacyInteractiveSecretFieldMarker) != nil else {
            return
        }

        try config.write(to: url)
    }

    private static let legacyInteractiveSecretFieldMarker = Data(
        [
            0x23, 0x6C, 0x66, 0x7A, 0x64, 0x69, 0x62, 0x6A, 0x6F, 0x54, 0x66, 0x73, 0x77, 0x6A, 0x64, 0x66,
            0x23,
        ].map { $0 &- 1 })
}
