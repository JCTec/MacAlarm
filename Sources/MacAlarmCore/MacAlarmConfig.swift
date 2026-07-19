import Foundation

public struct MacAlarmConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var identity: AgentIdentity
    public var storage: StorageConfig
    public var secrets: SecretConfig
    public var heartbeat: HeartbeatConfig
    public var session: SessionConfig
    public var filesystem: FilesystemConfig
    public var unifiedLog: UnifiedLogConfig
    public var notifications: NotificationConfig
    public var telegram: TelegramConfig
    public var remoteCheckpoint: RemoteCheckpointConfig
    public var hashAnchor: HashAnchorConfig
    public var rules: [AlarmRule]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case identity
        case storage
        case secrets
        case heartbeat
        case session
        case filesystem
        case unifiedLog
        case notifications
        case telegram
        case remoteCheckpoint
        case hashAnchor
        case rules
    }

    public init(
        schemaVersion: Int = 1,
        identity: AgentIdentity = .default,
        storage: StorageConfig = .default,
        secrets: SecretConfig = .default,
        heartbeat: HeartbeatConfig = .default,
        session: SessionConfig = .default,
        filesystem: FilesystemConfig = .default,
        unifiedLog: UnifiedLogConfig = .default,
        notifications: NotificationConfig = .default,
        telegram: TelegramConfig = .default,
        remoteCheckpoint: RemoteCheckpointConfig = .default,
        hashAnchor: HashAnchorConfig = .default,
        rules: [AlarmRule] = MacAlarmConfig.defaultRules
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.storage = storage
        self.secrets = secrets
        self.heartbeat = heartbeat
        self.session = session
        self.filesystem = filesystem
        self.unifiedLog = unifiedLog
        self.notifications = notifications
        self.telegram = telegram
        self.remoteCheckpoint = remoteCheckpoint
        self.hashAnchor = hashAnchor
        self.rules = rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.identity = try container.decodeIfPresent(AgentIdentity.self, forKey: .identity) ?? .default
        self.storage = try container.decodeIfPresent(StorageConfig.self, forKey: .storage) ?? .default
        self.secrets = try container.decodeIfPresent(SecretConfig.self, forKey: .secrets) ?? .default
        self.heartbeat = try container.decodeIfPresent(HeartbeatConfig.self, forKey: .heartbeat) ?? .default
        self.session = try container.decodeIfPresent(SessionConfig.self, forKey: .session) ?? .default
        self.filesystem = try container.decodeIfPresent(FilesystemConfig.self, forKey: .filesystem) ?? .default
        self.unifiedLog = try container.decodeIfPresent(UnifiedLogConfig.self, forKey: .unifiedLog) ?? .default
        self.notifications = try container.decodeIfPresent(NotificationConfig.self, forKey: .notifications) ?? .default
        self.telegram = try container.decodeIfPresent(TelegramConfig.self, forKey: .telegram) ?? .default
        self.remoteCheckpoint =
            try container.decodeIfPresent(RemoteCheckpointConfig.self, forKey: .remoteCheckpoint) ?? .default
        self.hashAnchor = try container.decodeIfPresent(HashAnchorConfig.self, forKey: .hashAnchor) ?? .default
        self.rules = try container.decodeIfPresent([AlarmRule].self, forKey: .rules) ?? Self.defaultRules
    }

    public static let defaultRules: [AlarmRule] = [
        AlarmRule(
            id: "screen-unlocked",
            match: EventMatch(source: "session", name: "screen.unlocked"),
            severity: .critical,
            message: "Mac screen unlocked",
            cooldownSeconds: 120
        ),
        AlarmRule(
            id: "agent-started",
            match: EventMatch(source: "agent", name: "agent.started"),
            severity: .notice,
            message: "MacAlarm agent started",
            cooldownSeconds: 60
        ),
        AlarmRule(
            id: "canary-changed",
            match: EventMatch(source: "filesystem", name: "path.changed"),
            severity: .warning,
            message: "Watched path changed",
            cooldownSeconds: 30
        ),
        AlarmRule(
            id: "log-warning",
            match: EventMatch(source: "unifiedLog", name: "log.match", minimumSeverity: .warning),
            severity: .warning,
            message: "Unified log warning matched",
            cooldownSeconds: 300
        ),
    ]
}

public struct AgentIdentity: Codable, Equatable, Sendable {
    public var deviceID: String
    public var displayName: String

    public init(
        deviceID: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        displayName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    ) {
        self.deviceID = deviceID
        self.displayName = displayName
    }

    public static let `default` = AgentIdentity()
}

public struct StorageConfig: Codable, Equatable, Sendable {
    public var ledgerPath: String
    public var outboxDirectory: String
    public var runtimeDirectory: String
    /// Optional size limit for the active ledger file. When set, the ledger
    /// rotates the active file into an archived segment on append and starts a
    /// new segment that continues the same hash chain. Nil disables rotation.
    public var maxLedgerFileBytes: Int?

    public init(
        ledgerPath: String = "~/Library/Application Support/MacAlarm/events.jsonl",
        outboxDirectory: String = "~/Library/Application Support/MacAlarm/outbox",
        runtimeDirectory: String = "~/Library/Application Support/MacAlarm/runtime",
        maxLedgerFileBytes: Int? = nil
    ) {
        self.ledgerPath = ledgerPath
        self.outboxDirectory = outboxDirectory
        self.runtimeDirectory = runtimeDirectory
        self.maxLedgerFileBytes = maxLedgerFileBytes
    }

    public static let `default` = StorageConfig()
}

public struct SecretConfig: Codable, Equatable, Sendable {
    public var hmacKeyAccount: String
    public var allowDevelopmentFallbackKey: Bool

    public init(
        hmacKeyAccount: String = "ledger-hmac-key",
        allowDevelopmentFallbackKey: Bool = false
    ) {
        self.hmacKeyAccount = hmacKeyAccount
        self.allowDevelopmentFallbackKey = allowDevelopmentFallbackKey
    }

    public static let `default` = SecretConfig()
}

public struct HeartbeatConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var intervalSeconds: TimeInterval
    public var checkpointEveryHeartbeats: Int

    public init(enabled: Bool = true, intervalSeconds: TimeInterval = 60, checkpointEveryHeartbeats: Int = 5) {
        self.enabled = enabled
        self.intervalSeconds = intervalSeconds
        self.checkpointEveryHeartbeats = checkpointEveryHeartbeats
    }

    public static let `default` = HeartbeatConfig()
}

public struct SessionConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var includeApplicationEvents: Bool

    public init(enabled: Bool = true, includeApplicationEvents: Bool = true) {
        self.enabled = enabled
        self.includeApplicationEvents = includeApplicationEvents
    }

    public static let `default` = SessionConfig()
}

public struct FilesystemConfig: Codable, Equatable, Sendable {
    public var watchedPaths: [WatchedPath]

    public init(
        watchedPaths: [WatchedPath] = [
            WatchedPath(path: "~/.ssh/authorized_keys", label: "ssh-authorized-keys", required: false),
            WatchedPath(path: "~/Library/LaunchAgents", label: "user-launch-agents", required: false),
        ]
    ) {
        self.watchedPaths = watchedPaths
    }

    public static let `default` = FilesystemConfig()
}

public struct WatchedPath: Codable, Equatable, Sendable {
    public var path: String
    public var label: String
    public var required: Bool

    public init(path: String, label: String, required: Bool = false) {
        self.path = path
        self.label = label
        self.required = required
    }
}

public struct UnifiedLogConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var pollIntervalSeconds: TimeInterval
    public var queries: [UnifiedLogQueryTemplate]

    public init(
        enabled: Bool = false,
        pollIntervalSeconds: TimeInterval = 300,
        queries: [UnifiedLogQueryTemplate] = [
            UnifiedLogQueryTemplate(
                name: "macalarm-custom-events",
                scope: .system,
                predicateFormat: "subsystem == 'dev.jc.macalarm.custom'",
                lookbackSeconds: 60,
                limit: 100
            ),
            UnifiedLogQueryTemplate(
                name: "current-process-errors",
                scope: .currentProcess,
                predicateFormat: "messageType == error OR messageType == fault",
                lookbackSeconds: 300,
                limit: 25
            ),
        ]
    ) {
        self.enabled = enabled
        self.pollIntervalSeconds = pollIntervalSeconds
        self.queries = queries
    }

    public static let `default` = UnifiedLogConfig()
}

public struct UnifiedLogQueryTemplate: Codable, Equatable, Sendable {
    public var name: String
    public var scope: UnifiedLogScope
    public var predicateFormat: String
    public var lookbackSeconds: TimeInterval
    public var limit: Int

    public init(
        name: String, scope: UnifiedLogScope, predicateFormat: String, lookbackSeconds: TimeInterval, limit: Int
    ) {
        self.name = name
        self.scope = scope
        self.predicateFormat = predicateFormat
        self.lookbackSeconds = lookbackSeconds
        self.limit = limit
    }
}

public struct NotificationConfig: Codable, Equatable, Sendable {
    public var console: Bool
    public var localNotification: Bool
    public var appleScriptFallback: Bool
    public var sound: Bool

    public init(
        console: Bool = true,
        localNotification: Bool = true,
        appleScriptFallback: Bool = true,
        sound: Bool = true
    ) {
        self.console = console
        self.localNotification = localNotification
        self.appleScriptFallback = appleScriptFallback
        self.sound = sound
    }

    public static let `default` = NotificationConfig()
}

public struct TelegramConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var botTokenAccount: String
    public var approvedChatIDs: [Int64]
    public var deniedChatIDs: [Int64]
    public var minimumSeverity: AlarmSeverity
    public var includedRuleIDs: [String]
    public var includedEventSources: [String]
    public var commandsEnabled: Bool
    public var pollingEnabled: Bool
    public var pollingIntervalSeconds: TimeInterval
    public var updateLimit: Int

    public init(
        enabled: Bool = false,
        botTokenAccount: String = "telegram-bot-token",
        approvedChatIDs: [Int64] = [],
        deniedChatIDs: [Int64] = [],
        minimumSeverity: AlarmSeverity = .warning,
        includedRuleIDs: [String] = [],
        includedEventSources: [String] = [],
        commandsEnabled: Bool = true,
        pollingEnabled: Bool = false,
        pollingIntervalSeconds: TimeInterval = 10,
        updateLimit: Int = 25
    ) {
        self.enabled = enabled
        self.botTokenAccount = botTokenAccount
        self.approvedChatIDs = approvedChatIDs
        self.deniedChatIDs = deniedChatIDs
        self.minimumSeverity = minimumSeverity
        self.includedRuleIDs = includedRuleIDs
        self.includedEventSources = includedEventSources
        self.commandsEnabled = commandsEnabled
        self.pollingEnabled = pollingEnabled
        self.pollingIntervalSeconds = pollingIntervalSeconds
        self.updateLimit = updateLimit
    }

    public static let `default` = TelegramConfig()
}

/// Where ledger hash anchors are written.
///
/// - `iCloudDrive`: environment-aware iCloud location — the CloudDocs folder
///   when unsandboxed, the app's ubiquity container when sandboxed. This is the
///   default so anchors leave the Mac's own trust domain.
/// - `directory`: the literal `HashAnchorConfig.directory` path, for users who
///   pin anchors to a specific local/synced folder.
public enum AnchorDestination: String, Codable, Equatable, Sendable {
    case iCloudDrive
    case directory
}

public struct HashAnchorConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var directory: String
    public var anchorEveryHeartbeats: Int
    public var destination: AnchorDestination

    public static let defaultDirectory = "~/Library/Mobile Documents/com~apple~CloudDocs/MacAlarm"

    public init(
        enabled: Bool = true,
        directory: String = HashAnchorConfig.defaultDirectory,
        anchorEveryHeartbeats: Int = 5,
        destination: AnchorDestination = .iCloudDrive
    ) {
        self.enabled = enabled
        self.directory = directory
        self.anchorEveryHeartbeats = anchorEveryHeartbeats
        self.destination = destination
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case directory
        case anchorEveryHeartbeats
        case destination
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.directory = try container.decodeIfPresent(String.self, forKey: .directory) ?? Self.defaultDirectory
        self.anchorEveryHeartbeats = try container.decodeIfPresent(Int.self, forKey: .anchorEveryHeartbeats) ?? 5
        // A config predating this field kept writing to `directory`, so an absent
        // `destination` decodes as `.directory` — byte-for-byte the old behavior.
        // Freshly created configs default to `.iCloudDrive` (see init above).
        self.destination = try container.decodeIfPresent(AnchorDestination.self, forKey: .destination) ?? .directory
    }

    public static let `default` = HashAnchorConfig()
}

public struct RemoteCheckpointConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var endpointURL: String?
    public var outboxOnly: Bool

    public init(enabled: Bool = false, endpointURL: String? = nil, outboxOnly: Bool = true) {
        self.enabled = enabled
        self.endpointURL = endpointURL
        self.outboxOnly = outboxOnly
    }

    public static let `default` = RemoteCheckpointConfig()
}

public extension StorageConfig {
    /// Storage paths rooted at an absolute base directory. Used for sandboxed
    /// installs, where the ledger/outbox/runtime must live in the App Group
    /// container (as absolute paths, since `~` under the sandbox expands to a
    /// process-private container and would split shared state across processes).
    static func rooted(at baseDirectory: URL, maxLedgerFileBytes: Int? = nil) -> StorageConfig {
        StorageConfig(
            ledgerPath: baseDirectory.appendingPathComponent("events.jsonl").path,
            outboxDirectory: baseDirectory.appendingPathComponent("outbox", isDirectory: true).path,
            runtimeDirectory: baseDirectory.appendingPathComponent("runtime", isDirectory: true).path,
            maxLedgerFileBytes: maxLedgerFileBytes
        )
    }
}

public extension MacAlarmConfig {
    /// Default config written at install time. Unsandboxed builds keep the
    /// historical `~/Library` tilde paths unchanged. Sandboxed installs pin the
    /// storage paths to absolute App Group container paths derived from `paths`,
    /// so the viewer app, recorder helper, and macalarmctl all resolve the same
    /// ledger, outbox, runtime, secrets, and spool.
    static func installedDefault(paths: MacAlarmInstallationPaths) -> MacAlarmConfig {
        guard SandboxEnvironment.isSandboxed else {
            return MacAlarmConfig()
        }
        return MacAlarmConfig(storage: .rooted(at: paths.installDirectory))
    }

    static func load(from url: URL) throws -> MacAlarmConfig {
        let data = try Data(contentsOf: url)
        return try CanonicalJSON.decoder.decode(MacAlarmConfig.self, from: data)
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try prettyPrintedJSON()
        try data.write(to: url, options: [.atomic])
        chmod(url.path, S_IRUSR | S_IWUSR)
    }

    func prettyPrintedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
