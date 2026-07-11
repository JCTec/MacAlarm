public struct DerivedTimelineData: Sendable {
    public var visibleRecords: [TimelineRecord]
    public var visibleDisplayRecords: [TimelineDisplayRecord]
    public var hiddenSearchResults: Set<TimelineRecord.ID>
    public var displayRecordsByID: [TimelineRecord.ID: TimelineDisplayRecord]

    public static let empty = DerivedTimelineData(
        visibleRecords: [],
        visibleDisplayRecords: [],
        hiddenSearchResults: [],
        displayRecordsByID: [:]
    )
}
