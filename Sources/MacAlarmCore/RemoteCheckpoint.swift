import Foundation

public struct RemoteCheckpoint: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var deviceID: String
    public var displayName: String
    public var ledgerPath: String
    public var recordCount: Int
    public var lastHash: String
    public var isLedgerValid: Bool
    public var reason: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        deviceID: String,
        displayName: String,
        ledgerPath: String,
        recordCount: Int,
        lastHash: String,
        isLedgerValid: Bool,
        reason: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.displayName = displayName
        self.ledgerPath = ledgerPath
        self.recordCount = recordCount
        self.lastHash = lastHash
        self.isLedgerValid = isLedgerValid
        self.reason = reason
    }
}

public struct PendingPOSTRequest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var endpointURL: String?
    public var method: String
    public var headers: [String: String]
    public var body: RemoteCheckpoint
    public var status: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        endpointURL: String?,
        method: String = "POST",
        headers: [String: String] = ["Content-Type": "application/json"],
        body: RemoteCheckpoint,
        status: String = "pending-send-not-implemented"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.endpointURL = endpointURL
        self.method = method
        self.headers = headers
        self.body = body
        self.status = status
    }
}

public protocol RemoteCheckpointSink: Sendable {
    func enqueue(_ checkpoint: RemoteCheckpoint) async throws
}

public actor OutboxRemoteCheckpointSink: RemoteCheckpointSink {
    private let directory: URL
    private let endpointURL: String?
    private let fileManager: FileManager

    public init(directory: URL, endpointURL: String?, fileManager: FileManager = .default) {
        self.directory = directory
        self.endpointURL = endpointURL
        self.fileManager = fileManager
    }

    public func enqueue(_ checkpoint: RemoteCheckpoint) async throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let request = PendingPOSTRequest(endpointURL: endpointURL, body: checkpoint)
        let fileURL = directory.appendingPathComponent(
            "\(request.createdAt.timeIntervalSince1970)-\(request.id.uuidString).post.json")
        try CanonicalJSON.encodeLine(request).write(to: fileURL, options: [.atomic])
        chmod(fileURL.path, S_IRUSR | S_IWUSR)
    }
}

public struct DisabledRemoteCheckpointSink: RemoteCheckpointSink {
    public init() {}

    public func enqueue(_ checkpoint: RemoteCheckpoint) async throws {
        _ = checkpoint
    }
}
