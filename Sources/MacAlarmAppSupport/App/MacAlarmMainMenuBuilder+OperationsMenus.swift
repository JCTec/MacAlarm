import AppKit

extension MacAlarmMainMenuBuilder {
    func notificationsMenuItem() -> NSMenuItem {
        let factory = MacAlarmMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Notifications")
        menu.autoenablesItems = false
        menu.addItem(
            factory.command(
                title: "Notification Status",
                action: #selector(MacAlarmApplicationDelegate.showNotificationDiagnostics(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Enable Notifications...",
                action: #selector(MacAlarmApplicationDelegate.enableNotifications(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Send Test Notification",
                action: #selector(MacAlarmApplicationDelegate.sendTestNotification(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Open System Notification Settings",
                action: #selector(MacAlarmApplicationDelegate.openNotificationSettings(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Telegram Settings...",
                action: #selector(MacAlarmApplicationDelegate.showTelegramSettings(_:))
            )
        )
        item.submenu = menu
        return item
    }

    func agentMenuItem() -> NSMenuItem {
        let factory = MacAlarmMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Recorder")
        menu.addItem(
            factory.command(
                title: "Install Recorder at Login...",
                action: #selector(MacAlarmApplicationDelegate.installAgent(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Show Recorder Status",
                action: #selector(MacAlarmApplicationDelegate.showAgentStatus(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Start or Restart Recorder",
                action: #selector(MacAlarmApplicationDelegate.restartAgent(_:))
            ))
        menu.addItem(
            factory.command(title: "Stop Recorder", action: #selector(MacAlarmApplicationDelegate.stopAgent(_:))))
        menu.addItem(
            factory.command(
                title: "Uninstall Recorder...",
                action: #selector(MacAlarmApplicationDelegate.uninstallAgent(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Open Recorder Logs",
                action: #selector(MacAlarmApplicationDelegate.openAgentLogs(_:))
            ))
        menu.addItem(
            factory.command(title: "Reveal Ledger", action: #selector(MacAlarmApplicationDelegate.revealLedger(_:))))
        item.submenu = menu
        return item
    }
}
