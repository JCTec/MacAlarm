import Foundation

public struct DerivedTimelineSnapshot: Sendable {
    public var records: [TimelineRecord]
    public var filters: [TimelineFilterDefinition]
    public var filterStates: [String: CategoryDisplayState]
    public var searchText: String
    public var timeRange: TimeInterval
    public var now: Date

    public init(
        records: [TimelineRecord],
        filters: [TimelineFilterDefinition],
        filterStates: [String: CategoryDisplayState],
        searchText: String,
        timeRange: TimeInterval,
        now: Date
    ) {
        self.records = records
        self.filters = filters
        self.filterStates = filterStates
        self.searchText = searchText
        self.timeRange = timeRange
        self.now = now
    }
}
