import Foundation
import MacAlarmCore

public struct DoctorCommand {
    private let arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }

    public func run() async throws -> Never {
        let report = await buildReport()

        if arguments.contains("--json") {
            print(DoctorReportRenderer.jsonString(report))
        } else {
            print(DoctorReportRenderer.humanReport(report))
        }

        Foundation.exit(report.healthy ? 0 : 3)
    }

    private func buildReport() async -> DoctorReport {
        let paths = MacAlarmInstallationPaths()
        let configURL = URL(fileURLWithPath: optionValue("--config") ?? paths.configURL.path)
        let checkedAt = Date()
        var checks = [DoctorCheck]()

        let fileSnapshot = await FileSnapshot.capture(paths: paths, configURL: configURL)
        checks.append(fileSnapshot.check(name: "agent binary", file: \.agentBinary, required: true))
        checks.append(fileSnapshot.check(name: "control tool", file: \.controlBinary, required: true))
        checks.append(fileSnapshot.check(name: "config file", file: \.configFile, required: true))
        checks.append(fileSnapshot.check(name: "legacy launch agent plist", file: \.plistFile, required: false))
        checks.append(fileSnapshot.check(name: "log directory", file: \.logDirectory, required: false))

        let configResult = await loadConfig(from: configURL)
        var config: MacAlarmConfig?
        switch configResult {
        case .success(let loaded):
            config = loaded
            let validation = ConfigValidator.validate(loaded)
            let criticalIssues = validation.issues.filter { $0.severity >= .critical }
            if validation.isValid {
                checks.append(.pass("config validation", "config schema and rules are valid", required: true))
            } else {
                checks.append(
                    .fail(
                        "config validation",
                        criticalIssues.map(\.message).joined(separator: "; "),
                        required: true
                    )
                )
            }
            for issue in validation.issues where issue.severity < .critical {
                checks.append(.warning("config warning", issue.message, required: false))
            }
        case .failure(let error):
            checks.append(.fail("config load", String(describing: error), required: true))
        }

        let launchctl = await ProcessExecution.run(
            executable: "/bin/launchctl",
            arguments: ["print", paths.launchAgentService]
        )
        checks.append(
            launchctl.terminationStatus == 0
                ? .pass("launch agent", "\(paths.launchAgentService) is visible to launchctl", required: true)
                : .fail("launch agent", launchctl.summary, required: true)
        )

        let notification = await notificationSnapshot(config: config)
        checks.append(.pass("notification status", notification.authorizationStatus))

        var ledger: LedgerDoctorSnapshot?
        if let config {
            let ledgerResult = await verifyLedger(config: config)
            switch ledgerResult {
            case .success(let snapshot):
                ledger = snapshot
                if snapshot.verification.isValid {
                    checks.append(
                        .pass(
                            "ledger hash chain",
                            "\(snapshot.verification.recordCount) verified record(s)",
                            required: true
                        )
                    )
                    if snapshot.verification.recordCount == 0 {
                        checks.append(
                            .warning(
                                "ledger activity",
                                "ledger is valid but empty; recorder has not written an event yet",
                                required: false
                            )
                        )
                    } else if let staleMessage = DoctorLedgerFreshness.staleMessage(
                        snapshot: snapshot, config: config)
                    {
                        checks.append(.warning("ledger freshness", staleMessage, required: false))
                    }
                } else {
                    checks.append(
                        .fail(
                            "ledger hash chain",
                            snapshot.verification.issues.joined(separator: "; "),
                            required: true
                        )
                    )
                }
            case .failure(let error):
                checks.append(.fail("ledger hash chain", String(describing: error), required: true))
            }
        }

        return DoctorReport(
            checkedAt: checkedAt,
            healthy: !checks.contains { $0.required && $0.status == .fail },
            paths: paths,
            configPath: configURL.path,
            ledgerPath: config.map { PathResolver.fileURL($0.storage.ledgerPath).path } ?? paths.defaultLedgerURL.path,
            checks: checks,
            launchctl: launchctl,
            notification: notification,
            ledger: ledger
        )
    }

    private func optionValue(_ option: String) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private func loadConfig(from url: URL) async -> Result<MacAlarmConfig, ErrorDescription> {
        await Task.detached(priority: .utility) {
            do {
                return .success(try MacAlarmConfig.load(from: url))
            } catch {
                return .failure(ErrorDescription(error))
            }
        }.value
    }

    private func verifyLedger(config: MacAlarmConfig) async -> Result<LedgerDoctorSnapshot, ErrorDescription> {
        await Task.detached(priority: .userInitiated) {
            do {
                let secretStore = FileSecretStore.installedStore(for: config)
                let hmacKey = try AgentFactory.hmacKey(for: config, secretStore: secretStore)
                let ledgerURL = PathResolver.fileURL(config.storage.ledgerPath)
                let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: hmacKey)
                let verification = try await ledger.verify()
                let records = try await ledger.readRecords()
                return .success(
                    LedgerDoctorSnapshot(
                        path: ledgerURL.path,
                        verification: verification,
                        latestEventAt: records.last?.event.observedAt,
                        latestEventName: records.last.map { "\($0.event.source).\($0.event.name)" }
                    )
                )
            } catch {
                return .failure(ErrorDescription(error))
            }
        }.value
    }

    private func notificationSnapshot(config: MacAlarmConfig?) async -> NotificationAuthorizationSnapshot {
        let notifier = ResilientLocalNotifier(
            soundEnabled: config?.notifications.sound ?? true,
            useAppleScriptFallback: config?.notifications.appleScriptFallback ?? true
        )
        return await notifier.authorizationSnapshot()
    }
}
