import Foundation

enum DoctorReportRenderer {
    static func humanReport(_ report: DoctorReport) -> String {
        var lines = [String]()
        lines.append("MacAlarm Doctor")
        lines.append("Checked: \(report.checkedAt)")
        lines.append("Status: \(report.healthy ? "healthy" : "needs attention")")
        lines.append("")
        lines.append("Install paths:")
        lines.append("  Agent: \(report.paths.agentExecutableURL.path)")
        lines.append("  Control: \(report.paths.controlExecutableURL.path)")
        lines.append("  Config: \(report.configPath)")
        lines.append("  Ledger: \(report.ledgerPath)")
        lines.append("  LaunchAgent: \(report.paths.plistURL.path)")
        lines.append("  Service: \(report.paths.launchAgentService)")
        lines.append("")
        lines.append("Checks:")
        for check in report.checks {
            lines.append("  \(check.marker) \(check.name): \(check.message)")
        }

        if let ledger = report.ledger {
            lines.append("")
            lines.append("Ledger:")
            lines.append("  Records: \(ledger.verification.recordCount)")
            lines.append("  Valid: \(ledger.verification.isValid)")
            lines.append("  Last hash: \(ledger.verification.lastHash)")
            if let latestEventAt = ledger.latestEventAt, let latestEventName = ledger.latestEventName {
                lines.append("  Latest event: \(latestEventName) at \(latestEventAt)")
            }
        }

        lines.append("")
        lines.append("Next checks:")
        lines.append("  launchctl print \"\(report.paths.launchAgentService)\"")
        lines.append("  tail -f \"\(report.paths.standardOutputURL.path)\"")
        lines.append("  macalarmctl verify-ledger --config \"\(report.configPath)\"")
        return lines.joined(separator: "\n")
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "{\"encodingError\":\"\(error)\"}"
        }
    }
}
