import Foundation
import MacAlarmCore
import SwiftUI

public struct TimelineRecord: Identifiable, Equatable, Sendable {
    public var index: Int
    public var record: LedgerRecord
    public var category: TimelineCategory

    public init(index: Int, record: LedgerRecord, category: TimelineCategory) {
        self.index = index
        self.record = record
        self.category = category
    }

    public var id: UUID { record.event.id }
    public var event: AlarmEvent { record.event }
    public var timestamp: Date { record.event.observedAt }

    public var title: String {
        switch category {
        case .unlock:
            return "Screen unlocked"
        case .lock:
            return "Screen locked"
        case .sleepWake:
            return event.name.contains("Wake") || event.name.contains("wake") ? "System woke" : "System slept"
        case .app:
            return event.metadata["applicationName"] ?? "Application event"
        case .file:
            return event.metadata["label"] ?? event.metadata["path"] ?? "File event"
        case .notification:
            return event.metadata["channel"] ?? "Notification"
        case .agent:
            return event.name.replacingOccurrences(of: "agent.", with: "Agent ")
        case .log:
            return event.metadata["composedMessage"] ?? "Log match"
        case .ledger:
            return "Ledger event"
        case .custom:
            return event.name
        case .other:
            return event.name
        }
    }

    public var subtitle: String {
        if let bundle = event.metadata["bundleIdentifier"] { return bundle }
        if let notification = event.metadata["notification"] { return notification }
        if let detail = event.metadata["detail"] { return detail }
        if let path = event.metadata["path"] { return path }
        return event.source
    }

    public var searchText: String {
        ([event.source, event.name, title, subtitle, event.severity.rawValue]
            + event.metadata.flatMap { [$0.key, $0.value] })
            .joined(separator: " ")
            .lowercased()
    }

    public var tintColor: Color {
        category.tintColor
    }
}
