import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runWatchAvailabilityTests(_ runner: TestRunner) async {
        await runner.run("sandboxed agent reports watch.unavailable for out-of-container paths") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            let containerPrevious = MacAlarmSharedContainer.overrideContainerURL
            defer {
                SandboxEnvironment.overrideIsSandboxed = sandboxPrevious
                MacAlarmSharedContainer.overrideContainerURL = containerPrevious
            }

            let base = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let container = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: base)
                try? FileManager.default.removeItem(at: container)
            }
            SandboxEnvironment.overrideIsSandboxed = true
            MacAlarmSharedContainer.overrideContainerURL = container

            let outsidePath = "/tmp/macalarm-outside-\(UUID().uuidString)"
            let config = MacAlarmConfig(
                storage: StorageConfig(
                    ledgerPath: base.appendingPathComponent("events.jsonl").path,
                    outboxDirectory: base.appendingPathComponent("outbox", isDirectory: true).path,
                    runtimeDirectory: base.appendingPathComponent("runtime", isDirectory: true).path,
                    spoolDirectory: base.appendingPathComponent("spool", isDirectory: true).path
                ),
                heartbeat: HeartbeatConfig(enabled: false),
                session: SessionConfig(enabled: false),
                filesystem: FilesystemConfig(
                    watchedPaths: [WatchedPath(path: outsidePath, label: "outside-canary", required: true)]),
                unifiedLog: UnifiedLogConfig(enabled: false),
                notifications: NotificationConfig(console: false, localNotification: false),
                hashAnchor: HashAnchorConfig(enabled: false),
                rules: []
            )

            let hmacKey = Data("unit-test-key".utf8)
            let runtime = try await MainActor.run {
                try MacAlarmAgentRuntime(config: config, hmacKey: hmacKey)
            }
            try await runtime.run(duration: 0.6)

            let ledger = try HashChainLedger(fileURL: base.appendingPathComponent("events.jsonl"), hmacKey: hmacKey)
            let records = try await ledger.readRecords()
            let unavailable = records.map(\.event).first {
                $0.source == "filesystem" && $0.name == "watch.unavailable"
            }
            let event = try require(unavailable, "agent should record a watch.unavailable event")
            try expect(event.metadata["reason"] == "app-sandbox", "reason should attribute the sandbox")
            try expect(event.metadata["label"] == "outside-canary", "event should name the watched path label")
        }

        await runner.run("config validator flags out-of-container watch paths under sandbox") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            let containerPrevious = MacAlarmSharedContainer.overrideContainerURL
            defer {
                SandboxEnvironment.overrideIsSandboxed = sandboxPrevious
                MacAlarmSharedContainer.overrideContainerURL = containerPrevious
            }

            let container = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            SandboxEnvironment.overrideIsSandboxed = true
            MacAlarmSharedContainer.overrideContainerURL = container

            let requiredOutside = MacAlarmConfig(
                filesystem: FilesystemConfig(
                    watchedPaths: [WatchedPath(path: "/tmp/outside-required", label: "req", required: true)]),
                telegram: TelegramConfig(enabled: false)
            )
            let requiredValidation = ConfigValidator.validate(requiredOutside)
            try expect(
                !requiredValidation.isValid,
                "a required out-of-container path should be a critical error under sandbox")
            try expect(
                requiredValidation.issues.contains {
                    $0.severity >= .critical && $0.message.contains("outside the App Group container")
                },
                "critical issue should name the container boundary")

            let optionalOutside = MacAlarmConfig(
                filesystem: FilesystemConfig(
                    watchedPaths: [WatchedPath(path: "/tmp/outside-optional", label: "opt", required: false)])
            )
            let optionalValidation = ConfigValidator.validate(optionalOutside)
            try expect(
                optionalValidation.issues.contains {
                    $0.severity < .critical && $0.message.contains("outside the App Group container")
                },
                "an optional out-of-container path should be a warning")

            let insidePath = container.appendingPathComponent("watched", isDirectory: true).path
            let insideConfig = MacAlarmConfig(
                filesystem: FilesystemConfig(
                    watchedPaths: [WatchedPath(path: insidePath, label: "inside", required: true)])
            )
            let insideValidation = ConfigValidator.validate(insideConfig)
            try expect(
                !insideValidation.issues.contains { $0.message.contains("outside the App Group container") },
                "a container-relative path should not be flagged")
        }
    }
}
