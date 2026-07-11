import Foundation

public enum AgentFactory {
    public static func hmacKey(for config: MacAlarmConfig, secretStore: any SecretStore) throws -> Data {
        if let key = try secretStore.readSecret(account: config.secrets.hmacKeyAccount) {
            return key
        }

        if config.secrets.allowDevelopmentFallbackKey {
            return SecretMaterial.developmentHMACKey(identity: config.identity)
        }

        throw MacAlarmError.missingHMACKey(account: config.secrets.hmacKeyAccount)
    }

    public static func hmacKeyOffMain(for config: MacAlarmConfig, secretStore: any SecretStore) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try hmacKey(for: config, secretStore: secretStore)
        }.value
    }

    @discardableResult
    public static func ensureHMACKey(for config: MacAlarmConfig, secretStore: any SecretStore) throws -> Data {
        if let key = try secretStore.readSecret(account: config.secrets.hmacKeyAccount) {
            return key
        }

        let key = try SecretMaterial.randomKey()
        try secretStore.writeSecret(key, account: config.secrets.hmacKeyAccount)
        return key
    }

    @MainActor
    public static func makeRuntime(config: MacAlarmConfig, secretStore: any SecretStore) throws -> MacAlarmAgentRuntime
    {
        let key = try hmacKey(for: config, secretStore: secretStore)
        return try MacAlarmAgentRuntime(config: config, hmacKey: key)
    }
}
