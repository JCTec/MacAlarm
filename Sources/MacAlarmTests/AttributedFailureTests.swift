import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runAttributedFailureTests(_ runner: TestRunner) async {
        await runner.run("config validator adds no sandbox warnings when unsandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = false

            let config = MacAlarmConfig(
                unifiedLog: UnifiedLogConfig(enabled: true),
                notifications: NotificationConfig(appleScriptFallback: true)
            )
            let validation = ConfigValidator.validate(config)
            try expect(
                !validation.issues.contains { $0.message.contains(SandboxEnvironment.unavailablePrefix) },
                "no sandbox-attributed warnings should appear when unsandboxed")
        }

        await runner.run("config validator warns for system-scope unified log under sandbox") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = true

            // Default UnifiedLogConfig includes a system-scope template.
            let config = MacAlarmConfig(unifiedLog: UnifiedLogConfig(enabled: true))
            let validation = ConfigValidator.validate(config)
            try expect(
                validation.issues.contains {
                    $0.message.contains("system scope") && $0.message.contains(SandboxEnvironment.unavailablePrefix)
                },
                "sandboxed system-scope template should raise an attributed warning")
        }

        await runner.run("config validator warns for AppleScript fallback under sandbox") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = true

            let config = MacAlarmConfig(notifications: NotificationConfig(appleScriptFallback: true))
            let validation = ConfigValidator.validate(config)
            try expect(
                validation.issues.contains {
                    $0.message.contains("appleScriptFallback")
                        && $0.message.contains(SandboxEnvironment.unavailablePrefix)
                },
                "sandboxed AppleScript fallback should raise an attributed warning")
        }

        await runner.run("config validator warns for Telegram without network entitlement under sandbox") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            let networkPrevious = ProcessEntitlements.overrideNetworkClient
            defer {
                SandboxEnvironment.overrideIsSandboxed = sandboxPrevious
                ProcessEntitlements.overrideNetworkClient = networkPrevious
            }
            SandboxEnvironment.overrideIsSandboxed = true
            ProcessEntitlements.overrideNetworkClient = false

            let config = MacAlarmConfig(
                notifications: NotificationConfig(appleScriptFallback: false),
                telegram: TelegramConfig(enabled: true, approvedChatIDs: [1])
            )
            let validation = ConfigValidator.validate(config)
            try expect(
                validation.issues.contains {
                    $0.message.contains("telegram") && $0.message.contains("network.client")
                },
                "sandboxed Telegram without network.client should raise an attributed warning")

            ProcessEntitlements.overrideNetworkClient = true
            let allowed = ConfigValidator.validate(config)
            try expect(
                !allowed.issues.contains { $0.message.contains("network.client") },
                "no network warning when the entitlement is present")
        }

        await runner.run("AppleScript notifier fails with the uniform reason under sandbox") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = true

            let notifier = AppleScriptNotificationNotifier(soundEnabled: false)
            let delivery = try await notifier.send(sampleAlarm())
            try expect(!delivery.succeeded, "sandboxed AppleScript delivery should not succeed")
            try expect(
                delivery.detail.hasPrefix(SandboxEnvironment.unavailablePrefix),
                "delivery detail should carry the uniform sandbox reason, got: \(delivery.detail)")
        }

        await runner.run("Telegram notifier fails with the uniform reason under sandbox without network") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            let networkPrevious = ProcessEntitlements.overrideNetworkClient
            defer {
                SandboxEnvironment.overrideIsSandboxed = sandboxPrevious
                ProcessEntitlements.overrideNetworkClient = networkPrevious
            }
            SandboxEnvironment.overrideIsSandboxed = true
            ProcessEntitlements.overrideNetworkClient = false

            let notifier = TelegramNotifier(
                client: TelegramClient(token: "test-token"),
                config: TelegramConfig(enabled: true, approvedChatIDs: [1])
            )
            let delivery = try await notifier.send(sampleAlarm())
            try expect(!delivery.succeeded, "sandboxed Telegram without network should not succeed")
            try expect(
                delivery.detail.hasPrefix(SandboxEnvironment.unavailablePrefix),
                "delivery detail should carry the uniform sandbox reason, got: \(delivery.detail)")
        }
    }

    private static func sampleAlarm() -> Alarm {
        Alarm(
            ruleID: "test-rule",
            severity: .warning,
            message: "test alarm",
            event: AlarmEvent(source: "test", name: "test.event", severity: .warning)
        )
    }
}
