import AppKit

struct MacAlarmMainMenuBuildResult {
    var menu: NSMenu
    var viewItems: MacAlarmViewMenuItems
}

struct MacAlarmViewMenuItems {
    var showInspector: NSMenuItem
    var inspectorAutoOpen: NSMenuItem
    var inspectorSummaryHeader: NSMenuItem
}

struct MacAlarmMainMenuBuilder {
    let target: MacAlarmApplicationDelegate

    func build() -> MacAlarmMainMenuBuildResult {
        let mainMenu = NSMenu(title: "Main Menu")
        let viewMenu = viewMenuItem()

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenu.item)
        mainMenu.addItem(timelineMenuItem())
        mainMenu.addItem(notificationsMenuItem())
        mainMenu.addItem(agentMenuItem())

        return MacAlarmMainMenuBuildResult(menu: mainMenu, viewItems: viewMenu.viewItems)
    }
}
