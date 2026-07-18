import Foundation
import OSLog

public enum UnifiedLogScope: String, Codable, Equatable, Sendable {
    case currentProcess
    case system
}

public struct UnifiedLogQuery: Codable, Equatable, Sendable {
    public var scope: UnifiedLogScope
    public var since: Date
    public var predicateFormat: String
    public var limit: Int

    public init(
        scope: UnifiedLogScope = .currentProcess,
        since: Date,
        predicateFormat: String,
        limit: Int = 50
    ) {
        self.scope = scope
        self.since = since
        self.predicateFormat = predicateFormat
        self.limit = limit
    }
}

public struct UnifiedLogReader: Sendable {
    public init() {}

    public func readEvents(query: UnifiedLogQuery) throws -> [AlarmEvent] {
        let store = try makeStore(scope: query.scope)
        let position = store.position(date: query.since)
        let predicate = NSPredicate(format: query.predicateFormat)
        let entries = try store.getEntries(with: [], at: position, matching: predicate)

        var events = [AlarmEvent]()
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else {
                continue
            }

            events.append(makeEvent(from: logEntry))

            if events.count >= query.limit {
                break
            }
        }

        MacAlarmLog.sources.debug(
            "Unified log query returned \(events.count, privacy: .public) event(s)")
        return events
    }

    private func makeStore(scope: UnifiedLogScope) throws -> OSLogStore {
        switch scope {
        case .currentProcess:
            return try OSLogStore(scope: .currentProcessIdentifier)
        case .system:
            return try OSLogStore(scope: .system)
        }
    }

    private func makeEvent(from logEntry: OSLogEntryLog) -> AlarmEvent {
        let logMetadata = [
            "logCategory": logEntry.category,
            "logComposedMessage": logEntry.composedMessage,
            "logProcess": logEntry.process,
            "logSender": logEntry.sender,
            "logSubsystem": logEntry.subsystem,
        ].filter { !$0.value.isEmpty }

        if let payload = CustomLogEventPayload.parseLogLine(logEntry.composedMessage) {
            var metadata = payload.metadata
            metadata.merge(logMetadata) { current, _ in current }
            if let message = payload.message, !message.isEmpty {
                metadata["message"] = message
            }

            return AlarmEvent(
                observedAt: logEntry.date,
                source: "custom",
                name: payload.name,
                severity: payload.severity,
                metadata: metadata
            )
        }

        return AlarmEvent(
            observedAt: logEntry.date,
            source: "unifiedLog",
            name: "log.match",
            severity: AlarmSeverity(logEntry.level),
            metadata: [
                "category": logEntry.category,
                "composedMessage": logEntry.composedMessage,
                "process": logEntry.process,
                "sender": logEntry.sender,
                "subsystem": logEntry.subsystem,
            ].filter { !$0.value.isEmpty }
        )
    }
}

private extension AlarmSeverity {
    init(_ level: OSLogEntryLog.Level) {
        switch level {
        case .undefined:
            self = .info
        case .debug:
            self = .debug
        case .info:
            self = .info
        case .notice:
            self = .notice
        case .error:
            self = .warning
        case .fault:
            self = .critical
        @unknown default:
            self = .info
        }
    }
}
