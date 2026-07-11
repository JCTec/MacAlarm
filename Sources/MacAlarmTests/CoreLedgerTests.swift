import Foundation
import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

extension MacAlarmTests {
    static func runCoreLedgerTests(_ runner: TestRunner) async {
        await runner.run("ledger appends and verifies") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: Data("unit-test-key".utf8))

            try await ledger.append(AlarmEvent(source: "test", name: "one"))
            try await ledger.append(AlarmEvent(source: "test", name: "two"))

            let verification = try await ledger.verify()
            try expect(verification.isValid, "ledger should verify")
            try expect(verification.recordCount == 2, "ledger should contain two records")
            try expect(ledgerURL.fileMode == Int(S_IRUSR | S_IWUSR), "ledger should be mode 0600")
        }

        await runner.run("ledger serializes concurrent appends into one valid chain") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: Data("unit-test-key".utf8))
            let eventCount = 80
            let base = Date(timeIntervalSince1970: 10_000)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<eventCount {
                    group.addTask {
                        _ = try await ledger.append(
                            AlarmEvent(
                                observedAt: base.addingTimeInterval(Double(index)),
                                source: "test",
                                name: "concurrent.append",
                                metadata: ["index": "\(index)"]
                            )
                        )
                    }
                }

                try await group.waitForAll()
            }

            let verification = try await ledger.verify()
            let records = try await ledger.readRecords()
            try expect(verification.isValid, "concurrent ledger appends should verify")
            try expect(verification.recordCount == eventCount, "ledger should contain every concurrent append")
            try expect(records.count == eventCount, "read records should include every concurrent append")
            try expect(
                Set(records.map(\.event.id)).count == eventCount,
                "concurrent appends should not duplicate event records"
            )

            var previousHash = HashChainLedger.zeroHash
            for record in records {
                try expect(record.previousHash == previousHash, "each record should point at the prior hash")
                previousHash = record.hash
            }
            try expect(verification.lastHash == previousHash, "verification should expose the final chain hash")
        }

        await runner.run("ledger detects tampering") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: Data("unit-test-key".utf8))

            try await ledger.append(AlarmEvent(source: "test", name: "original"))

            var contents = try String(contentsOf: ledgerURL, encoding: .utf8)
            contents = contents.replacingOccurrences(of: "original", with: "tampered")
            try contents.write(to: ledgerURL, atomically: true, encoding: .utf8)

            let verification = try await ledger.verify()
            try expect(!verification.isValid, "tampered ledger should fail verification")
            try expect(
                verification.issues.contains { $0.contains("hash mismatch") },
                "tamper issue should mention hash mismatch")
        }

        #if canImport(Darwin)
            await runner.run("ledger proof exporter waits for external exclusive lock") {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                defer { try? FileManager.default.removeItem(at: directory) }

                let ledgerURL = directory.appendingPathComponent("events.jsonl")
                let key = Data("unit-test-key".utf8)
                let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key)
                try await ledger.append(AlarmEvent(source: "test", name: "locked-read"))

                let helper = Process()
                helper.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                helper.arguments = ["--hold-exclusive-lock", ledgerURL.path, "500000"]
                let readyPipe = Pipe()
                helper.standardOutput = readyPipe
                try helper.run()
                defer {
                    if helper.isRunning {
                        helper.terminate()
                        helper.waitUntilExit()
                    }
                }

                let readyData = readyPipe.fileHandleForReading.readData(ofLength: 6)
                try expect(
                    String(data: readyData, encoding: .utf8) == "ready\n",
                    "helper should hold lock"
                )

                let exporter = try LedgerProofExporter(ledgerURL: ledgerURL, hmacKey: key)
                let start = Date()
                let snapshot = try exporter.inspectLedger()
                let elapsed = Date().timeIntervalSince(start)

                helper.waitUntilExit()
                try expect(helper.terminationStatus == 0, "lock helper should exit cleanly")
                try expect(elapsed >= 0.25, "proof exporter should wait for the external exclusive lock")
                try expect(snapshot.verification.isValid, "locked proof read should still verify")
                try expect(snapshot.verification.recordCount == 1, "locked proof read should preserve records")
            }
        #endif

        await runner.run("ledger proof exporter writes valid proof bundle") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let proofURL = directory.appendingPathComponent("proof", isDirectory: true)
            let key = Data("unit-test-key".utf8)
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key)
            try await ledger.append(
                AlarmEvent(
                    observedAt: Date(timeIntervalSince1970: 1_000),
                    source: "test",
                    name: "one"
                )
            )
            try await ledger.append(
                AlarmEvent(
                    observedAt: Date(timeIntervalSince1970: 1_001),
                    source: "test",
                    name: "two"
                )
            )

            let exporter = try LedgerProofExporter(ledgerURL: ledgerURL, hmacKey: key)
            let snapshot = try exporter.inspectLedger(checkedAt: Date(timeIntervalSince1970: 1_999))
            let bundle = try exporter.exportProofBundle(
                to: proofURL,
                exportedAt: Date(timeIntervalSince1970: 2_000)
            )

            try expect(snapshot.verification.isValid, "integrity snapshot should verify")
            try expect(snapshot.verification.recordCount == 2, "integrity snapshot should count records")
            try expect(
                snapshot.firstEventAt == Date(timeIntervalSince1970: 1_000), "snapshot should include first event")
            try expect(snapshot.lastEventAt == Date(timeIntervalSince1970: 1_001), "snapshot should include last event")
            try expect(bundle.verification.isValid, "proof verification should be valid")
            try expect(bundle.verification.recordCount == 2, "proof should count records")
            try expect(bundle.firstEventAt == Date(timeIntervalSince1970: 1_000), "proof should include first event")
            try expect(bundle.lastEventAt == Date(timeIntervalSince1970: 1_001), "proof should include last event")
            let exportedLedgerData = try Data(contentsOf: proofURL.appendingPathComponent("events.jsonl"))
            let sourceLedgerData = try Data(contentsOf: ledgerURL)
            try expect(
                exportedLedgerData == sourceLedgerData,
                "proof should copy exact ledger bytes"
            )
            let exportedLastHash = try String(
                contentsOf: proofURL.appendingPathComponent("last-hash.txt"),
                encoding: .utf8
            )
            try expect(
                exportedLastHash == bundle.verification.lastHash + "\n",
                "last hash file should match verification"
            )
            try expect(
                proofURL.appendingPathComponent("events.jsonl").fileMode == Int(S_IRUSR | S_IWUSR),
                "proof event copy should be mode 0600"
            )
            try expect(proofURL.fileMode == 0o700, "proof directory should be mode 0700")
        }

        await runner.run("ledger proof exporter marks tampered ledger invalid") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let proofURL = directory.appendingPathComponent("proof", isDirectory: true)
            let key = Data("unit-test-key".utf8)
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key)
            try await ledger.append(AlarmEvent(source: "test", name: "original"))

            var contents = try String(contentsOf: ledgerURL, encoding: .utf8)
            contents = contents.replacingOccurrences(of: "original", with: "tampered")
            try contents.write(to: ledgerURL, atomically: true, encoding: .utf8)

            let exporter = try LedgerProofExporter(ledgerURL: ledgerURL, hmacKey: key)
            let snapshot = try exporter.inspectLedger()
            let bundle = try exporter.exportProofBundle(to: proofURL)
            let verificationJSON = try Data(contentsOf: proofURL.appendingPathComponent("verification.json"))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(LedgerProofBundle.self, from: verificationJSON)

            try expect(!snapshot.verification.isValid, "tampered snapshot should be invalid")
            try expect(!bundle.verification.isValid, "tampered proof should be invalid")
            try expect(!decoded.verification.isValid, "verification json should mark invalid")
            try expect(
                bundle.verification.issues.contains { $0.contains("hash mismatch") },
                "proof should explain hash mismatch"
            )
        }

        await runner.run("ledger rotates segments and verifies across the whole chain") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let key = Data("unit-test-key".utf8)
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key, maxFileBytes: 1)

            try await ledger.append(AlarmEvent(source: "test", name: "one"))
            try await ledger.append(AlarmEvent(source: "test", name: "two"))
            try await ledger.append(AlarmEvent(source: "test", name: "three"))

            let archives = try HashChainLedger.rotatedSegmentURLs(for: ledgerURL)
            try expect(archives.count == 2, "each over-limit append should rotate one archived segment")

            let activeRecords = try await ledger.readRecords()
            try expect(
                activeRecords.first?.event.name == "ledger.rotated",
                "rotated active segment should start with a rotation record"
            )
            try expect(
                activeRecords.first?.previousHash != HashChainLedger.zeroHash,
                "rotation record should continue the previous segment's chain"
            )

            let allRecords = try await ledger.readAllRecords()
            try expect(allRecords.count == 5, "chain should keep three events plus two rotation records")
            try expect(
                allRecords.map(\.event.name).filter { $0 != "ledger.rotated" } == ["one", "two", "three"],
                "chain should preserve event order across segments"
            )

            let verification = try await ledger.verify()
            try expect(verification.isValid, "rotated chain should verify across segments")
            try expect(verification.recordCount == 5, "verification should count records in every segment")
            try expect(
                verification.lastHash == allRecords.last?.hash,
                "verification should expose the active segment's chain head"
            )

            var previousHash = HashChainLedger.zeroHash
            for record in allRecords {
                try expect(record.previousHash == previousHash, "chain should stay linked across segments")
                previousHash = record.hash
            }
        }

        await runner.run("ledger rotation detects tampering inside an archived segment") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let key = Data("unit-test-key".utf8)
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key, maxFileBytes: 1)

            try await ledger.append(AlarmEvent(source: "test", name: "original"))
            try await ledger.append(AlarmEvent(source: "test", name: "second"))

            let archives = try HashChainLedger.rotatedSegmentURLs(for: ledgerURL)
            let archiveURL = try require(archives.first, "rotation should archive a segment")

            var contents = try String(contentsOf: archiveURL, encoding: .utf8)
            contents = contents.replacingOccurrences(of: "original", with: "tampered")
            try contents.write(to: archiveURL, atomically: true, encoding: .utf8)

            let verification = try await ledger.verify()
            try expect(!verification.isValid, "tampered archived segment should fail verification")
        }

    }
}
