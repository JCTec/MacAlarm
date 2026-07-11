import Foundation
import MacAlarmCore

struct TimelineLedgerSnapshot: Sendable {
    var recordSet: TimelineRecordSet
    var continuity: LedgerVerification

    var records: [TimelineRecord] {
        recordSet.records
    }

    var recordIndex: TimelineRecordIndex {
        recordSet.index
    }
}

enum TimelineLedgerLoader {
    static func load(from ledgerURL: URL) throws -> TimelineLedgerSnapshot {
        let decoded = try readRecords(from: ledgerURL)
        let timelineRecords = decoded.enumerated().map { index, record in
            TimelineRecord(index: index, record: record, category: TimelineCategory.category(for: record.event))
        }

        return TimelineLedgerSnapshot(
            recordSet: TimelineRecordSet(records: timelineRecords),
            continuity: checkContinuity(records: decoded)
        )
    }

    private static func readRecords(from ledgerURL: URL) throws -> [LedgerRecord] {
        let data = try LedgerFileReader.readDataWithSharedLock(fileURL: ledgerURL)
        guard let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        return
            try contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decoder.decode(LedgerRecord.self, from: Data($0.utf8)) }
    }

    private static func checkContinuity(records: [LedgerRecord]) -> LedgerVerification {
        var expectedPreviousHash = HashChainLedger.zeroHash
        var issues = [String]()
        var lastHash = HashChainLedger.zeroHash

        for (index, record) in records.enumerated() {
            if record.previousHash != expectedPreviousHash {
                issues.append("Line \(index + 1): previous hash mismatch")
            }
            expectedPreviousHash = record.hash
            lastHash = record.hash
        }

        return LedgerVerification(
            isValid: issues.isEmpty, recordCount: records.count, lastHash: lastHash, issues: issues)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
