import Foundation
import MacAlarmCore

enum DoctorLedgerFreshness {
    static func staleMessage(
        snapshot: LedgerDoctorSnapshot,
        config: MacAlarmConfig,
        now: Date = Date()
    ) -> String? {
        guard config.heartbeat.enabled, let latestEventAt = snapshot.latestEventAt else {
            return nil
        }

        let age = now.timeIntervalSince(latestEventAt)
        let expectedInterval = max(config.heartbeat.intervalSeconds * 2, 180)
        guard age > expectedInterval else {
            return nil
        }

        return "latest event is \(Int(age))s old; heartbeat interval is \(Int(config.heartbeat.intervalSeconds))s"
    }
}
