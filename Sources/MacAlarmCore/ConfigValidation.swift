import Foundation

public struct ConfigIssue: Codable, Equatable, Sendable {
    public var message: String
    public var severity: AlarmSeverity

    public init(message: String, severity: AlarmSeverity = .warning) {
        self.message = message
        self.severity = severity
    }
}

public struct ConfigValidation: Codable, Equatable, Sendable {
    public var isValid: Bool
    public var issues: [ConfigIssue]
}

public enum ConfigValidator {
    public static func validate(_ config: MacAlarmConfig) -> ConfigValidation {
        var issues = [ConfigIssue]()

        if config.schemaVersion != 1 {
            issues.append(
                ConfigIssue(message: "Unsupported schemaVersion \(config.schemaVersion)", severity: .critical))
        }

        if config.heartbeat.enabled && config.heartbeat.intervalSeconds < 10 {
            issues.append(ConfigIssue(message: "heartbeat.intervalSeconds should be at least 10 seconds"))
        }

        if config.remoteCheckpoint.enabled && config.remoteCheckpoint.endpointURL == nil {
            issues.append(
                ConfigIssue(
                    message: "remoteCheckpoint is enabled without endpointURL; outbox files will still be created"))
        }

        if config.telegram.enabled {
            do {
                _ = try FileSecretStore.fileName(forAccount: config.telegram.botTokenAccount)
            } catch {
                issues.append(
                    ConfigIssue(
                        message: "telegram.botTokenAccount is not a safe secret file account: \(error)",
                        severity: .critical
                    ))
            }

            if config.telegram.approvedChatIDs.isEmpty {
                issues.append(ConfigIssue(message: "telegram is enabled without approvedChatIDs"))
            }

            if config.telegram.pollingEnabled && config.telegram.pollingIntervalSeconds < 5 {
                issues.append(ConfigIssue(message: "telegram.pollingIntervalSeconds should be at least 5 seconds"))
            }

            if !(1...100).contains(config.telegram.updateLimit) {
                issues.append(
                    ConfigIssue(message: "telegram.updateLimit must be between 1 and 100", severity: .critical))
            }
        }

        if config.secrets.allowDevelopmentFallbackKey {
            issues.append(
                ConfigIssue(
                    message:
                        "secrets.allowDevelopmentFallbackKey should be false outside local development or tests"
                ))
        }

        do {
            _ = try FileSecretStore.fileName(forAccount: config.secrets.hmacKeyAccount)
        } catch {
            issues.append(
                ConfigIssue(
                    message: "secrets.hmacKeyAccount is not a safe secret file account: \(error)",
                    severity: .critical
                ))
        }

        for watchedPath in config.filesystem.watchedPaths
        where watchedPath.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ConfigIssue(message: "filesystem.watchedPaths contains an empty path", severity: .critical))
        }

        let ruleIDs = config.rules.map(\.id)
        let duplicateRuleIDs = Set(ruleIDs.filter { id in ruleIDs.filter { $0 == id }.count > 1 })
        for id in duplicateRuleIDs {
            issues.append(ConfigIssue(message: "Duplicate rule id: \(id)", severity: .critical))
        }

        return ConfigValidation(isValid: !issues.contains { $0.severity >= .critical }, issues: issues)
    }
}
