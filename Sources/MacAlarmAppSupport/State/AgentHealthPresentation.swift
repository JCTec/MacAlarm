import Foundation
import MacAlarmCore

#if canImport(Darwin)
    import Darwin
#endif

enum AgentHealthLevel: String, Equatable, Sendable {
    case unknown
    case healthy
    case warning
    case critical
}

struct AgentHealthPresentation: Equatable, Sendable {
    var title: String
    var detail: String
    var level: AgentHealthLevel
}

enum AgentHealthPresenter {
    static func presentation(
        snapshot: AgentStatusSnapshot?,
        loadError: String?,
        now: Date
    ) -> AgentHealthPresentation {
        guard let snapshot else {
            if loadError != nil {
                return AgentHealthPresentation(
                    title: "Recorder status unavailable",
                    detail: "Open details to inspect the status issue.",
                    level: .warning
                )
            }

            return AgentHealthPresentation(
                title: "Recorder not set up",
                detail: "Install the recorder to start local event capture.",
                level: .unknown
            )
        }

        if !processIsRunning(processID: snapshot.processID) {
            return AgentHealthPresentation(
                title: "Recorder stopped",
                detail: "Start the recorder to resume local event capture.",
                level: .critical
            )
        }

        if snapshot.state == .degraded {
            return AgentHealthPresentation(
                title: "Recorder degraded",
                detail: snapshot.lastErrorDescription ?? "Recorder reported degraded state",
                level: .warning
            )
        }

        if snapshot.state != .running {
            return AgentHealthPresentation(
                title: "Recorder \(snapshot.state.rawValue)",
                detail: "Latest status \(ageText(since: snapshot.generatedAt, now: now)) ago",
                level: snapshot.state == .stopped ? .critical : .warning
            )
        }

        if let latestHeartbeatAt = snapshot.latestHeartbeatAt,
            let heartbeatInterval = snapshot.heartbeatIntervalSeconds
        {
            let age = now.timeIntervalSince(latestHeartbeatAt)
            let threshold = max(heartbeatInterval * 2, 180)
            if age > threshold {
                return AgentHealthPresentation(
                    title: "Heartbeat stale",
                    detail: "Last heartbeat \(ageText(since: latestHeartbeatAt, now: now)) ago",
                    level: .warning
                )
            }
        }

        return AgentHealthPresentation(
            title: "Recorder running",
            detail: "Heartbeat \(snapshot.latestHeartbeatAt.map { ageText(since: $0, now: now) } ?? "pending") ago",
            level: .healthy
        )
    }

    static func ageText(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        return "\(minutes / 60)h"
    }

    private static func processIsRunning(processID: Int32) -> Bool {
        guard processID > 0 else {
            return false
        }

        #if canImport(Darwin)
            return kill(processID, 0) == 0 || errno == EPERM
        #else
            return true
        #endif
    }
}
