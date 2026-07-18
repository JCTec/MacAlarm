import CryptoKit
import Foundation

public struct LedgerProofBundle: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var ledgerPath: String
    public var proofDirectoryPath: String
    public var eventsPath: String
    public var verificationPath: String
    public var summaryPath: String
    public var lastHashPath: String
    public var verification: LedgerVerification
    public var firstEventAt: Date?
    public var lastEventAt: Date?

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        ledgerPath: String,
        proofDirectoryPath: String,
        eventsPath: String,
        verificationPath: String,
        summaryPath: String,
        lastHashPath: String,
        verification: LedgerVerification,
        firstEventAt: Date?,
        lastEventAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.ledgerPath = ledgerPath
        self.proofDirectoryPath = proofDirectoryPath
        self.eventsPath = eventsPath
        self.verificationPath = verificationPath
        self.summaryPath = summaryPath
        self.lastHashPath = lastHashPath
        self.verification = verification
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
    }
}

public struct LedgerIntegritySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var checkedAt: Date
    public var ledgerPath: String
    public var verification: LedgerVerification
    public var firstEventAt: Date?
    public var lastEventAt: Date?

    public init(
        schemaVersion: Int = 1,
        checkedAt: Date,
        ledgerPath: String,
        verification: LedgerVerification,
        firstEventAt: Date?,
        lastEventAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.checkedAt = checkedAt
        self.ledgerPath = ledgerPath
        self.verification = verification
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
    }
}

public struct LedgerProofExporter {
    private let ledgerURL: URL
    private let hmacKey: Data

    public init(ledgerURL: URL, hmacKey: Data) throws {
        guard !hmacKey.isEmpty else {
            throw MacAlarmError.emptyHMACKey
        }

        self.ledgerURL = ledgerURL
        self.hmacKey = hmacKey
    }

    @discardableResult
    public func exportProofBundle(to destinationURL: URL, exportedAt: Date = .now) throws -> LedgerProofBundle {
        let ledgerData = try readLedgerData()
        let records = try decodeRecords(from: ledgerData)
        let verification = try verify(records: records)
        let bundle = LedgerProofBundle(
            exportedAt: exportedAt,
            ledgerPath: ledgerURL.path,
            proofDirectoryPath: destinationURL.path,
            eventsPath: destinationURL.appendingPathComponent("events.jsonl").path,
            verificationPath: destinationURL.appendingPathComponent("verification.json").path,
            summaryPath: destinationURL.appendingPathComponent("summary.txt").path,
            lastHashPath: destinationURL.appendingPathComponent("last-hash.txt").path,
            verification: verification,
            firstEventAt: records.first?.event.observedAt,
            lastEventAt: records.last?.event.observedAt
        )

        try write(bundle: bundle, ledgerData: ledgerData, to: destinationURL)
        MacAlarmLog.ledger.info(
            """
            Proof bundle exported: \(verification.recordCount, privacy: .public) record(s), \
            valid=\(verification.isValid, privacy: .public)
            """)
        return bundle
    }

    public func inspectLedger(checkedAt: Date = .now) throws -> LedgerIntegritySnapshot {
        let ledgerData = try readLedgerData()
        let records = try decodeRecords(from: ledgerData)
        return LedgerIntegritySnapshot(
            checkedAt: checkedAt,
            ledgerPath: ledgerURL.path,
            verification: try verify(records: records),
            firstEventAt: records.first?.event.observedAt,
            lastEventAt: records.last?.event.observedAt
        )
    }

    private func readLedgerData() throws -> Data {
        try LedgerFileLock.readDataWithSharedLock(fileURL: ledgerURL)
    }

    private func decodeRecords(from data: Data) throws -> [LedgerRecord] {
        guard !data.isEmpty, let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        return
            try contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try CanonicalJSON.decoder.decode(LedgerRecord.self, from: Data($0.utf8)) }
    }

    private func verify(records: [LedgerRecord]) throws -> LedgerVerification {
        var expectedPreviousHash = HashChainLedger.zeroHash
        var issues = [String]()
        var lastHash = HashChainLedger.zeroHash

        for (index, record) in records.enumerated() {
            let line = index + 1
            if record.previousHash != expectedPreviousHash {
                issues.append(MacAlarmError.ledgerPreviousHashMismatch(line: line).localizedDescription)
            }

            let recomputedHash = try computeHash(event: record.event, previousHash: record.previousHash)
            if record.hash != recomputedHash {
                issues.append(MacAlarmError.ledgerRecordHashMismatch(line: line).localizedDescription)
            }

            expectedPreviousHash = record.hash
            lastHash = record.hash
        }

        return LedgerVerification(
            isValid: issues.isEmpty,
            recordCount: records.count,
            lastHash: lastHash,
            issues: issues
        )
    }

    private func write(bundle: LedgerProofBundle, ledgerData: Data, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destinationURL.path)

        try writeProtected(ledgerData, to: destinationURL.appendingPathComponent("events.jsonl"))
        try writeProtected(
            try Self.makeEncoder().encode(bundle), to: destinationURL.appendingPathComponent("verification.json"))
        try writeProtected(
            Data(summary(for: bundle).utf8),
            to: destinationURL.appendingPathComponent("summary.txt")
        )
        try writeProtected(
            Data((bundle.verification.lastHash + "\n").utf8),
            to: destinationURL.appendingPathComponent("last-hash.txt")
        )
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func summary(for bundle: LedgerProofBundle) -> String {
        let firstEvent = bundle.firstEventAt.map(Self.dateString) ?? "none"
        let lastEvent = bundle.lastEventAt.map(Self.dateString) ?? "none"
        return """
            MacAlarm Ledger Proof
            Exported: \(Self.dateString(bundle.exportedAt))
            Ledger: \(bundle.ledgerPath)
            Valid: \(bundle.verification.isValid)
            Records: \(bundle.verification.recordCount)
            First event: \(firstEvent)
            Last event: \(lastEvent)
            Last hash: \(bundle.verification.lastHash)
            Issues: \(bundle.verification.issues.count)

            \(bundle.verification.issues.joined(separator: "\n"))
            """
    }

    private func computeHash(event: AlarmEvent, previousHash: String) throws -> String {
        let payload = LedgerRecordPayload(event: event, previousHash: previousHash)
        let data = try CanonicalJSON.encode(payload)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: hmacKey))
        return Data(authenticationCode).hexEncodedString
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct LedgerRecordPayload: Codable {
    var event: AlarmEvent
    var previousHash: String
}
