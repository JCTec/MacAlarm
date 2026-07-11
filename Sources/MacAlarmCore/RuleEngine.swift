import Foundation

public struct EventMatch: Codable, Equatable, Sendable {
    public var source: String?
    public var name: String?
    public var minimumSeverity: AlarmSeverity?
    public var metadataEquals: [String: String]

    public init(
        source: String? = nil,
        name: String? = nil,
        minimumSeverity: AlarmSeverity? = nil,
        metadataEquals: [String: String] = [:]
    ) {
        self.source = source
        self.name = name
        self.minimumSeverity = minimumSeverity
        self.metadataEquals = metadataEquals
    }

    public func matches(_ event: AlarmEvent) -> Bool {
        if let source, event.source != source {
            return false
        }

        if let name, event.name != name {
            return false
        }

        if let minimumSeverity, event.severity < minimumSeverity {
            return false
        }

        for (key, expectedValue) in metadataEquals where event.metadata[key] != expectedValue {
            return false
        }

        return true
    }
}

public struct Threshold: Codable, Equatable, Sendable {
    public var count: Int
    public var intervalSeconds: TimeInterval

    public init(count: Int, intervalSeconds: TimeInterval) {
        self.count = count
        self.intervalSeconds = intervalSeconds
    }
}

public struct QuietHours: Codable, Equatable, Sendable {
    public var startHour: Int
    public var endHour: Int
    public var calendarIdentifier: Calendar.Identifier

    public init(startHour: Int, endHour: Int, calendarIdentifier: Calendar.Identifier = .gregorian) {
        self.startHour = startHour
        self.endHour = endHour
        self.calendarIdentifier = calendarIdentifier
    }

    public func contains(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.timeZone = .current
        let hour = calendar.component(.hour, from: date)

        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        }

        return hour >= startHour || hour < endHour
    }
}

public struct AlarmRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var match: EventMatch
    public var severity: AlarmSeverity
    public var message: String
    public var cooldownSeconds: TimeInterval
    public var threshold: Threshold?
    public var quietHours: QuietHours?

    public init(
        id: String,
        match: EventMatch,
        severity: AlarmSeverity,
        message: String,
        cooldownSeconds: TimeInterval = 0,
        threshold: Threshold? = nil,
        quietHours: QuietHours? = nil
    ) {
        self.id = id
        self.match = match
        self.severity = severity
        self.message = message
        self.cooldownSeconds = cooldownSeconds
        self.threshold = threshold
        self.quietHours = quietHours
    }
}

public actor RuleEngine {
    private let rules: [AlarmRule]
    private var lastRaisedAtByRuleID = [String: Date]()
    private var thresholdWindowsByRuleID = [String: [Date]]()

    public init(rules: [AlarmRule]) {
        self.rules = rules
    }

    public func evaluate(_ event: AlarmEvent, now: Date = .now) -> [Alarm] {
        rules.compactMap { rule in
            guard rule.match.matches(event) else {
                return nil
            }

            if let quietHours = rule.quietHours, !quietHours.contains(event.observedAt) {
                return nil
            }

            guard thresholdSatisfied(for: rule, now: now) else {
                return nil
            }

            guard !isCoolingDown(rule, now: now) else {
                return nil
            }

            lastRaisedAtByRuleID[rule.id] = now
            return Alarm(
                ruleID: rule.id,
                raisedAt: now,
                severity: rule.severity,
                message: rule.message,
                event: event
            )
        }
    }

    private func isCoolingDown(_ rule: AlarmRule, now: Date) -> Bool {
        guard rule.cooldownSeconds > 0, let lastRaisedAt = lastRaisedAtByRuleID[rule.id] else {
            return false
        }

        return now.timeIntervalSince(lastRaisedAt) < rule.cooldownSeconds
    }

    private func thresholdSatisfied(for rule: AlarmRule, now: Date) -> Bool {
        guard let threshold = rule.threshold else {
            return true
        }

        let cutoff = now.addingTimeInterval(-threshold.intervalSeconds)
        var window = thresholdWindowsByRuleID[rule.id, default: []]
        window.append(now)
        window.removeAll { $0 < cutoff }
        thresholdWindowsByRuleID[rule.id] = window
        return window.count >= threshold.count
    }
}
