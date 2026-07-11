import Foundation

public struct EventProcessingResult: Codable, Equatable, Sendable {
    public var record: LedgerRecord?
    public var alarms: [Alarm]
    public var deliveries: [NotificationDelivery]
    public var errorDescription: String?

    public init(
        record: LedgerRecord?,
        alarms: [Alarm],
        deliveries: [NotificationDelivery],
        errorDescription: String? = nil
    ) {
        self.record = record
        self.alarms = alarms
        self.deliveries = deliveries
        self.errorDescription = errorDescription
    }
}

public actor EventPipeline {
    private let config: MacAlarmConfig
    private let ledger: HashChainLedger
    private let ruleEngine: RuleEngine
    private let dispatcher: AlarmDispatcher
    private let checkpointSink: any RemoteCheckpointSink
    private let anchorSink: any LedgerHashAnchorSink
    private var heartbeatCount = 0
    private var hasReportedAnchorFailure = false

    public init(
        config: MacAlarmConfig,
        ledger: HashChainLedger,
        ruleEngine: RuleEngine,
        dispatcher: AlarmDispatcher,
        checkpointSink: any RemoteCheckpointSink,
        anchorSink: any LedgerHashAnchorSink = DisabledLedgerHashAnchorSink()
    ) {
        self.config = config
        self.ledger = ledger
        self.ruleEngine = ruleEngine
        self.dispatcher = dispatcher
        self.checkpointSink = checkpointSink
        self.anchorSink = anchorSink
    }

    @discardableResult
    public func record(_ event: AlarmEvent) async -> EventProcessingResult {
        do {
            let record = try await ledger.append(event)
            let alarms = await ruleEngine.evaluate(event)
            var deliveries = [NotificationDelivery]()
            for alarm in alarms {
                let alarmDeliveries = await dispatcher.dispatch(alarm)
                deliveries.append(contentsOf: alarmDeliveries)
                for delivery in alarmDeliveries {
                    _ = try? await ledger.append(
                        AlarmEvent(
                            source: "notification",
                            name: delivery.succeeded ? "delivery.succeeded" : "delivery.failed",
                            severity: delivery.succeeded ? .info : .warning,
                            metadata: [
                                "alarmID": alarm.id.uuidString,
                                "ruleID": alarm.ruleID,
                                "channel": delivery.channel,
                                "detail": delivery.detail,
                            ]
                        )
                    )
                }
            }

            if event.source == "agent", event.name == "agent.heartbeat" {
                heartbeatCount += 1
                if shouldCheckpointHeartbeat() {
                    try await enqueueCheckpoint(reason: "heartbeat")
                }
                if shouldAnchorHeartbeat() {
                    await writeAnchorReportingFailure(reason: "heartbeat")
                }
            }

            return EventProcessingResult(record: record, alarms: alarms, deliveries: deliveries)
        } catch {
            return EventProcessingResult(
                record: nil, alarms: [], deliveries: [], errorDescription: String(describing: error))
        }
    }

    public func enqueueCheckpoint(reason: String) async throws {
        let verification = try await ledger.verify()
        let checkpoint = RemoteCheckpoint(
            deviceID: config.identity.deviceID,
            displayName: config.identity.displayName,
            ledgerPath: PathResolver.expandedPath(config.storage.ledgerPath),
            recordCount: verification.recordCount,
            lastHash: verification.lastHash,
            isLedgerValid: verification.isValid,
            reason: reason
        )
        try await checkpointSink.enqueue(checkpoint)
    }

    public func writeAnchor(reason: String) async throws {
        let verification = try await ledger.verify()
        let anchor = LedgerHashAnchor(
            deviceID: config.identity.deviceID,
            ledgerPath: PathResolver.expandedPath(config.storage.ledgerPath),
            recordCount: verification.recordCount,
            lastHash: verification.lastHash,
            isLedgerValid: verification.isValid,
            reason: reason
        )
        try await anchorSink.write(anchor)
    }

    public func writeAnchorReportingFailure(reason: String) async {
        do {
            try await writeAnchor(reason: reason)
        } catch {
            guard !hasReportedAnchorFailure else {
                return
            }
            hasReportedAnchorFailure = true
            _ = try? await ledger.append(
                AlarmEvent(
                    source: "anchor",
                    name: "anchor.write.failed",
                    severity: .warning,
                    metadata: [
                        "reason": reason,
                        "error": String(describing: error),
                    ]
                )
            )
        }
    }

    public func verifyLedger() async throws -> LedgerVerification {
        try await ledger.verify()
    }

    private func shouldCheckpointHeartbeat() -> Bool {
        guard config.remoteCheckpoint.enabled, config.heartbeat.checkpointEveryHeartbeats > 0 else {
            return false
        }

        return heartbeatCount % config.heartbeat.checkpointEveryHeartbeats == 0
    }

    private func shouldAnchorHeartbeat() -> Bool {
        guard config.hashAnchor.enabled, config.hashAnchor.anchorEveryHeartbeats > 0 else {
            return false
        }

        return heartbeatCount % config.hashAnchor.anchorEveryHeartbeats == 0
    }
}
