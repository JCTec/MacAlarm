import AppKit

enum MacAlarmSystemSettings {
    static let backgroundItemsURLs = [
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension?BackgroundItems"),
    ].compactMap { $0 }

    static let notificationURLs = [
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
        URL(string: "x-apple.systempreferences:com.apple.preference.notifications"),
    ].compactMap { $0 }

    @MainActor
    @discardableResult
    static func openBackgroundItems(workspace: NSWorkspace = .shared) -> Bool {
        open(urls: backgroundItemsURLs, workspace: workspace)
    }

    @MainActor
    @discardableResult
    static func openNotifications(workspace: NSWorkspace = .shared) -> Bool {
        open(urls: notificationURLs, workspace: workspace)
    }

    @MainActor
    @discardableResult
    private static func open(urls: [URL], workspace: NSWorkspace) -> Bool {
        for url in urls where workspace.open(url) {
            return true
        }

        return workspace.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
