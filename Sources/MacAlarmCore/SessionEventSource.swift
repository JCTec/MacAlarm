import AppKit
import Foundation

@MainActor
public final class SessionEventSource: NSObject {
    public static let screenLockedName = Notification.Name("com.apple.screenIsLocked")
    public static let screenUnlockedName = Notification.Name("com.apple.screenIsUnlocked")
    public static let selfTestName = Notification.Name("com.jctec.macalarm.selftest")

    private let handler: @MainActor @Sendable (AlarmEvent) -> Void
    private var isRunning = false

    public init(handler: @escaping @MainActor @Sendable (AlarmEvent) -> Void) {
        self.handler = handler
        super.init()
    }

    public func start() {
        guard !isRunning else {
            return
        }

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: Self.screenLockedName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: Self.screenUnlockedName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(handleDistributedNotification(_:)),
            name: Self.selfTestName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNotifications: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]

        for name in workspaceNotifications {
            workspaceCenter.addObserver(
                self,
                selector: #selector(handleWorkspaceNotification(_:)),
                name: name,
                object: nil
            )
        }

        isRunning = true
    }

    public func stop() {
        guard isRunning else {
            return
        }

        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isRunning = false
        MacAlarmLog.sources.debug("Session event observers removed")
    }

    public func postSelfTest() {
        handler(
            AlarmEvent(
                source: "session",
                name: "session.syntheticSelfTest",
                metadata: [
                    "delivery": "direct",
                    "distributedNotificationPosted": "true",
                ]
            )
        )

        DistributedNotificationCenter.default().postNotificationName(
            Self.selfTestName,
            object: nil,
            userInfo: ["reason": "session-self-test"],
            deliverImmediately: true
        )
    }

    public func currentFrontmostApplicationMetadata() -> [String: String] {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return [:]
        }

        return applicationMetadata(app)
    }

    @objc private func handleDistributedNotification(_ notification: Notification) {
        let eventName: String
        switch notification.name {
        case Self.screenLockedName:
            eventName = "screen.locked"
        case Self.screenUnlockedName:
            eventName = "screen.unlocked"
        case Self.selfTestName:
            eventName = "session.selfTest"
        default:
            eventName = notification.name.rawValue
        }

        var metadata = [
            "notification": notification.name.rawValue
        ]

        if let userInfo = notification.userInfo {
            metadata["userInfoKeys"] = userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ",")
        }

        MacAlarmLog.sources.debug("Session event mapped: \(eventName, privacy: .public)")
        handler(AlarmEvent(source: "session", name: eventName, metadata: metadata))
    }

    @objc private func handleWorkspaceNotification(_ notification: Notification) {
        let eventName: String
        switch notification.name {
        case NSWorkspace.willSleepNotification:
            eventName = "system.willSleep"
        case NSWorkspace.didWakeNotification:
            eventName = "system.didWake"
        case NSWorkspace.screensDidSleepNotification:
            eventName = "screens.didSleep"
        case NSWorkspace.screensDidWakeNotification:
            eventName = "screens.didWake"
        case NSWorkspace.didActivateApplicationNotification:
            eventName = "application.activated"
        case NSWorkspace.didLaunchApplicationNotification:
            eventName = "application.launched"
        case NSWorkspace.didTerminateApplicationNotification:
            eventName = "application.terminated"
        default:
            eventName = notification.name.rawValue
        }

        var metadata = [
            "notification": notification.name.rawValue
        ]

        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            metadata.merge(applicationMetadata(app), uniquingKeysWith: { _, new in new })
        }

        MacAlarmLog.sources.debug("Workspace event mapped: \(eventName, privacy: .public)")
        handler(AlarmEvent(source: "session", name: eventName, metadata: metadata))
    }

    private func applicationMetadata(_ app: NSRunningApplication) -> [String: String] {
        var metadata = [
            "processIdentifier": String(app.processIdentifier)
        ]

        if let localizedName = app.localizedName {
            metadata["applicationName"] = localizedName
        }

        if let bundleIdentifier = app.bundleIdentifier {
            metadata["bundleIdentifier"] = bundleIdentifier
        }

        if let executableURL = app.executableURL {
            metadata["executablePath"] = executableURL.path
        }

        return metadata
    }
}
