import CryptoKit
import Foundation

public struct LedgerRecord: Codable, Equatable, Sendable {
    public var event: AlarmEvent
    public var previousHash: String
    public var hash: String

    public init(event: AlarmEvent, previousHash: String, hash: String) {
        self.event = event
        self.previousHash = previousHash
        self.hash = hash
    }
}

private struct LedgerRecordPayload: Codable {
    var event: AlarmEvent
    var previousHash: String
}

public struct LedgerVerification: Codable, Equatable, Sendable {
    public var isValid: Bool
    public var recordCount: Int
    public var lastHash: String
    public var issues: [String]

    public init(isValid: Bool, recordCount: Int, lastHash: String, issues: [String]) {
        self.isValid = isValid
        self.recordCount = recordCount
        self.lastHash = lastHash
        self.issues = issues
    }
}

public actor HashChainLedger {
    public static let zeroHash = String(repeating: "0", count: 64)

    private let fileURL: URL
    private let hmacKey: Data
    private let fileManager: LedgerFileManager
    private var ioTail: Task<Void, Never>?
    private var ioTailID = 0

    public init(fileURL: URL, hmacKey: Data, fileManager: FileManager = .default) throws {
        guard !hmacKey.isEmpty else {
            throw MacAlarmError.emptyHMACKey
        }

        self.fileURL = fileURL
        self.hmacKey = hmacKey
        self.fileManager = LedgerFileManager(fileManager)
    }

    @discardableResult
    public func append(_ event: AlarmEvent) async throws -> LedgerRecord {
        let fileURL = fileURL
        let hmacKey = hmacKey
        let fileManager = fileManager
        return try await runSerializedIO {
            try Self.append(event, fileURL: fileURL, hmacKey: hmacKey, fileManager: fileManager)
        }
    }

    public func verify() async throws -> LedgerVerification {
        let fileURL = fileURL
        let hmacKey = hmacKey
        let fileManager = fileManager
        return try await runSerializedIO {
            try Self.verify(fileURL: fileURL, hmacKey: hmacKey, fileManager: fileManager)
        }
    }

    public func readRecords() async throws -> [LedgerRecord] {
        let fileURL = fileURL
        let fileManager = fileManager
        return try await runSerializedIO {
            try Self.readRecords(fileURL: fileURL, fileManager: fileManager)
        }
    }

    public func lastHash() async throws -> String {
        let fileURL = fileURL
        let fileManager = fileManager
        return try await runSerializedIO {
            try Self.lastHash(fileURL: fileURL, fileManager: fileManager)
        }
    }

    private func runSerializedIO<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let previous = ioTail
        ioTailID += 1
        let operationID = ioTailID
        let task = Task.detached(priority: .utility) {
            await previous?.value
            return try operation()
        }
        ioTail = Task.detached(priority: .utility) {
            _ = try? await task.value
        }

        do {
            let value = try await task.value
            clearCompletedIO(operationID)
            return value
        } catch {
            clearCompletedIO(operationID)
            throw error
        }
    }

    private func clearCompletedIO(_ operationID: Int) {
        if ioTailID == operationID {
            ioTail = nil
        }
    }

    private static func append(
        _ event: AlarmEvent,
        fileURL: URL,
        hmacKey: Data,
        fileManager: LedgerFileManager
    ) throws -> LedgerRecord {
        try ensureParentDirectory(fileURL: fileURL, fileManager: fileManager)

        if !fileManager.value.fileExists(atPath: fileURL.path) {
            fileManager.value.createFile(atPath: fileURL.path, contents: nil)
            chmod(fileURL.path, S_IRUSR | S_IWUSR)
        }

        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }

        return try LedgerFileLock.withExclusiveLock(handle) {
            let previousHash = try lastHashUnlocked(fileURL: fileURL, fileManager: fileManager)
            let hash = try computeHash(event: event, previousHash: previousHash, hmacKey: hmacKey)
            let record = LedgerRecord(event: event, previousHash: previousHash, hash: hash)
            let line = try CanonicalJSON.encodeLine(record)

            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            return record
        }
    }

    private static func verify(fileURL: URL, hmacKey: Data, fileManager: LedgerFileManager) throws
        -> LedgerVerification
    {
        var expectedPreviousHash = Self.zeroHash
        var issues = [String]()
        var count = 0
        var lastHash = Self.zeroHash

        for (lineNumber, record) in try readRecords(fileURL: fileURL, fileManager: fileManager).enumerated() {
            let line = lineNumber + 1

            if record.previousHash != expectedPreviousHash {
                issues.append(MacAlarmError.ledgerPreviousHashMismatch(line: line).localizedDescription)
            }

            let recomputedHash = try computeHash(
                event: record.event, previousHash: record.previousHash, hmacKey: hmacKey)
            if record.hash != recomputedHash {
                issues.append(MacAlarmError.ledgerRecordHashMismatch(line: line).localizedDescription)
            }

            expectedPreviousHash = record.hash
            lastHash = record.hash
            count += 1
        }

        return LedgerVerification(
            isValid: issues.isEmpty,
            recordCount: count,
            lastHash: lastHash,
            issues: issues
        )
    }

    private static func readRecords(fileURL: URL, fileManager: LedgerFileManager) throws -> [LedgerRecord] {
        let data = try LedgerFileLock.readDataWithSharedLock(fileURL: fileURL, fileManager: fileManager.value)
        return try decodeRecords(from: data)
    }

    private static func readRecordsUnlocked(fileURL: URL, fileManager: LedgerFileManager) throws -> [LedgerRecord] {
        guard fileManager.value.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decodeRecords(from: data)
    }

    private static func decodeRecords(from data: Data) throws -> [LedgerRecord] {
        guard !data.isEmpty, let contents = String(data: data, encoding: .utf8) else {
            return []
        }

        return
            try contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                try CanonicalJSON.decoder.decode(LedgerRecord.self, from: Data(line.utf8))
            }
    }

    private static func lastHash(fileURL: URL, fileManager: LedgerFileManager) throws -> String {
        try readRecords(fileURL: fileURL, fileManager: fileManager).last?.hash ?? Self.zeroHash
    }

    private static func lastHashUnlocked(fileURL: URL, fileManager: LedgerFileManager) throws -> String {
        try readRecordsUnlocked(fileURL: fileURL, fileManager: fileManager).last?.hash ?? Self.zeroHash
    }

    private static func ensureParentDirectory(fileURL: URL, fileManager: LedgerFileManager) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.value.createDirectory(at: parent, withIntermediateDirectories: true)
    }

    private static func computeHash(event: AlarmEvent, previousHash: String, hmacKey: Data) throws -> String {
        let payload = LedgerRecordPayload(event: event, previousHash: previousHash)
        let data = try CanonicalJSON.encode(payload)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: hmacKey))
        return Data(authenticationCode).hexEncodedString
    }

}

private struct LedgerFileManager: @unchecked Sendable {
    var value: FileManager

    init(_ value: FileManager) {
        self.value = value
    }
}
