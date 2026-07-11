enum RecorderHealthAction: Equatable, Sendable {
    case install
    case start
}

struct RecorderHealthActionContent: Equatable, Sendable {
    var buttonTitle: String
    var detail: String
    var symbolName: String
    var action: RecorderHealthAction

    static func primaryAction(for presentation: AgentHealthPresentation) -> RecorderHealthActionContent? {
        switch presentation.level {
        case .healthy:
            return nil
        case .unknown:
            return RecorderHealthActionContent(
                buttonTitle: "Install & Start",
                detail: "Add MacAlarm as a visible background item.",
                symbolName: "plus.circle.fill",
                action: .install
            )
        case .critical:
            return RecorderHealthActionContent(
                buttonTitle: "Start Recorder",
                detail: "Resume event capture for this user session.",
                symbolName: "play.fill",
                action: .start
            )
        case .warning:
            return RecorderHealthActionContent(
                buttonTitle: "Start or Restart",
                detail: "Refresh the recorder if the status looks stale.",
                symbolName: "arrow.clockwise",
                action: .start
            )
        }
    }
}
