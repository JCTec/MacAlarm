import Foundation
import MacAlarmCore

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

            let signpostState = MacAlarmLog.signposter.beginInterval("timelineDerivation")
            let result = await MacAlarmBackgroundTask.value(priority: .userInitiated) {
                TimelineDerivedState.computeIfNotCancelled(snapshot)
            }
            MacAlarmLog.signposter.endInterval("timelineDerivation", signpostState)

            guard let result, !Task.isCancelled else {
                MacAlarmLog.timeline.debug("Derivation cancelled or superseded; result discarded")
                return
            }

            self?.applyDerivedTimelineData(result)
        }
    }
}
