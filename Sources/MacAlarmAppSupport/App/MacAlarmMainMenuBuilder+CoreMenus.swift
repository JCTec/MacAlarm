import AppKit

extension MacAlarmMainMenuBuilder {
    func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "MacAlarm")
        menu.addItem(
            NSMenuItem(
                title: "About MacAlarm", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit MacAlarm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = menu
        return item
    }

    func fileMenuItem() -> NSMenuItem {
        let factory = MacAlarmMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.autoenablesItems = false
        let showTimeline = factory.command(
            title: "Show Timeline",
            action: #selector(MacAlarmApplicationDelegate.showTimelineMenuAction(_:)),
            keyEquivalent: "0"
        )
        showTimeline.isEnabled = true
        menu.addItem(showTimeline)
        menu.addItem(.separator())
        let exportProof = factory.shiftCommand(
            title: "Export Proof Bundle...",
            action: #selector(MacAlarmApplicationDelegate.exportProofBundle(_:)),
            keyEquivalent: "p"
        )
        exportProof.isEnabled = true
        menu.addItem(exportProof)
        item.submenu = menu
        return item
    }

    func editMenuItem() -> NSMenuItem {
        let factory = MacAlarmMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addItem(
            factory.shiftCommand(
                title: "Copy Selected Event as CSV",
                action: #selector(MacAlarmApplicationDelegate.copySelectedCSV(_:)),
                keyEquivalent: "C"
            ))
        menu.addItem(
            factory.shiftCommand(
                title: "Copy Visible Events as CSV",
                action: #selector(MacAlarmApplicationDelegate.copyVisibleCSV(_:)),
                keyEquivalent: "E"
            )
        )
        item.submenu = menu
        return item
    }
}
