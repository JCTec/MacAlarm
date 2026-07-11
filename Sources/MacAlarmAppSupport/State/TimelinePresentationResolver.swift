struct TimelinePresentationResolver: Sendable {
    var filterStates: [String: CategoryDisplayState]

    func displayState(
        for filters: [TimelineFilterDefinition],
        enabledFiltersAreEmpty: Bool
    ) -> CategoryDisplayState {
        guard !enabledFiltersAreEmpty else {
            return .normal
        }
        guard !filters.isEmpty else {
            return .hidden
        }

        if filters.contains(where: { state(for: $0) == .spotlight }) {
            return .spotlight
        }
        if filters.contains(where: { state(for: $0) == .normal }) {
            return .normal
        }
        return .hidden
    }

    func presentation(
        for record: TimelineRecord,
        matches: [TimelineFilterDefinition]
    ) -> TimelineEventPresentation {
        if let filter = presentationFilter(for: matches) {
            return TimelineEventPresentation(
                title: filter.title,
                symbolName: filter.symbolName,
                color: filter.color
            )
        }

        return TimelineEventPresentation(
            title: record.category.title,
            symbolName: record.category.symbolName,
            color: record.category.presentationColor
        )
    }

    func presentationFilter(for filters: [TimelineFilterDefinition]) -> TimelineFilterDefinition? {
        filters.first { state(for: $0) == .spotlight }
            ?? filters.first { state(for: $0) == .normal }
            ?? filters.first
    }

    private func state(for filter: TimelineFilterDefinition) -> CategoryDisplayState {
        filterStates[filter.id, default: filter.defaultState]
    }
}
