import Foundation

extension TimelineStore {
    func cycle(_ filter: TimelineFilterDefinition) {
        var state = filterStates[filter.id, default: filter.defaultState]
        state.advance()
        filterStates[filter.id] = state
    }

    func displayState(for record: TimelineRecord) -> CategoryDisplayState {
        if let cached = displayRecordsByID[record.id] {
            return cached.displayState
        }

        return TimelineDerivedState.displayState(
            for: matchingEnabledFilters(for: record),
            enabledFiltersAreEmpty: enabledFilters.isEmpty,
            filterStates: filterStates
        )
    }

    func presentation(for record: TimelineRecord) -> TimelineEventPresentation {
        if let cached = displayRecordsByID[record.id] {
            return cached.presentation
        }

        return TimelineDerivedState.presentation(
            for: record,
            matches: matchingEnabledFilters(for: record),
            filterStates: filterStates
        )
    }

    func matchingEnabledFilters(for record: TimelineRecord) -> [TimelineFilterDefinition] {
        enabledFilters.filter { $0.matches(record) }
    }

    func filterState(for filter: TimelineFilterDefinition) -> CategoryDisplayState {
        filterStates[filter.id, default: filter.defaultState]
    }

    func setFilterEnabled(_ filter: TimelineFilterDefinition, enabled: Bool) {
        guard let index = timelineFilters.firstIndex(where: { $0.id == filter.id }) else { return }
        timelineFilters[index].isEnabled = enabled
    }

    func addFilter(_ filter: TimelineFilterDefinition) {
        timelineFilters.append(filter)
        filterStates[filter.id] = filter.defaultState
    }

    func deleteFilter(_ filter: TimelineFilterDefinition) {
        guard !filter.isBuiltIn else { return }
        timelineFilters.removeAll { $0.id == filter.id }
        filterStates.removeValue(forKey: filter.id)
    }

    func resetFiltersToDefaults() {
        timelineFilters = TimelineFilterDefinition.defaultTemplates
        filterStates = Dictionary(uniqueKeysWithValues: timelineFilters.map { ($0.id, $0.defaultState) })
    }
}
