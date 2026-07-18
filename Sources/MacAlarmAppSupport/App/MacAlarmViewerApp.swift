import AppKit

@MainActor
public enum MacAlarmViewerApplication {
    private static var delegate: MacAlarmApplicationDelegate?

    public static func main() {
        let app = NSApplication.shared
        let delegate = MacAlarmApplicationDelegate()
        Self.delegate = delegate

        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class MacAlarmApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = TimelineStore()
    let healthStore = AgentHealthStore()
    var window: NSWindow?
    var showInspectorMenuItem: NSMenuItem?
    var inspectorAutoOpenMenuItem: NSMenuItem?
    var inspectorSummaryHeaderMenuItem: NSMenuItem?

    let launchAgentLabel = "com.jctec.macalarm.agent"

    var agentInstaller: MacAlarmAgentInstaller {
        MacAlarmAgentInstaller(launchAgentLabel: launchAgentLabel)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureNotificationPresentation()
        configureMainMenu()
        store.start()
        healthStore.start()
        showTimelineWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthStore.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showTimelineWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshInspectorMenuState()
    }
}
