import AppKit

extension MacAlarmMainMenuBuilder {
    func viewMenuItem() -> (item: NSMenuItem, viewItems: MacAlarmViewMenuItems) {
        let factory = MacAlarmMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")
        menu.delegate = target

        let showInspector = factory.command(
            title: "Show Inspector",
            action: #selector(MacAlarmApplicationDelegate.toggleInspector(_:)),
            keyEquivalent: "i"
        )
        showInspector.keyEquivalentModifierMask = [.command, .option]

        let autoOpenInspector = factory.command(
            title: "Open Inspector When Selecting Events",
            action: #selector(MacAlarmApplicationDelegate.toggleInspectorAutoOpen(_:)),
            keyEquivalent: ""
        )

        let showInspectorSummaryHeader = factory.command(
            title: "Show Pinned Event Summary",
            action: #selector(MacAlarmApplicationDelegate.toggleInspectorSummaryHeader(_:)),
            keyEquivalent: ""
        )

        menu.addItem(showInspector)
        menu.addItem(autoOpenInspector)
        menu.addItem(
            factory.command(
                title: "Show Ledger Integrity",
                action: #selector(MacAlarmApplicationDelegate.showLedgerIntegrity(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(showInspectorSummaryHeader)
        item.submenu = menu

        return (
            item,
            MacAlarmViewMenuItems(
                showInspector: showInspector,
                inspectorAutoOpen: autoOpenInspector,
                inspectorSummaryHeader: showInspectorSummaryHeader
            )
        )
    }

    func timelineMenuItem() -> NSMenuItem {
        let factory = MacAlarmMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Timeline")
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last15Minutes.menuTitle,
                action: #selector(MacAlarmApplicationDelegate.showLast15Minutes(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.lastHour.menuTitle,
                action: #selector(MacAlarmApplicationDelegate.showLastHour(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last6Hours.menuTitle,
                action: #selector(MacAlarmApplicationDelegate.showLast6Hours(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last24Hours.menuTitle,
                action: #selector(MacAlarmApplicationDelegate.showLast24Hours(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last7Days.menuTitle,
                action: #selector(MacAlarmApplicationDelegate.showLast7Days(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Zoom In",
                action: #selector(MacAlarmApplicationDelegate.zoomIn(_:)),
                keyEquivalent: "+"
            ))
        menu.addItem(
            factory.command(
                title: "Zoom Out",
                action: #selector(MacAlarmApplicationDelegate.zoomOut(_:)),
                keyEquivalent: "-"
            ))
        item.submenu = menu
        return item
    }
}
