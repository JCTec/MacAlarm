import Foundation

public enum AlarmSeverity: String, Codable, CaseIterable, Comparable, Sendable {
    case debug
    case info
    case notice
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .critical: 4
        }
    }

    public static func < (lhs: AlarmSeverity, rhs: AlarmSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct AlarmEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var observedAt: Date
    public var host: String
    public var source: String
    public var name: String
    public var severity: AlarmSeverity
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        observedAt: Date = .now,
        host: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        source: String,
        name: String,
        severity: AlarmSeverity = .info,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.observedAt = observedAt
        self.host = host
        self.source = source
        self.name = name
        self.severity = severity
        self.metadata = metadata
    }
}

public struct Alarm: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var ruleID: String
    public var raisedAt: Date
    public var severity: AlarmSeverity
    public var message: String
    public var event: AlarmEvent

    public init(
        id: UUID = UUID(),
        ruleID: String,
        raisedAt: Date = .now,
        severity: AlarmSeverity,
        message: String,
        event: AlarmEvent
    ) {
        self.id = id
        self.ruleID = ruleID
        self.raisedAt = raisedAt
        self.severity = severity
        self.message = message
        self.event = event
    }
}
