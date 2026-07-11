import Foundation

public struct TimelinePreferences {
    public var defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadTimelineFilters() -> [TimelineFilterDefinition] {
        guard let data = defaults.data(forKey: Self.timelineFiltersKey),
            let decoded = try? JSONDecoder().decode([TimelineFilterDefinition].self, from: data)
        else {
            return TimelineFilterDefinition.defaultTemplates
        }

        return Self.mergeWithDefaultTemplates(decoded)
    }

    public func loadFilterStates(filters: [TimelineFilterDefinition]) -> [String: CategoryDisplayState] {
        let decoded: [String: CategoryDisplayState]
        if let data = defaults.data(forKey: Self.filterStatesKey),
            let stored = try? JSONDecoder().decode([String: CategoryDisplayState].self, from: data)
        {
            decoded = stored
        } else {
            decoded = [:]
        }

        return Dictionary(
            uniqueKeysWithValues: filters.map { filter in
                (filter.id, decoded[filter.id] ?? filter.defaultState)
            })
    }

    public func loadInspectorAutoOpens() -> Bool {
        defaults.object(forKey: Self.inspectorAutoOpensKey) as? Bool ?? false
    }

    public func loadInspectorSummaryHeaderVisible() -> Bool {
        defaults.object(forKey: Self.inspectorSummaryHeaderVisibleKey) as? Bool ?? true
    }

    public func saveInspectorAutoOpens(_ value: Bool) {
        defaults.set(value, forKey: Self.inspectorAutoOpensKey)
    }

    public func saveInspectorSummaryHeaderVisible(_ value: Bool) {
        defaults.set(value, forKey: Self.inspectorSummaryHeaderVisibleKey)
    }

    public func saveTimelineFilters(_ filters: [TimelineFilterDefinition]) {
        guard let data = Self.encodedTimelineFilters(filters) else {
            return
        }
        saveTimelineFiltersData(data)
    }

    public func saveFilterStates(_ states: [String: CategoryDisplayState]) {
        guard let data = Self.encodedFilterStates(states) else {
            return
        }
        saveFilterStatesData(data)
    }

    func saveTimelineFiltersData(_ data: Data) {
        defaults.set(data, forKey: Self.timelineFiltersKey)
    }

    func saveFilterStatesData(_ data: Data) {
        defaults.set(data, forKey: Self.filterStatesKey)
    }

    static func encodedTimelineFilters(_ filters: [TimelineFilterDefinition]) -> Data? {
        try? JSONEncoder().encode(filters)
    }

    static func encodedFilterStates(_ states: [String: CategoryDisplayState]) -> Data? {
        try? JSONEncoder().encode(states)
    }

    public static func mergeWithDefaultTemplates(_ filters: [TimelineFilterDefinition]) -> [TimelineFilterDefinition] {
        var merged = filters
        let existingIDs = Set(filters.map(\.id))
        for template in TimelineFilterDefinition.defaultTemplates where !existingIDs.contains(template.id) {
            merged.append(template)
        }
        return merged.filter { filter in
            filter.id != "builtin.other" && filter.id != "builtin.custom"
        }
    }

    private static let inspectorAutoOpensKey = "MacAlarm.inspectorAutoOpens"
    private static let inspectorSummaryHeaderVisibleKey = "MacAlarm.inspectorSummaryHeaderVisible"
    private static let timelineFiltersKey = "MacAlarm.timelineFilters"
    private static let filterStatesKey = "MacAlarm.filterStates"
}
