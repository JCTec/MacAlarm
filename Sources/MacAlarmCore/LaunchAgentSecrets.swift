import Foundation

extension LaunchAgentManager {
    public static func ensureInstalledSecretIfMissing(config: MacAlarmConfig) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try AgentFactory.ensureHMACKey(
                for: config,
                secretStore: FileSecretStore.installedStore(for: config)
            )
        }.value
    }
    static func disableDevelopmentFallbackIfNeeded(config: MacAlarmConfig, configPath: String) async throws {
        guard config.secrets.allowDevelopmentFallbackKey else {
            return
        }

        try await Task.detached(priority: .utility) {
            var hardened = config
            hardened.secrets.allowDevelopmentFallbackKey = false
            try hardened.write(to: URL(fileURLWithPath: PathResolver.expandedPath(configPath)))
        }.value
    }
}
