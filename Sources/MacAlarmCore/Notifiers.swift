import Foundation
import UserNotifications

public struct NotificationDelivery: Codable, Equatable, Sendable {
    public var channel: String
    public var succeeded: Bool
    public var detail: String

    public init(channel: String, succeeded: Bool, detail: String) {
        self.channel = channel
        self.succeeded = succeeded
        self.detail = detail
    }
}

public protocol AlarmNotifier: Sendable {
    var channel: String { get }
    func send(_ alarm: Alarm) async throws -> NotificationDelivery
}

public struct NotificationAuthorizationSnapshot: Codable, Equatable, Sendable {
    public var authorizationStatus: String
    public var alertSetting: String
    public var soundSetting: String
    public var badgeSetting: String

    public init(
        authorizationStatus: String,
        alertSetting: String,
        soundSetting: String,
        badgeSetting: String
    ) {
        self.authorizationStatus = authorizationStatus
        self.alertSetting = alertSetting
        self.soundSetting = soundSetting
        self.badgeSetting = badgeSetting
    }
}

public enum NotificationEnvironment {
    public static var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

public struct ConsoleNotifier: AlarmNotifier {
    public let channel = "console"

    public init() {}

    public func send(_ alarm: Alarm) async throws -> NotificationDelivery {
        let data = try CanonicalJSON.encodeLine(alarm)
        FileHandle.standardOutput.write(data)
        return NotificationDelivery(channel: channel, succeeded: true, detail: "wrote alarm JSON to stdout")
    }
}

public actor LocalNotificationNotifier: AlarmNotifier {
    public nonisolated let channel = "user-notifications"
    private let notificationCenter: UNUserNotificationCenter
    private let soundEnabled: Bool

    public init(notificationCenter: UNUserNotificationCenter = .current(), soundEnabled: Bool = true) {
        self.notificationCenter = notificationCenter
        self.soundEnabled = soundEnabled
    }

    public func authorizationSnapshot() async -> NotificationAuthorizationSnapshot {
        let settings = await notificationCenter.notificationSettings()
        return NotificationAuthorizationSnapshot(
            authorizationStatus: String(describing: settings.authorizationStatus),
            alertSetting: String(describing: settings.alertSetting),
            soundSetting: String(describing: settings.soundSetting),
            badgeSetting: String(describing: settings.badgeSetting)
        )
    }

    /// Explicitly ask macOS for notification permission. Registers this app in
    /// System Settings > Notifications so the user can opt in.
    public func requestAuthorization() async throws -> Bool {
        try await notificationCenter.requestAuthorization(options: [.alert, .sound])
    }

    public func send(_ alarm: Alarm) async throws -> NotificationDelivery {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            return NotificationDelivery(channel: channel, succeeded: false, detail: "notification authorization denied")
        }

        let content = UNMutableNotificationContent()
        content.title = alarm.severity.rawValue.uppercased()
        content.body = alarm.message
        content.subtitle = "\(alarm.event.source): \(alarm.event.name)"
        content.threadIdentifier = "com.jctec.macalarm.\(alarm.ruleID)"
        content.userInfo = [
            "alarmID": alarm.id.uuidString,
            "ruleID": alarm.ruleID,
            "eventID": alarm.event.id.uuidString,
        ]
        if soundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: nil
        )
        try await notificationCenter.add(request)
        return NotificationDelivery(channel: channel, succeeded: true, detail: "local notification queued")
    }
}

public struct AppleScriptNotificationNotifier: AlarmNotifier {
    public let channel = "applescript-notification"
    private let soundEnabled: Bool

    public init(soundEnabled: Bool = true) {
        self.soundEnabled = soundEnabled
    }

    public func send(_ alarm: Alarm) async throws -> NotificationDelivery {
        let title = "MacAlarm \(alarm.severity.rawValue.uppercased())"
        let subtitle = "\(alarm.event.source): \(alarm.event.name)"
        let message = alarm.message
        let soundClause = soundEnabled ? " sound name \"Glass\"" : ""
        let script =
            "display notification \(message.appleScriptLiteral) with title \(title.appleScriptLiteral) subtitle \(subtitle.appleScriptLiteral)\(soundClause)"

        return try await Task.detached(priority: .utility) {
            try Self.runAppleScript(script: script, channel: channel)
        }.value
    }

    private static func runAppleScript(script: String, channel: String) throws -> NotificationDelivery {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return NotificationDelivery(channel: channel, succeeded: true, detail: "display notification executed")
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? "osascript failed"
        return NotificationDelivery(
            channel: channel, succeeded: false, detail: errorText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Outcome of a user-initiated request to enable local notifications.
public enum LocalNotificationAuthorization: Equatable, Sendable {
    case granted
    case denied
    case unavailable(String)
}

public actor ResilientLocalNotifier: AlarmNotifier {
    public nonisolated let channel = "local-notification"
    private let primary: LocalNotificationNotifier?
    private let fallback: AppleScriptNotificationNotifier?

    public init(soundEnabled: Bool = true, useAppleScriptFallback: Bool = true) {
        self.primary =
            NotificationEnvironment.canUseUserNotifications
            ? LocalNotificationNotifier(soundEnabled: soundEnabled)
            : nil
        self.fallback = useAppleScriptFallback ? AppleScriptNotificationNotifier(soundEnabled: soundEnabled) : nil
    }

    /// Ask macOS to authorize local notifications for this process. Only the
    /// user-facing notification path (UNUserNotifications) supports opt-in; when
    /// this process is not a bundled app the request is unavailable.
    public func requestAuthorization() async -> LocalNotificationAuthorization {
        guard let primary else {
            return .unavailable("Local notifications require the packaged MacAlarm app bundle.")
        }

        do {
            return try await primary.requestAuthorization() ? .granted : .denied
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func authorizationSnapshot() async -> NotificationAuthorizationSnapshot {
        guard let primary else {
            return NotificationAuthorizationSnapshot(
                authorizationStatus: "unavailable-unbundled-executable",
                alertSetting: "unavailable",
                soundSetting: "unavailable",
                badgeSetting: "unavailable"
            )
        }

        return await primary.authorizationSnapshot()
    }

    public func send(_ alarm: Alarm) async throws -> NotificationDelivery {
        if let primary {
            let primaryResult = try await primary.send(alarm)
            if primaryResult.succeeded || fallback == nil {
                return NotificationDelivery(
                    channel: channel,
                    succeeded: primaryResult.succeeded,
                    detail: "\(primary.channel): \(primaryResult.detail)"
                )
            }

            let fallbackResult = try await fallback!.send(alarm)
            return NotificationDelivery(
                channel: channel,
                succeeded: fallbackResult.succeeded,
                detail:
                    "\(primary.channel): \(primaryResult.detail); \(fallbackResult.channel): \(fallbackResult.detail)"
            )
        }

        guard let fallback else {
            return NotificationDelivery(
                channel: channel,
                succeeded: false,
                detail: "UserNotifications unavailable for unbundled executable and AppleScript fallback disabled"
            )
        }

        let fallbackResult = try await fallback.send(alarm)
        return NotificationDelivery(
            channel: channel,
            succeeded: fallbackResult.succeeded,
            detail: "\(fallbackResult.channel): \(fallbackResult.detail)"
        )
    }
}

public actor AlarmDispatcher {
    private let notifiers: [any AlarmNotifier]

    public init(notifiers: [any AlarmNotifier]) {
        self.notifiers = notifiers
    }

    public func dispatch(_ alarm: Alarm) async -> [NotificationDelivery] {
        await withTaskGroup(of: NotificationDelivery.self) { group in
            for notifier in notifiers {
                group.addTask {
                    do {
                        return try await notifier.send(alarm)
                    } catch {
                        return NotificationDelivery(
                            channel: notifier.channel,
                            succeeded: false,
                            detail: String(describing: error)
                        )
                    }
                }
            }

            var deliveries = [NotificationDelivery]()
            for await delivery in group {
                if delivery.succeeded {
                    MacAlarmLog.notify.debug(
                        "Delivery succeeded via \(delivery.channel, privacy: .public)")
                } else {
                    MacAlarmLog.notify.error(
                        """
                        Delivery failed via \(delivery.channel, privacy: .public): \
                        \(delivery.detail, privacy: .public)
                        """)
                }
                deliveries.append(delivery)
            }
            return deliveries.sorted { $0.channel < $1.channel }
        }
    }
}

private extension String {
    var appleScriptLiteral: String {
        "\"" + replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
