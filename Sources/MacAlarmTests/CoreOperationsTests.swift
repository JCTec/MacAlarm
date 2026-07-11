import Foundation
import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

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

        await runner.run("ledger hash anchor sink writes latest anchor and append-only history") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let sink = FileLedgerHashAnchorSink(directory: directory)
            let first = LedgerHashAnchor(
                deviceID: "device",
                ledgerPath: "/tmp/events.jsonl",
                recordCount: 1,
                lastHash: String(repeating: "a", count: 64),
                isLedgerValid: true,
                reason: "unit-test"
            )
            let second = LedgerHashAnchor(
                deviceID: "device",
                ledgerPath: "/tmp/events.jsonl",
                recordCount: 2,
                lastHash: String(repeating: "b", count: 64),
                isLedgerValid: true,
                reason: "heartbeat"
            )

            try await sink.write(first)
            try await sink.write(second)

            let latest = try require(
                FileLedgerHashAnchorSink.readLatest(directory: directory), "latest anchor should decode")
            try expect(latest.lastHash == second.lastHash, "latest anchor should reflect the newest write")
            try expect(latest.recordCount == 2, "latest anchor should carry the newest record count")

            let latestURL = directory.appendingPathComponent(FileLedgerHashAnchorSink.latestFileName)
            try expect(latestURL.fileMode == Int(S_IRUSR | S_IWUSR), "latest anchor should be mode 0600")

            let historyURL = directory.appendingPathComponent(FileLedgerHashAnchorSink.historyFileName)
            let history = try String(contentsOf: historyURL, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: true)
            try expect(history.count == 2, "history should keep every anchor write")
        }

        await runner.run("ledger anchor comparison detects truncation and rewrite") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: Data("unit-test-key".utf8))
            try await ledger.append(AlarmEvent(source: "test", name: "one"))
            try await ledger.append(AlarmEvent(source: "test", name: "two"))
            try await ledger.append(AlarmEvent(source: "test", name: "three"))

            let records = try await ledger.readRecords()
            let anchor = LedgerHashAnchor(
                deviceID: "device",
                ledgerPath: ledgerURL.path,
                recordCount: records.count,
                lastHash: records[records.count - 1].hash,
                isLedgerValid: true,
                reason: "unit-test"
            )

            let intact = LedgerAnchorComparison.compare(records: records, anchor: anchor)
            try expect(intact.matches, "untouched ledger should match its anchor")

            let truncated = LedgerAnchorComparison.compare(records: Array(records.dropLast()), anchor: anchor)
            try expect(!truncated.matches, "truncated ledger should not match its anchor")
            try expect(
                truncated.issues.first?.contains("deleted") == true,
                "truncation issue should mention deleted records"
            )

            var rewritten = records
            rewritten[records.count - 1].hash = String(repeating: "f", count: 64)
            let mismatch = LedgerAnchorComparison.compare(records: rewritten, anchor: anchor)
            try expect(!mismatch.matches, "rewritten chain head should not match its anchor")
            try expect(
                mismatch.issues.first?.contains("rewritten") == true,
                "rewrite issue should mention a rewritten chain"
            )
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
