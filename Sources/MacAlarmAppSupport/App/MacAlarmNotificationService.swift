import Foundation
import MacAlarmCore

struct MacAlarmNotificationService: Sendable {
    func authorizationSnapshot() async -> NotificationAuthorizationSnapshot {
        let notifier = await notifier()
        return await notifier.authorizationSnapshot()
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        let notifier = await notifier()
        return await notifier.requestAuthorization()
    }

    func sendTestNotification(message: String = "MacAlarm notification system is working") async throws
        -> NotificationTestResult
    {
        let context = try await diagnosticContext()
        let runner = try NotificationTestRunner(
            config: context.config,
            hmacKey: context.hmacKey
        )
        return try await runner.run(
            message: message,
            origin: "MacAlarm.app notification diagnostics",
            notifier: notifier(config: context.config)
        )
    }

    static func testAlarm(message: String) -> Alarm {
        NotificationTestRunner.testAlarm(
            message: message,
            origin: "MacAlarm.app notification diagnostics"
        )
    }

    private func notifier() async -> ResilientLocalNotifier {
        let config = await loadConfig()
        return notifier(config: config)
    }

    private func notifier(config: MacAlarmConfig) -> ResilientLocalNotifier {
        return ResilientLocalNotifier(
            soundEnabled: config.notifications.sound,
            useAppleScriptFallback: config.notifications.appleScriptFallback
        )
    }

    private func diagnosticContext() async throws -> NotificationDiagnosticContext {
        try await MacAlarmBackgroundTask.throwing(priority: .utility) {
            let config = Self.loadConfig()
            return NotificationDiagnosticContext(
                config: config,
                hmacKey: try AgentFactory.hmacKey(
                    for: config,
                    secretStore: FileSecretStore.installedStore(for: config)
                )
            )
        }
    }

    private func loadConfig() async -> MacAlarmConfig {
        await MacAlarmBackgroundTask.value(priority: .utility) {
            Self.loadConfig()
        }
    }

    private static func loadConfig() -> MacAlarmConfig {
        let paths = MacAlarmInstallationPaths()
        guard FileManager.default.fileExists(atPath: paths.configURL.path),
            let config = try? MacAlarmConfig.load(from: paths.configURL)
        else {
            return MacAlarmConfig()
        }

        return config
    }
}

private struct NotificationDiagnosticContext: Sendable {
    var config: MacAlarmConfig
    var hmacKey: Data
}
