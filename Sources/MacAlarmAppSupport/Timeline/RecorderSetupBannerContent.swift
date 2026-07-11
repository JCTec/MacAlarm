enum RecorderSetupBannerAction: Equatable, Sendable {
    case install
    case start
}

struct RecorderSetupBannerContent: Equatable, Sendable {
    var title: String
    var detail: String
    var buttonTitle: String
    var help: String
    var action: RecorderSetupBannerAction

    static func content(for presentation: AgentHealthPresentation) -> RecorderSetupBannerContent {
        if presentation.level == .critical {
            return RecorderSetupBannerContent(
                title: "Recorder Stopped",
                detail: "Start the background recorder so MacAlarm keeps writing events after the app closes.",
                buttonTitle: "Start Recorder",
                help: "Start the MacAlarm background recorder.",
                action: .start
            )
        }

        return RecorderSetupBannerContent(
            title: "Recorder Not Running",
            detail: "Install the visible macOS background recorder. No admin password or Keychain prompt is required.",
            buttonTitle: "Install & Start",
            help: "Install and start the MacAlarm background recorder.",
            action: .install
        )
    }
}
