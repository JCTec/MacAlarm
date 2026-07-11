import Foundation

/// A point-in-time record of the ledger chain head, written outside the ledger
/// so truncation or rewrite of the local chain is detectable later.
public struct LedgerHashAnchor: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var deviceID: String
    public var ledgerPath: String
    public var recordCount: Int
    public var lastHash: String
    public var isLedgerValid: Bool
    public var reason: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        deviceID: String,
        ledgerPath: String,
        recordCount: Int,
        lastHash: String,
        isLedgerValid: Bool,
        reason: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.ledgerPath = ledgerPath
        self.recordCount = recordCount
        self.lastHash = lastHash
        self.isLedgerValid = isLedgerValid
        self.reason = reason
    }
}

public protocol LedgerHashAnchorSink: Sendable {
    func write(_ anchor: LedgerHashAnchor) async throws
}

/// Writes anchors into a directory that should live outside the Mac's own
/// trust domain, such as an iCloud Drive folder. `anchor-latest.json` is the
/// fast comparison surface; `anchor-history.jsonl` is append-only so a rolled
/// back "latest" file is itself detectable.
public actor FileLedgerHashAnchorSink: LedgerHashAnchorSink {
    public static let latestFileName = "anchor-latest.json"
    public static let historyFileName = "anchor-history.jsonl"

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func write(_ anchor: LedgerHashAnchor) async throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let line = try CanonicalJSON.encodeLine(anchor)

        let latestURL = directory.appendingPathComponent(Self.latestFileName)
        try line.write(to: latestURL, options: [.atomic])
        chmod(latestURL.path, S_IRUSR | S_IWUSR)

        let historyURL = directory.appendingPathComponent(Self.historyFileName)
        if !fileManager.fileExists(atPath: historyURL.path) {
            fileManager.createFile(atPath: historyURL.path, contents: nil)
            chmod(historyURL.path, S_IRUSR | S_IWUSR)
        }
        let handle = try FileHandle(forWritingTo: historyURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public static func readLatest(
        directory: URL, fileManager: FileManager = .default
    ) throws -> LedgerHashAnchor? {
        let latestURL = directory.appendingPathComponent(Self.latestFileName)
        guard fileManager.fileExists(atPath: latestURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: latestURL)
        return try CanonicalJSON.decoder.decode(LedgerHashAnchor.self, from: data)
    }
}

public struct DisabledLedgerHashAnchorSink: LedgerHashAnchorSink {
    public init() {}

    public func write(_ anchor: LedgerHashAnchor) async throws {
        _ = anchor
    }
}

/// Compares the current ledger contents against a previously written anchor.
public struct LedgerAnchorComparison: Codable, Equatable, Sendable {
    public var matches: Bool
    public var issues: [String]

    public init(matches: Bool, issues: [String]) {
        self.matches = matches
        self.issues = issues
    }

    /// The record at `anchor.recordCount - 1` must carry `anchor.lastHash`.
    /// Fewer records than the anchor saw means truncation; a different hash at
    /// that position means the chain was rewritten.
    public static func compare(records: [LedgerRecord], anchor: LedgerHashAnchor) -> LedgerAnchorComparison {
        var issues = [String]()

        if anchor.recordCount <= 0 {
            return LedgerAnchorComparison(matches: true, issues: [])
        }

        if records.count < anchor.recordCount {
            issues.append(
                "Ledger has \(records.count) record(s) but the anchor from \(anchor.createdAt) "
                    + "saw \(anchor.recordCount); trailing records may have been deleted."
            )
        } else if records[anchor.recordCount - 1].hash != anchor.lastHash {
            issues.append(
                "Ledger record \(anchor.recordCount) does not match the anchored hash from "
                    + "\(anchor.createdAt); the chain may have been rewritten."
            )
        }

        return LedgerAnchorComparison(matches: issues.isEmpty, issues: issues)
    }
}
