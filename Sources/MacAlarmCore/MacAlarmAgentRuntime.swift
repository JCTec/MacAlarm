import Foundation

@MainActor
public final class MacAlarmAgentRuntime {
    private let config: MacAlarmConfig
    private let pipeline: EventPipeline
    private let statusStore: AgentStatusStore
    private var sessionEventSource: SessionEventSource?
    private var fileEventSources = [FileEventSource]()
    private var heartbeatTask: Task<Void, Never>?
    private var unifiedLogTask: Task<Void, Never>?
    private var telegramPollingTask: Task<Void, Never>?
    private var isRunning = false

    public init(config: MacAlarmConfig, hmacKey: Data) throws {
        self.config = config

        let ledger = try HashChainLedger(
            fileURL: PathResolver.fileURL(config.storage.ledgerPath),
            hmacKey: hmacKey,
            maxFileBytes: config.storage.maxLedgerFileBytes
        )
        let ruleEngine = RuleEngine(rules: config.rules)
        let dispatcher = AlarmDispatcher(notifiers: Self.makeNotifiers(config))
        let checkpointSink: any RemoteCheckpointSink =
            config.remoteCheckpoint.enabled
            ? OutboxRemoteCheckpointSink(
                directory: PathResolver.fileURL(config.storage.outboxDirectory),
                endpointURL: config.remoteCheckpoint.endpointURL
            )
            : DisabledRemoteCheckpointSink()
        let anchorSink: any LedgerHashAnchorSink =
            config.hashAnchor.enabled
            ? FileLedgerHashAnchorSink(directory: PathResolver.fileURL(config.hashAnchor.directory))
            : DisabledLedgerHashAnchorSink()

        self.pipeline = EventPipeline(
            config: config,
            ledger: ledger,
            ruleEngine: ruleEngine,
            dispatcher: dispatcher,
            checkpointSink: checkpointSink,
            anchorSink: anchorSink
        )
        self.statusStore = AgentStatusStore(config: config)
    }

    public func run(duration: TimeInterval? = nil) async throws {
        try await start()

        let deadline = duration.map { Date().addingTimeInterval($0) }
        while !Task.isCancelled {
            if let deadline, Date() >= deadline {
                break
            }

            pumpMainRunLoopOnce()
            try? await Task.sleep(for: .milliseconds(50))
        }

        await stop()
    }

    public func start() async throws {
        guard !isRunning else {
            return
        }

        try FileManager.default.createDirectory(
            at: PathResolver.fileURL(config.storage.runtimeDirectory),
            withIntermediateDirectories: true
        )

        isRunning = true
        await statusStore.markRunning()
        await recordAgentEvent(
            AlarmEvent(
                source: "agent",
                name: "agent.started",
                severity: .notice,
                metadata: [
                    "schemaVersion": String(config.schemaVersion),
                    "pid": String(ProcessInfo.processInfo.processIdentifier),
                ]
            ),
            pipeline: pipeline,
            statusStore: statusStore
        )

        if config.session.enabled {
            startSessionEvents()
        }

        startFileEvents()

        if config.heartbeat.enabled {
            startHeartbeat()
        }

        if config.unifiedLog.enabled {
            startUnifiedLogPolling()
        }

        if config.telegram.enabled && config.telegram.pollingEnabled {
            startTelegramPolling()
        }

        if config.remoteCheckpoint.enabled {
            try await pipeline.enqueueCheckpoint(reason: "agent-started")
        }

        if config.hashAnchor.enabled {
            await pipeline.writeAnchorReportingFailure(reason: "agent-started")
        }
    }

    public func stop() async {
        guard isRunning else {
            return
        }

        sessionEventSource?.stop()
        sessionEventSource = nil

        for source in fileEventSources {
            source.stop()
        }
        fileEventSources.removeAll()

        heartbeatTask?.cancel()
        heartbeatTask = nil

        unifiedLogTask?.cancel()
        unifiedLogTask = nil

        telegramPollingTask?.cancel()
        telegramPollingTask = nil

        await statusStore.markStopping()
        await recordAgentEvent(
            AlarmEvent(source: "agent", name: "agent.stopped", severity: .notice),
            pipeline: pipeline,
            statusStore: statusStore
        )
        if config.remoteCheckpoint.enabled {
            try? await pipeline.enqueueCheckpoint(reason: "agent-stopped")
        }
        if config.hashAnchor.enabled {
            await pipeline.writeAnchorReportingFailure(reason: "agent-stopped")
        }

        isRunning = false
        await statusStore.markStopped()
    }

    public func verifyLedger() async throws -> LedgerVerification {
        try await pipeline.verifyLedger()
    }

    private func startSessionEvents() {
        let source = SessionEventSource { [pipeline, statusStore] event in
            Task {
                await recordAgentEvent(event, pipeline: pipeline, statusStore: statusStore)
            }
        }
        sessionEventSource = source
        source.start()
    }

    private func startFileEvents() {
        for watchedPath in config.filesystem.watchedPaths {
            let expandedPath = PathResolver.expandedPath(watchedPath.path)
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                if watchedPath.required {
                    Task { [pipeline, statusStore] in
                        await recordAgentEvent(
                            AlarmEvent(
                                source: "filesystem",
                                name: "watch.missing",
                                severity: .warning,
                                metadata: [
                                    "label": watchedPath.label,
                                    "path": expandedPath,
                                ]
                            ),
                            pipeline: pipeline,
                            statusStore: statusStore
                        )
                    }
                }
                continue
            }

            let source = FileEventSource(path: expandedPath)
            do {
                try source.start { [pipeline, statusStore, label = watchedPath.label] fileEvent in
                    var event = fileEvent.alarmEvent
                    event.metadata["label"] = label
                    Task {
                        await recordAgentEvent(event, pipeline: pipeline, statusStore: statusStore)
                    }
                }
                fileEventSources.append(source)
            } catch {
                Task { [pipeline, statusStore] in
                    await recordAgentEvent(
                        AlarmEvent(
                            source: "filesystem",
                            name: "watch.failed",
                            severity: .warning,
                            metadata: [
                                "label": watchedPath.label,
                                "path": expandedPath,
                                "error": String(describing: error),
                            ]
                        ),
                        pipeline: pipeline,
                        statusStore: statusStore
                    )
                }
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [pipeline, statusStore, interval = config.heartbeat.intervalSeconds] in
            while !Task.isCancelled {
                await recordAgentEvent(
                    AlarmEvent(
                        source: "agent",
                        name: "agent.heartbeat",
                        metadata: ["pid": String(ProcessInfo.processInfo.processIdentifier)]
                    ),
                    pipeline: pipeline,
                    statusStore: statusStore
                )
                try? await Task.sleep(for: .milliseconds(Int(interval * 1_000)))
            }
        }
    }

    private func startUnifiedLogPolling() {
        unifiedLogTask = Task { [pipeline, statusStore, config = config.unifiedLog] in
            let reader = UnifiedLogReader()
            var seenFingerprintsByQuery = [String: Set<String>]()
            while !Task.isCancelled {
                for template in config.queries {
                    let query = UnifiedLogQuery(
                        scope: template.scope,
                        since: Date().addingTimeInterval(-template.lookbackSeconds),
                        predicateFormat: template.predicateFormat,
                        limit: template.limit
                    )
                    do {
                        let events = try reader.readEvents(query: query)
                        for var event in events {
                            let fingerprint = Self.unifiedLogFingerprint(event, queryName: template.name)
                            if seenFingerprintsByQuery[template.name, default: []].contains(fingerprint) {
                                continue
                            }
                            seenFingerprintsByQuery[template.name, default: []].insert(fingerprint)
                            event.metadata["query"] = template.name
                            await recordAgentEvent(event, pipeline: pipeline, statusStore: statusStore)
                        }
                        seenFingerprintsByQuery[template.name] = Self.trimmedFingerprints(
                            seenFingerprintsByQuery[template.name, default: []],
                            limit: max(template.limit * 4, 128)
                        )
                    } catch {
                        await recordAgentEvent(
                            AlarmEvent(
                                source: "unifiedLog",
                                name: "poll.failed",
                                severity: .warning,
                                metadata: [
                                    "query": template.name,
                                    "error": String(describing: error),
                                ]
                            ),
                            pipeline: pipeline,
                            statusStore: statusStore
                        )
                    }
                }

                try? await Task.sleep(for: .milliseconds(Int(config.pollIntervalSeconds * 1_000)))
            }
        }
    }

    private func startTelegramPolling() {
        telegramPollingTask = Task { [config, statusStore, pipeline] in
            do {
                let secretStore = FileSecretStore.installedStore(for: config)
                guard let tokenData = try secretStore.readSecret(account: config.telegram.botTokenAccount),
                    let token = String(data: tokenData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !token.isEmpty
                else {
                    await recordAgentEvent(
                        AlarmEvent(source: "telegram", name: "token.missing", severity: .warning),
                        pipeline: pipeline,
                        statusStore: statusStore
                    )
                    return
                }

                let poller = TelegramCommandPoller(
                    client: TelegramClient(token: token),
                    config: config,
                    pendingStore: .installedStore(config: config)
                )
                while !Task.isCancelled {
                    do {
                        try await poller.pollOnce()
                    } catch {
                        await recordAgentEvent(
                            AlarmEvent(
                                source: "telegram",
                                name: "poll.failed",
                                severity: .warning,
                                metadata: ["error": String(describing: error)]
                            ),
                            pipeline: pipeline,
                            statusStore: statusStore
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(Int(config.telegram.pollingIntervalSeconds * 1_000)))
                }
            } catch {
                await recordAgentEvent(
                    AlarmEvent(
                        source: "telegram",
                        name: "poll.setup.failed",
                        severity: .warning,
                        metadata: ["error": String(describing: error)]
                    ),
                    pipeline: pipeline,
                    statusStore: statusStore
                )
            }
        }
    }

    private static func unifiedLogFingerprint(_ event: AlarmEvent, queryName: String) -> String {
        [
            queryName,
            String(format: "%.6f", event.observedAt.timeIntervalSince1970),
            event.source,
            event.name,
            event.severity.rawValue,
            event.metadata["logSubsystem"] ?? event.metadata["subsystem"] ?? "",
            event.metadata["logCategory"] ?? event.metadata["category"] ?? "",
            event.metadata["logProcess"] ?? event.metadata["process"] ?? "",
            event.metadata["logSender"] ?? event.metadata["sender"] ?? "",
            event.metadata["logComposedMessage"] ?? event.metadata["composedMessage"] ?? event.metadata["message"]
                ?? "",
        ].joined(separator: "\u{1f}")
    }

    private static func trimmedFingerprints(_ fingerprints: Set<String>, limit: Int) -> Set<String> {
        guard fingerprints.count > limit else {
            return fingerprints
        }

        return Set(fingerprints.suffix(limit))
    }

    private static func makeNotifiers(_ config: MacAlarmConfig) -> [any AlarmNotifier] {
        var notifiers = [any AlarmNotifier]()
        if config.notifications.console {
            notifiers.append(ConsoleNotifier())
        }
        if config.notifications.localNotification {
            notifiers.append(
                ResilientLocalNotifier(
                    soundEnabled: config.notifications.sound,
                    useAppleScriptFallback: config.notifications.appleScriptFallback
                )
            )
        }
        if config.telegram.enabled,
            let tokenData = try? FileSecretStore.installedStore(for: config)
                .readSecret(account: config.telegram.botTokenAccount),
            let token = String(data: tokenData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        {
            notifiers.append(TelegramNotifier(client: TelegramClient(token: token), config: config.telegram))
        }
        return notifiers
    }
}

private func recordAgentEvent(
    _ event: AlarmEvent,
    pipeline: EventPipeline,
    statusStore: AgentStatusStore
) async {
    let result = await pipeline.record(event)
    await statusStore.record(event: event, result: result)
}

@MainActor
private func pumpMainRunLoopOnce() {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
}
