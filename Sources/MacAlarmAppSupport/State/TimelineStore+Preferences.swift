import Foundation

extension TimelineStore {
    func scheduleTimelineFiltersSave() {
        let filters = timelineFilters
        timelineFiltersSaveTask?.cancel()
        timelineFiltersSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }

            let data = await MacAlarmBackgroundTask.value(priority: .utility) {
                TimelinePreferences.encodedTimelineFilters(filters)
            }

            guard !Task.isCancelled, let data else {
                return
            }

            self?.preferences.saveTimelineFiltersData(data)
        }
    }

    func scheduleFilterStatesSave() {
        let states = filterStates
        filterStatesSaveTask?.cancel()
        filterStatesSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }

            let data = await MacAlarmBackgroundTask.value(priority: .utility) {
                TimelinePreferences.encodedFilterStates(states)
            }

            guard !Task.isCancelled, let data else {
                return
            }

            self?.preferences.saveFilterStatesData(data)
        }
    }
}
