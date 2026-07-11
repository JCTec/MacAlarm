import MacAlarmCore
import SwiftUI

public enum TimelineCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case unlock
    case lock
    case sleepWake
    case app
    case file
    case notification
    case agent
    case log
    case ledger
    case custom
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unlock: "Unlock"
        case .lock: "Lock"
        case .sleepWake: "Sleep/Wake"
        case .app: "Apps"
        case .file: "Files"
        case .notification: "Notify"
        case .agent: "Agent"
        case .log: "Logs"
        case .ledger: "Ledger"
        case .custom: "Custom"
        case .other: "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .unlock: "lock.open.fill"
        case .lock: "lock.fill"
        case .sleepWake: "moon.zzz.fill"
        case .app: "app.fill"
        case .file: "doc.text.fill"
        case .notification: "bell.badge.fill"
        case .agent: "waveform.path.ecg"
        case .log: "terminal.fill"
        case .ledger: "link"
        case .custom: "tag.fill"
        case .other: "circle.grid.cross.fill"
        }
    }

    public var tintColor: Color {
        presentationColor.color
    }

    public var presentationColor: TimelineFilterColor {
        switch self {
        case .unlock: .unlock
        case .lock: .lock
        case .sleepWake: .sleepWake
        case .app: .app
        case .file: .file
        case .notification: .notification
        case .agent: .agent
        case .log: .log
        case .ledger: .ledger
        case .custom: .custom
        case .other: .secondary
        }
    }

    public static func category(for event: AlarmEvent) -> TimelineCategory {
        if event.source == "custom" { return .custom }
        if event.source == "notification" { return .notification }
        if event.source == "filesystem" { return .file }
        if event.source == "unifiedLog" { return .log }
        if event.source == "ledger" { return .ledger }
        if event.source == "agent" { return .agent }

        if event.name.contains("unlock") || event.name.contains("unlocked") {
            return .unlock
        }
        if event.name.contains("lock") || event.name.contains("locked") {
            return .lock
        }
        if event.name.contains("Sleep") || event.name.contains("Wake") || event.name.contains("sleep")
            || event.name.contains("wake")
        {
            return .sleepWake
        }
        if event.name.contains("application") {
            return .app
        }

        return .other
    }
}
