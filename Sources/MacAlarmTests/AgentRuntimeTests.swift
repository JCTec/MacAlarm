import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runAgentRuntimeTests(_ runner: TestRunner) async {
        await runner.run("agent bounded run records heartbeat and checkpoint outbox") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let outboxURL = directory.appendingPathComponent("outbox", isDirectory: true)
            let runtimeURL = directory.appendingPathComponent("runtime", isDirectory: true)
            let anchorURL = directory.appendingPathComponent("anchors", isDirectory: true)
            let config = MacAlarmConfig(
                storage: StorageConfig(
                    ledgerPath: ledgerURL.path,
                    outboxDirectory: outboxURL.path,
                    runtimeDirectory: runtimeURL.path
                ),
                heartbeat: HeartbeatConfig(enabled: true, intervalSeconds: 0.2, checkpointEveryHeartbeats: 1),
                session: SessionConfig(enabled: false),
                filesystem: FilesystemConfig(watchedPaths: []),
                unifiedLog: UnifiedLogConfig(enabled: false),
                notifications: NotificationConfig(console: false, localNotification: false),
                remoteCheckpoint: RemoteCheckpointConfig(
                    enabled: true, endpointURL: "https://example.invalid/checkpoints", outboxOnly: true),
                hashAnchor: HashAnchorConfig(
                    enabled: true, directory: anchorURL.path, anchorEveryHeartbeats: 1),
                rules: []
            )
            let runtime = try await MainActor.run {
                try MacAlarmAgentRuntime(config: config, hmacKey: Data("unit-test-key".utf8))
            }

            try await runtime.run(duration: 0.65)

            let verification = try await runtime.verifyLedger()
            try expect(verification.isValid, "agent ledger should verify")
            try expect(verification.recordCount >= 3, "agent should record start, heartbeat, and stop")
            let outboxFiles = try FileManager.default.contentsOfDirectory(
                at: outboxURL, includingPropertiesForKeys: nil)
            try expect(!outboxFiles.isEmpty, "agent should enqueue checkpoints")

            let anchor = try require(
                FileLedgerHashAnchorSink.readLatest(directory: anchorURL),
                "agent should write a ledger hash anchor"
            )
            try expect(anchor.lastHash == verification.lastHash, "anchor should track the chain head")
            try expect(anchor.recordCount == verification.recordCount, "anchor should track the record count")

            let statusURL = runtimeURL.appendingPathComponent("status.json")
            let status = try AgentStatusStore.load(from: statusURL)
            try expect(status.state == .stopped, "bounded run should write stopped status")
            try expect(status.startedAt != nil, "status should include start time")
            try expect(status.stoppedAt != nil, "status should include stop time")
            try expect(status.latestHeartbeatAt != nil, "status should include latest heartbeat")
            try expect(status.heartbeatCount >= 1, "status should count heartbeats")
            try expect(status.processedEventCount >= 3, "status should count processed events")
            try expect(status.latestLedgerHash != nil, "status should include latest ledger hash")
            try expect(statusURL.fileMode == Int(S_IRUSR | S_IWUSR), "status file should be mode 0600")
        }

        await runner.run("agent status store removes ephemeral runtime status") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let statusURL = directory.appendingPathComponent("status.json")
            try Data("{}".utf8).write(to: statusURL)

            try AgentStatusStore.remove(from: statusURL)
            try expect(!FileManager.default.fileExists(atPath: statusURL.path), "status file should be removed")

            try AgentStatusStore.remove(from: statusURL)
        }
    }
}
