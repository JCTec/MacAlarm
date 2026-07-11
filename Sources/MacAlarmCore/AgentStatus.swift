import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public enum AgentRuntimeState: String, Codable, Equatable, Sendable {
    case starting
    case running
    case stopping
    case stopped
    case degraded
}

public struct AgentStatusSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var state: AgentRuntimeState
    public var generatedAt: Date
    public var startedAt: Date?
    public var stoppedAt: Date?
    public var processID: Int32
    public var identity: AgentIdentity
    public var ledgerPath: String
    public var runtimeDirectory: String
    public var heartbeatIntervalSeconds: TimeInterval?
    public var sessionEventsEnabled: Bool
    public var applicationEventsEnabled: Bool
    public var unifiedLogEnabled: Bool
    public var watchedPathCount: Int
    public var processedEventCount: Int
    public var heartbeatCount: Int
    public var alarmCount: Int
    public var deliveryFailureCount: Int
    public var latestEventAt: Date?
    public var latestEventSource: String?
    public var latestEventName: String?
    public var latestHeartbeatAt: Date?
    public var latestLedgerHash: String?
    public var lastErrorDescription: String?

    public init(
        schemaVersion: Int = 1,
        state: AgentRuntimeState,
        generatedAt: Date = .now,
        startedAt: Date? = nil,
        stoppedAt: Date? = nil,
        processID: Int32,
        identity: AgentIdentity,
        ledgerPath: String,
        runtimeDirectory: String,
        heartbeatIntervalSeconds: TimeInterval?,
        sessionEventsEnabled: Bool,
        applicationEventsEnabled: Bool,
        unifiedLogEnabled: Bool,
        watchedPathCount: Int,
        processedEventCount: Int = 0,
        heartbeatCount: Int = 0,
        alarmCount: Int = 0,
        deliveryFailureCount: Int = 0,
        latestEventAt: Date? = nil,
        latestEventSource: String? = nil,
        latestEventName: String? = nil,
        latestHeartbeatAt: Date? = nil,
        latestLedgerHash: String? = nil,
        lastErrorDescription: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.generatedAt = generatedAt
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.processID = processID
        self.identity = identity
        self.ledgerPath = ledgerPath
        self.runtimeDirectory = runtimeDirectory
        self.heartbeatIntervalSeconds = heartbeatIntervalSeconds
        self.sessionEventsEnabled = sessionEventsEnabled
        self.applicationEventsEnabled = applicationEventsEnabled
        self.unifiedLogEnabled = unifiedLogEnabled
        self.watchedPathCount = watchedPathCount
        self.processedEventCount = processedEventCount
        self.heartbeatCount = heartbeatCount
        self.alarmCount = alarmCount
        self.deliveryFailureCount = deliveryFailureCount
        self.latestEventAt = latestEventAt
        self.latestEventSource = latestEventSource
        self.latestEventName = latestEventName
        self.latestHeartbeatAt = latestHeartbeatAt
        self.latestLedgerHash = latestLedgerHash
        self.lastErrorDescription = lastErrorDescription
    }
}

public actor AgentStatusStore {
    public let statusURL: URL
    private var snapshot: AgentStatusSnapshot

    public init(
        config: MacAlarmConfig,
        statusURL: URL? = nil,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        now: Date = .now
    ) {
        let runtimeDirectory = PathResolver.fileURL(config.storage.runtimeDirectory)
        self.statusURL = statusURL ?? runtimeDirectory.appendingPathComponent("status.json")
        self.snapshot = AgentStatusSnapshot(
            state: .starting,
            generatedAt: now,
            processID: processID,
            identity: config.identity,
            ledgerPath: PathResolver.expandedPath(config.storage.ledgerPath),
            runtimeDirectory: runtimeDirectory.path,
            heartbeatIntervalSeconds: config.heartbeat.enabled ? config.heartbeat.intervalSeconds : nil,
            sessionEventsEnabled: config.session.enabled,
            applicationEventsEnabled: config.session.includeApplicationEvents,
            unifiedLogEnabled: config.unifiedLog.enabled,
            watchedPathCount: config.filesystem.watchedPaths.count
        )
    }

    public func markRunning(at date: Date = .now) async {
        snapshot.state = .running
        snapshot.startedAt = snapshot.startedAt ?? date
        snapshot.stoppedAt = nil
        await persist(generatedAt: date)
    }

    public func record(event: AlarmEvent, result: EventProcessingResult, at date: Date = .now) async {
        snapshot.processedEventCount += 1
        snapshot.alarmCount += result.alarms.count
        snapshot.deliveryFailureCount += result.deliveries.filter { !$0.succeeded }.count
        snapshot.latestEventAt = event.observedAt
        snapshot.latestEventSource = event.source
        snapshot.latestEventName = event.name
        snapshot.latestLedgerHash = result.record?.hash ?? snapshot.latestLedgerHash

        if event.source == "agent", event.name == "agent.heartbeat" {
            snapshot.heartbeatCount += 1
            snapshot.latestHeartbeatAt = event.observedAt
        }

        if let errorDescription = result.errorDescription {
            snapshot.state = .degraded
            snapshot.lastErrorDescription = errorDescription
        }

        await persist(generatedAt: date)
    }

    public func markStopping(at date: Date = .now) async {
        snapshot.state = .stopping
        await persist(generatedAt: date)
    }

    public func markStopped(at date: Date = .now) async {
        snapshot.state = .stopped
        snapshot.stoppedAt = date
        await persist(generatedAt: date)
    }

    public static func load(from url: URL) throws -> AgentStatusSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentStatusSnapshot.self, from: data)
    }

    public static func remove(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func persist(generatedAt: Date) async {
        snapshot.generatedAt = generatedAt
        let statusURL = self.statusURL

        do {
            let data = try Self.encoder.encode(snapshot)
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(
                    at: statusURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: statusURL, options: [.atomic])
                #if canImport(Darwin)
                    chmod(statusURL.path, S_IRUSR | S_IWUSR)
                #endif
            }.value
        } catch {
            snapshot.lastErrorDescription = String(describing: error)
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
