import Foundation
import MacAlarmCore

extension MacAlarmTests {
    static func runSpoolTransportTests(_ runner: TestRunner) async {
        await runner.run("spool file preserves event id and maps to a custom event") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let payload = CustomLogEventPayload(
                name: "script.backup.finished",
                severity: .notice,
                message: "done",
                metadata: ["script": "nightly"]
            )
            let id = UUID()
            let url = try EventSpool.write(payload, id: id, to: directory)
            try expect(url.lastPathComponent == "\(id.uuidString).json", "spool file should be named by its UUID")
            try expect(url.fileMode == 0o600, "spool file should be mode 0600")

            let event = try EventSpool.event(fromFile: url)
            try expect(event.id == id, "ingested event id should equal the filename UUID")
            try expect(event.source == "custom", "spool events should have source custom")
            try expect(event.name == "script.backup.finished", "name should round-trip")
            try expect(event.metadata["script"] == "nightly", "metadata should round-trip")
            try expect(event.metadata["message"] == "done", "message should be folded into metadata")
        }

        await runner.run("agent ingests spooled events once and verifies") {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: base) }
            let spool = base.appendingPathComponent("spool", isDirectory: true)

            var ids = [UUID]()
            for index in 0..<3 {
                let payload = CustomLogEventPayload(
                    name: "producer.event.\(index)", severity: .notice, metadata: ["index": String(index)])
                let id = UUID()
                ids.append(id)
                _ = try EventSpool.write(payload, id: id, to: spool)
            }

            let hmacKey = Data("unit-test-key".utf8)
            let config = spoolTestConfig(base: base, spool: spool)
            let runtime = try await MainActor.run {
                try MacAlarmAgentRuntime(config: config, hmacKey: hmacKey)
            }
            try await runtime.run(duration: 0.8)

            let verification = try await runtime.verifyLedger()
            try expect(verification.isValid, "ledger should verify after spool ingestion")

            let ledger = try HashChainLedger(fileURL: base.appendingPathComponent("events.jsonl"), hmacKey: hmacKey)
            let records = try await ledger.readRecords()
            let customEvents = records.map(\.event).filter { $0.source == "custom" }
            try expect(
                customEvents.count == 3, "exactly the 3 spooled events should be ingested, got \(customEvents.count)")
            try expect(
                Set(customEvents.map(\.id)) == Set(ids),
                "ingested custom events should carry the produced ids")

            let remaining = EventSpool.pendingFiles(in: spool)
            try expect(remaining.isEmpty, "spool files should be deleted after successful append")
        }

        await runner.run("spool ingestor records each file once then drains") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let recorded = RecordedEvents()
            let ingestor = SpoolIngestor(directory: directory) { event in
                await recorded.append(event.id)
                return true
            }

            let first = UUID()
            let second = UUID()
            _ = try EventSpool.write(CustomLogEventPayload(name: "a"), id: first, to: directory)
            _ = try EventSpool.write(CustomLogEventPayload(name: "b"), id: second, to: directory)

            await ingestor.ingestPending()
            let afterFirst = await recorded.ids
            try expect(afterFirst.count == 2, "both files should be ingested once")
            try expect(Set(afterFirst) == Set([first, second]), "recorded ids should match filenames")
            try expect(EventSpool.pendingFiles(in: directory).isEmpty, "files should be deleted after append")

            // Second pass with the files already drained records nothing new.
            await ingestor.ingestPending()
            let afterSecond = await recorded.ids
            try expect(afterSecond.count == 2, "draining an empty spool should not re-record")
        }

        await runner.run("re-created spool file re-ingests with the preserved id") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let recorded = RecordedEvents()
            let ingestor = SpoolIngestor(directory: directory) { event in
                await recorded.append(event.id)
                return true
            }

            let id = UUID()
            let payload = CustomLogEventPayload(name: "idempotent", metadata: ["k": "v"])
            _ = try EventSpool.write(payload, id: id, to: directory)
            await ingestor.ingestPending()

            // Simulate the same event reappearing (e.g. a crash before delete):
            // the id is reconstructed from the filename, so the re-ingested event
            // is identical and downstream de-duplication stays possible.
            _ = try EventSpool.write(payload, id: id, to: directory)
            await ingestor.ingestPending()

            let ids = await recorded.ids
            try expect(ids.count == 2, "a re-created file is ingested again")
            try expect(ids[0] == id && ids[1] == id, "both ingestions preserve the same event id")
        }
    }

    private static func spoolTestConfig(base: URL, spool: URL) -> MacAlarmConfig {
        MacAlarmConfig(
            storage: StorageConfig(
                ledgerPath: base.appendingPathComponent("events.jsonl").path,
                outboxDirectory: base.appendingPathComponent("outbox", isDirectory: true).path,
                runtimeDirectory: base.appendingPathComponent("runtime", isDirectory: true).path,
                spoolDirectory: spool.path
            ),
            heartbeat: HeartbeatConfig(enabled: false),
            session: SessionConfig(enabled: false),
            filesystem: FilesystemConfig(watchedPaths: []),
            unifiedLog: UnifiedLogConfig(enabled: false),
            notifications: NotificationConfig(console: false, localNotification: false),
            hashAnchor: HashAnchorConfig(enabled: false),
            rules: []
        )
    }
}

private actor RecordedEvents {
    private(set) var ids = [UUID]()

    func append(_ id: UUID) {
        ids.append(id)
    }
}
