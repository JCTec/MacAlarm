import AppKit

struct MacAlarmMenuItemFactory {
    let target: AnyObject

    func command(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    func shiftCommand(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = command(title: title, action: action, keyEquivalent: keyEquivalent.lowercased())
        item.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
}
