import Foundation

struct HealthCommand {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() async throws -> Never {
        let report = await AgentStatusReportBuilder(configPath: optionValue("--config")).build()
        printHumanReport(report)
        Foundation.exit(report.isCurrent ? 0 : 3)
    }

    private func optionValue(_ option: String) -> String? {
        guard let index = arguments.firstIndex(of: option) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

    private func printHumanReport(_ report: AgentStatusReport) {
        print("MacAlarm Health")
        print("Status: \(report.isCurrent ? "healthy" : "needs attention")")
        print("Checked: \(report.checkedAt)")
        print()

        guard let snapshot = report.snapshot else {
            print("Agent: unknown")
            print("Status file: missing at \(report.statusPath)")
            print("Config: \(report.configPath)")
            print()
            print("Run: macalarmctl doctor")
            return
        }

        print("Agent: \(snapshot.state.rawValue) (pid \(snapshot.processID))")
        print("LaunchAgent: \(launchAgentText(report))")
        print("Process: \(report.processRunning == true ? "running" : "not running")")
        if report.statusMatchesLaunchAgent == false {
            print("Status PID: stale, launchd reports pid \(report.launchAgentProcessID ?? -1)")
        }
        print("Heartbeat: \(heartbeatText(report))")
        print("Events: \(snapshot.processedEventCount) processed, \(snapshot.heartbeatCount) heartbeats")
        print("Alarms: \(snapshot.alarmCount), delivery failures: \(snapshot.deliveryFailureCount)")
        print("Status file: \(report.statusPath)")
        print("Ledger: \(snapshot.ledgerPath)")

        if let latestEventName = snapshot.latestEventName, let latestEventAt = snapshot.latestEventAt {
            print("Latest event: \(snapshot.latestEventSource ?? "unknown").\(latestEventName) at \(latestEventAt)")
        }
        if let latestLedgerHash = snapshot.latestLedgerHash {
            print("Latest hash: \(latestLedgerHash)")
        }
        if let lastErrorDescription = snapshot.lastErrorDescription {
            print("Last error: \(lastErrorDescription)")
        }

        if !report.isCurrent {
            print()
            print("Run: macalarmctl doctor")
        }
    }

    private func heartbeatText(_ report: AgentStatusReport) -> String {
        guard let heartbeatAgeSeconds = report.heartbeatAgeSeconds else {
            return report.snapshot?.heartbeatIntervalSeconds == nil ? "disabled" : "pending"
        }

        let freshness = report.isHeartbeatFresh ? "fresh" : "stale"
        let expected = report.expectedHeartbeatAgeSeconds.map { ", threshold \(Self.durationText($0))" } ?? ""
        return "\(Self.durationText(heartbeatAgeSeconds)) ago (\(freshness)\(expected))"
    }

    private func launchAgentText(_ report: AgentStatusReport) -> String {
        guard report.launchAgentLoaded else {
            return "not loaded"
        }

        guard let processID = report.launchAgentProcessID else {
            return "loaded"
        }

        return "loaded (pid \(processID))"
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        return "\(minutes / 60)h"
    }
}
