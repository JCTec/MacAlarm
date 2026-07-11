import AppKit
import SwiftUI

extension MacAlarmApplicationDelegate {
    func showTimelineWindow() {
        if window == nil {
            window = makeTimelineWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeTimelineWindow() -> NSWindow {
        let actions = MacAlarmAppActions(
            installAgent: { [weak self] in
                self?.installAgent(nil)
            },
            startAgent: { [weak self] in
                self?.startAgentFromBanner()
            },
            exportProofBundle: { [weak self] in
                self?.exportProofBundle(nil)
            },
            openNotificationSettings: { [weak self] in
                self?.openNotificationSettings(nil)
            }
        )
        let content = ContentView(appActions: actions)
            .environmentObject(store)
            .environmentObject(healthStore)
            .frame(minWidth: 1180, minHeight: 720)

        let window = NSWindow(
            contentRect: NSRect(x: 166, y: 90, width: 1280, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacAlarm"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 1180, height: 720)
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
        window.center()
        return window
    }
}
