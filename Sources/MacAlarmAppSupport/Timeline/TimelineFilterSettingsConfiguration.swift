struct TimelineFilterSettingsConfiguration {
    let visibleButtonCount: Int
    let filters: [TimelineFilterDefinition]
    let state: (TimelineFilterDefinition) -> CategoryDisplayState
    let setEnabled: (TimelineFilterDefinition, Bool) -> Void
    let cycle: (TimelineFilterDefinition) -> Void
    let delete: (TimelineFilterDefinition) -> Void
    let create: (TimelineFilterDefinition) -> Void
    let reset: () -> Void
}
