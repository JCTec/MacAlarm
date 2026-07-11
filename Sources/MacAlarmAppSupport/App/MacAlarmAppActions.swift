struct MacAlarmAppActions: Sendable {
    let installAgent: @MainActor @Sendable () -> Void
    let startAgent: @MainActor @Sendable () -> Void
    let exportProofBundle: @MainActor @Sendable () -> Void
    let openNotificationSettings: @MainActor @Sendable () -> Void

    static let disabled = MacAlarmAppActions(
        installAgent: {},
        startAgent: {},
        exportProofBundle: {},
        openNotificationSettings: {}
    )
}
