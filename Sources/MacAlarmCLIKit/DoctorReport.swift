import Foundation
import MacAlarmCore

struct DoctorReport: Codable, Sendable {
    var checkedAt: Date
    var healthy: Bool
    var paths: MacAlarmInstallationPaths
    var configPath: String
    var ledgerPath: String
    var checks: [DoctorCheck]
    var launchctl: ProcessExecution
    var notification: NotificationAuthorizationSnapshot
    var ledger: LedgerDoctorSnapshot?
}

struct DoctorCheck: Codable, Sendable {
    var name: String
    var status: DoctorStatus
    var required: Bool
    var message: String

    static func pass(_ name: String, _ message: String, required: Bool = false) -> DoctorCheck {
        DoctorCheck(name: name, status: .pass, required: required, message: message)
    }

    static func warning(_ name: String, _ message: String, required: Bool) -> DoctorCheck {
        DoctorCheck(name: name, status: .warning, required: required, message: message)
    }

    static func fail(_ name: String, _ message: String, required: Bool) -> DoctorCheck {
        DoctorCheck(name: name, status: .fail, required: required, message: message)
    }

    var marker: String {
        switch status {
        case .pass: "[OK]"
        case .warning: "[WARN]"
        case .fail: "[FAIL]"
        }
    }
}

enum DoctorStatus: String, Codable, Sendable {
    case pass
    case warning
    case fail
}

struct LedgerDoctorSnapshot: Codable, Sendable {
    var path: String
    var verification: LedgerVerification
    var latestEventAt: Date?
    var latestEventName: String?
}

struct ErrorDescription: Error, CustomStringConvertible, Codable, Sendable {
    var description: String

    init(_ error: Error) {
        self.description = String(describing: error)
    }
}
