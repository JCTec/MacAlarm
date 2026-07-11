import AppKit

extension MacAlarmApplicationDelegate {
    func configureMainMenu() {
        let menuBuild = MacAlarmMainMenuBuilder(target: self).build()

        NSApplication.shared.mainMenu = menuBuild.menu
        showInspectorMenuItem = menuBuild.viewItems.showInspector
        inspectorAutoOpenMenuItem = menuBuild.viewItems.inspectorAutoOpen
        inspectorSummaryHeaderMenuItem = menuBuild.viewItems.inspectorSummaryHeader
        refreshInspectorMenuState()
    }
}
