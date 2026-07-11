import Foundation

public enum TimelineDerivedState {
    public static func compute(_ snapshot: DerivedTimelineSnapshot) -> DerivedTimelineData {
        compute(snapshot, shouldCancel: { false }) ?? .empty
    }

    public static func computeIfNotCancelled(_ snapshot: DerivedTimelineSnapshot) -> DerivedTimelineData? {
        compute(snapshot) {
            Task.isCancelled
        }
    }

    private static func compute(
        _ snapshot: DerivedTimelineSnapshot,
        shouldCancel: () -> Bool
    ) -> DerivedTimelineData? {
        let lowerBound = snapshot.now.addingTimeInterval(-snapshot.timeRange)
        let query = snapshot.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let enabledFilters = snapshot.filters.filter(\.isEnabled)
        let enabledFiltersAreEmpty = enabledFilters.isEmpty
        let resolver = TimelinePresentationResolver(filterStates: snapshot.filterStates)
        var visible = [TimelineRecord]()
        var visibleDisplayRecords = [TimelineDisplayRecord]()
        var hiddenSearchResults = Set<TimelineRecord.ID>()
        var displayRecordsByID = [TimelineRecord.ID: TimelineDisplayRecord](minimumCapacity: snapshot.records.count)

        for (offset, record) in snapshot.records.enumerated() {
            if offset.isMultiple(of: 64), shouldCancel() {
                return nil
            }

            let matches = enabledFilters.filter { $0.matches(record) }
            let state = resolver.displayState(
                for: matches,
                enabledFiltersAreEmpty: enabledFiltersAreEmpty
            )
            let display = TimelineDisplayRecord(
                record: record,
                presentation: resolver.presentation(for: record, matches: matches),
                displayState: state,
                hiddenBySearch: false
            )
            displayRecordsByID[record.id] = display

            if query.isEmpty {
                guard record.timestamp >= lowerBound, state != .hidden else {
                    continue
                }
                visible.append(record)
                visibleDisplayRecords.append(display)
            } else if record.searchText.contains(query) {
                let hiddenBySearch = state == .hidden
                if hiddenBySearch {
                    hiddenSearchResults.insert(record.id)
                }
                guard record.timestamp >= lowerBound else {
                    continue
                }
                visible.append(record)
                visibleDisplayRecords.append(
                    TimelineDisplayRecord(
                        record: record,
                        presentation: display.presentation,
                        displayState: state,
                        hiddenBySearch: hiddenBySearch
                    )
                )
            }
        }

        guard !shouldCancel() else {
            return nil
        }

        let paired = zip(visible, visibleDisplayRecords)
            .sorted { lhs, rhs in lhs.0.timestamp < rhs.0.timestamp }

        return DerivedTimelineData(
            visibleRecords: paired.map(\.0),
            visibleDisplayRecords: paired.map(\.1),
            hiddenSearchResults: hiddenSearchResults,
            displayRecordsByID: displayRecordsByID
        )
    }

    public static func displayState(
        for filters: [TimelineFilterDefinition],
        enabledFiltersAreEmpty: Bool,
        filterStates: [String: CategoryDisplayState]
    ) -> CategoryDisplayState {
        TimelinePresentationResolver(filterStates: filterStates).displayState(
            for: filters,
            enabledFiltersAreEmpty: enabledFiltersAreEmpty
        )
    }

    public static func presentation(
        for record: TimelineRecord,
        matches: [TimelineFilterDefinition],
        filterStates: [String: CategoryDisplayState]
    ) -> TimelineEventPresentation {
        TimelinePresentationResolver(filterStates: filterStates).presentation(for: record, matches: matches)
    }

    public static func presentationFilter(
        for filters: [TimelineFilterDefinition],
        filterStates: [String: CategoryDisplayState]
    ) -> TimelineFilterDefinition? {
        TimelinePresentationResolver(filterStates: filterStates).presentationFilter(for: filters)
    }
}
