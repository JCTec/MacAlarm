import Foundation

extension TimelineStore {
    func scheduleDerivedTimelineUpdate() {
        let snapshot = DerivedTimelineSnapshot(
            records: records,
            filters: timelineFilters,
            filterStates: filterStates,
            searchText: searchText,
            timeRange: timeRange,
            now: Date()
        )

        derivedTimelineTask?.cancel()
        derivedTimelineTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else {
                return
            }

            let result = await MacAlarmBackgroundTask.value(priority: .userInitiated) {
                TimelineDerivedState.computeIfNotCancelled(snapshot)
            }

            guard let result, !Task.isCancelled else {
                return
            }

            self?.applyDerivedTimelineData(result)
        }
    }
}
