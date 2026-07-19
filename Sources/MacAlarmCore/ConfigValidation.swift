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

        if let maxLedgerFileBytes = config.storage.maxLedgerFileBytes {
            if maxLedgerFileBytes < 1 {
                issues.append(
                    ConfigIssue(
                        message: "storage.maxLedgerFileBytes must be positive when set", severity: .critical))
            } else if maxLedgerFileBytes < 1_048_576 {
                issues.append(
                    ConfigIssue(
                        message: "storage.maxLedgerFileBytes below 1 MB will rotate the ledger very frequently"))
            }
        }

        if config.hashAnchor.enabled {
            if config.hashAnchor.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    ConfigIssue(message: "hashAnchor is enabled with an empty directory", severity: .critical))
            }

            if config.hashAnchor.anchorEveryHeartbeats < 1 {
                issues.append(
                    ConfigIssue(
                        message:
                            "hashAnchor.anchorEveryHeartbeats is below 1; heartbeat anchoring is disabled"))
            }
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

        issues.append(contentsOf: sandboxIssues(config))

        return ConfigValidation(isValid: !issues.contains { $0.severity >= .critical }, issues: issues)
    }

    /// Warnings for capabilities that the running process cannot honor under the
    /// App Sandbox. These mirror the runtime attributed-failure behaviors (Part
    /// D) so a sandboxed misconfiguration is visible at validate time, not only
    /// after the feature silently fails.
    private static func sandboxIssues(_ config: MacAlarmConfig) -> [ConfigIssue] {
        guard SandboxEnvironment.isSandboxed else {
            return []
        }

        var issues = [ConfigIssue]()

        if config.unifiedLog.enabled {
            let systemTemplates = config.unifiedLog.queries.filter { $0.scope == .system }.map(\.name)
            if !systemTemplates.isEmpty {
                issues.append(
                    ConfigIssue(
                        message:
                            "unifiedLog templates \(systemTemplates.joined(separator: ", ")) use system scope, "
                            + SandboxEnvironment.unavailableReason("system-scope OSLogStore is denied")
                            + "; they will be skipped"
                    ))
            }
        }

        if config.notifications.appleScriptFallback {
            issues.append(
                ConfigIssue(
                    message:
                        "notifications.appleScriptFallback is "
                        + SandboxEnvironment.unavailableReason("osascript cannot be spawned")
                        + "; UserNotifications is the sandboxed channel"
                ))
        }

        if config.telegram.enabled, !ProcessEntitlements.hasNetworkClient {
            issues.append(
                ConfigIssue(
                    message:
                        "telegram is enabled but "
                        + SandboxEnvironment.unavailableReason(
                            "the com.apple.security.network.client entitlement is missing")
                ))
        }

        for watchedPath in config.filesystem.watchedPaths {
            let expanded = PathResolver.expandedPath(watchedPath.path)
            guard !MacAlarmSharedContainer.isInsideContainer(expanded) else {
                continue
            }
            let detail =
                "filesystem.watchedPaths '\(watchedPath.label)' is outside the App Group container and "
                + SandboxEnvironment.unavailableReason("the sandboxed agent cannot watch it")
            // A required out-of-container path is a critical misconfiguration; an
            // optional one is a warning. User-selected folders are watched by the
            // app's WatchService, not the agent (Part E2).
            issues.append(ConfigIssue(message: detail, severity: watchedPath.required ? .critical : .warning))
        }

        return issues
    }
}
