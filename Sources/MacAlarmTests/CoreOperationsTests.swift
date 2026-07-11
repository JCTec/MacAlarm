import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runCoreOperationsTests(_ runner: TestRunner) async {
        await runner.run("custom log event payload round-trips") {
            let payload = CustomLogEventPayload(
                name: "script.backup.finished",
                severity: .notice,
                message: "Backup finished",
                metadata: ["script": "nightly", "status": "ok"]
            )

            let line = try payload.logLine()
            let decoded = try require(CustomLogEventPayload.parseLogLine(line), "payload should decode from log line")

            try expect(line.hasPrefix(CustomLogEventPayload.prefix), "log line should include custom event prefix")
            try expect(decoded == payload, "decoded payload should match original")
        }

        await runner.run("notification test runner records delivery attempt") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let config = MacAlarmConfig(
                storage: StorageConfig(
                    ledgerPath: ledgerURL.path,
                    outboxDirectory: directory.appendingPathComponent("outbox").path,
                    runtimeDirectory: directory.appendingPathComponent("runtime").path
                ),
                notifications: NotificationConfig(console: false, localNotification: true)
            )
            let hmacKey = Data("unit-test-key".utf8)
            let runner = try NotificationTestRunner(config: config, hmacKey: hmacKey)
            let notifier = StubDiagnosticNotifier(
                delivery: NotificationDelivery(channel: "stub", succeeded: true, detail: "queued")
            )

            let result = try await runner.run(message: "hello", origin: "unit-test", notifier: notifier)

            try expect(result.delivery.succeeded, "test delivery should succeed")
            try expect(result.triggerRecord?.event.name == "notification.test", "test trigger should be recorded")
            try expect(
                result.deliveryRecord?.event.name == "delivery.succeeded",
                "test delivery should be recorded"
            )

            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: hmacKey)
            let records = try await ledger.readRecords()
            let verification = try await ledger.verify()

            try expect(verification.isValid, "notification test ledger records should verify")
            try expect(
                records.map(\.event.name) == ["notification.test", "delivery.succeeded"],
                "ledger should record test and delivery")
            try expect(
                records.last?.event.metadata["triggerEventID"] == records.first?.event.id.uuidString,
                "delivery record should point back to trigger event"
            )
        }

        await runner.run("remote checkpoint outbox writes pending POST payload") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let sink = OutboxRemoteCheckpointSink(
                directory: directory, endpointURL: "https://example.invalid/checkpoints")
            let checkpoint = RemoteCheckpoint(
                deviceID: "device",
                displayName: "Device",
                ledgerPath: "/tmp/events.jsonl",
                recordCount: 1,
                lastHash: String(repeating: "a", count: 64),
                isLedgerValid: true,
                reason: "unit-test"
            )

            try await sink.enqueue(checkpoint)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            try expect(files.count == 1, "outbox should contain one pending request")

            let data = try Data(contentsOf: files[0])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let request = try decoder.decode(PendingPOSTRequest.self, from: data)
            try expect(request.method == "POST", "request should be POST")
            try expect(request.status == "pending-send-not-implemented", "request should be pending")
            try expect(request.body.lastHash == checkpoint.lastHash, "checkpoint should be embedded")
        }

        await runner.run("telegram alarm filter respects severity rule and source") {
            let config = TelegramConfig(
                enabled: true,
                approvedChatIDs: [123],
                minimumSeverity: .warning,
                includedRuleIDs: ["screen-unlocked"],
                includedEventSources: ["session"]
            )
            let filter = TelegramAlarmFilter(config: config)
            let matching = Alarm(
                ruleID: "screen-unlocked",
                severity: .critical,
                message: "unlock",
                event: AlarmEvent(source: "session", name: "screen.unlocked", severity: .critical)
            )
            let lowSeverity = Alarm(
                ruleID: "screen-unlocked",
                severity: .notice,
                message: "notice",
                event: AlarmEvent(source: "session", name: "screen.unlocked", severity: .notice)
            )
            let wrongSource = Alarm(
                ruleID: "screen-unlocked",
                severity: .critical,
                message: "file",
                event: AlarmEvent(source: "filesystem", name: "path.changed", severity: .critical)
            )

            try expect(filter.shouldSend(matching), "matching telegram alarm should be sent")
            try expect(!filter.shouldSend(lowSeverity), "low severity alarm should be skipped")
            try expect(!filter.shouldSend(wrongSource), "wrong source alarm should be skipped")
        }

        await runner.run("telegram command processor handles help latest search and status") {
            let first = LedgerRecord(
                event: AlarmEvent(
                    observedAt: Date(timeIntervalSince1970: 1_735_689_600),
                    source: "session",
                    name: "screen.unlocked",
                    severity: .critical
                ),
                previousHash: HashChainLedger.zeroHash,
                hash: String(repeating: "1", count: 64)
            )
            let second = LedgerRecord(
                event: AlarmEvent(
                    observedAt: Date(timeIntervalSince1970: 1_735_776_000),
                    source: "filesystem",
                    name: "path.changed",
                    severity: .warning
                ),
                previousHash: first.hash,
                hash: String(repeating: "2", count: 64)
            )
            let records = [first, second]
            let config = MacAlarmConfig(identity: AgentIdentity(deviceID: "device", displayName: "Test Mac"))

            let help = TelegramCommandProcessor.response(text: "/help", records: records, config: config)
            let latest = TelegramCommandProcessor.response(text: "/latest session 2", records: records, config: config)
            let search = TelegramCommandProcessor.response(
                text: "/search 2025-01-01 2025-01-02 filesystem",
                records: records,
                config: config
            )
            let status = TelegramCommandProcessor.response(text: "/status", records: records, config: config)
            let chat = TelegramCommandProcessor.response(text: "hello", records: records, config: config)

            try expect(help.contains("/latest"), "help should list latest command")
            try expect(latest.contains("session.screen.unlocked"), "latest should filter by session")
            try expect(search.contains("filesystem.path.changed"), "search should filter date range and type")
            try expect(status.contains("Records: 2"), "status should include record count")
            try expect(chat.contains("only accepts commands"), "free text should be rejected")
        }

    }
}

private actor StubDiagnosticNotifier: NotificationDiagnosticNotifier {
    nonisolated let channel = "stub"
    private let delivery: NotificationDelivery
    private let snapshot = NotificationAuthorizationSnapshot(
        authorizationStatus: "authorized",
        alertSetting: "enabled",
        soundSetting: "enabled",
        badgeSetting: "disabled"
    )

    init(delivery: NotificationDelivery) {
        self.delivery = delivery
    }

    func authorizationSnapshot() async -> NotificationAuthorizationSnapshot {
        snapshot
    }

    func send(_ alarm: Alarm) async throws -> NotificationDelivery {
        delivery
    }
}
