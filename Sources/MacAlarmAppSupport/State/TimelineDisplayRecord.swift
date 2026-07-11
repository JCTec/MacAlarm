import Foundation
import MacAlarmCore

public struct TimelineDisplayRecord: Identifiable, Equatable, Sendable {
    public var record: TimelineRecord
    public var presentation: TimelineEventPresentation
    public var displayState: CategoryDisplayState
    public var hiddenBySearch: Bool

    public init(
        record: TimelineRecord,
        presentation: TimelineEventPresentation,
        displayState: CategoryDisplayState,
        hiddenBySearch: Bool
    ) {
        self.record = record
        self.presentation = presentation
        self.displayState = displayState
        self.hiddenBySearch = hiddenBySearch
    }

    public var id: TimelineRecord.ID { record.id }
    public var event: AlarmEvent { record.event }
    public var timestamp: Date { record.timestamp }
    public var title: String { record.title }
    public var subtitle: String { record.subtitle }
}
