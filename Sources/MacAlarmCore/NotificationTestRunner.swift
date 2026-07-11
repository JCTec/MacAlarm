import Foundation

public protocol NotificationDiagnosticNotifier: AlarmNotifier {
    func authorizationSnapshot() async -> NotificationAuthorizationSnapshot
}

extension ResilientLocalNotifier: NotificationDiagnosticNotifier {}

public struct NotificationTestResult: Codable, Equatable, Sendable {
    public var before: NotificationAuthorizationSnapshot
    public var delivery: NotificationDelivery
    public var after: NotificationAuthorizationSnapshot
    public var triggerRecord: LedgerRecord?
    public var deliveryRecord: LedgerRecord?

    public init(
        before: NotificationAuthorizationSnapshot,
        delivery: NotificationDelivery,
        after: NotificationAuthorizationSnapshot,
        triggerRecord: LedgerRecord?,
        deliveryRecord: LedgerRecord?
    ) {
        self.before = before
        self.delivery = delivery
        self.after = after
        self.triggerRecord = triggerRecord
        self.deliveryRecord = deliveryRecord
    }
}

public struct NotificationTestRunner: Sendable {
    private let config: MacAlarmConfig
    private let hmacKey: Data

    public init(config: MacAlarmConfig, hmacKey: Data) throws {
        guard !hmacKey.isEmpty else {
            throw MacAlarmError.emptyHMACKey
        }

        self.config = config
        self.hmacKey = hmacKey
    }

    public func run(
        message: String = "MacAlarm notification system is working",
        origin: String = "MacAlarm notification diagnostics",
        notifier: (any NotificationDiagnosticNotifier)? = nil
    ) async throws -> NotificationTestResult {
        let notifier =
            notifier
            ?? ResilientLocalNotifier(
                soundEnabled: config.notifications.sound,
                useAppleScriptFallback: config.notifications.appleScriptFallback
            )
        let alarm = Self.testAlarm(message: message, origin: origin)
        let ledger = try HashChainLedger(
            fileURL: PathResolver.fileURL(config.storage.ledgerPath),
            hmacKey: hmacKey
        )

        let before = await notifier.authorizationSnapshot()
        let triggerRecord = try await ledger.append(alarm.event)
        let delivery = await send(alarm, through: notifier)
        let deliveryRecord = try await ledger.append(Self.deliveryEvent(for: delivery, alarm: alarm))
        let after = await notifier.authorizationSnapshot()

        return NotificationTestResult(
            before: before,
            delivery: delivery,
            after: after,
            triggerRecord: triggerRecord,
            deliveryRecord: deliveryRecord
        )
    }

    public static func testAlarm(message: String, origin: String) -> Alarm {
        let event = AlarmEvent(
            source: "manual",
            name: "notification.test",
            severity: .notice,
            metadata: ["command": origin]
        )
        return Alarm(
            ruleID: "manual-notification-test",
            severity: .critical,
            message: message,
            event: event
        )
    }

    public static func deliveryEvent(for delivery: NotificationDelivery, alarm: Alarm) -> AlarmEvent {
        AlarmEvent(
            source: "notification",
            name: delivery.succeeded ? "delivery.succeeded" : "delivery.failed",
            severity: delivery.succeeded ? .info : .warning,
            metadata: [
                "alarmID": alarm.id.uuidString,
                "ruleID": alarm.ruleID,
                "channel": delivery.channel,
                "detail": delivery.detail,
                "triggerEventID": alarm.event.id.uuidString,
            ]
        )
    }

    private func send(_ alarm: Alarm, through notifier: any NotificationDiagnosticNotifier) async
        -> NotificationDelivery
    {
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
