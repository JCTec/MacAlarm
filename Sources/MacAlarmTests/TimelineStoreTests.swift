import Foundation
import MacAlarmCore

@testable import MacAlarmAppSupport

extension MacAlarmTests {
    static func runTimelineStoreTests(_ runner: TestRunner) async {
        await runner.run("timeline store selects records and auto-opens inspector") {
            try await withIsolatedTimelineStore(inspectorAutoOpens: true) { store in
                let record = timelineRecord(
                    index: 7,
                    event: AlarmEvent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
                        observedAt: Date(timeIntervalSince1970: 7_000),
                        source: "session",
                        name: "screen.unlocked"
                    )
                )

                store.replaceRecords([record])
                store.select(record)

                try expect(store.selectedID == record.id, "selection should store the selected event ID")
                try expect(store.selectedRecord == record, "selection should resolve through the record index")
                try expect(store.inspectorVisible, "selection should auto-open the inspector when enabled")
            }
        }

        await runner.run("timeline store clears missing selected record after reload") {
            try await withIsolatedTimelineStore(inspectorAutoOpens: true) { store in
                let selected = timelineRecord(
                    index: 8,
                    event: AlarmEvent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
                        observedAt: Date(timeIntervalSince1970: 8_000),
                        source: "session",
                        name: "screen.unlocked"
                    )
                )
                let replacement = timelineRecord(
                    index: 9,
                    event: AlarmEvent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
                        observedAt: Date(timeIntervalSince1970: 8_001),
                        source: "session",
                        name: "screen.locked"
                    )
                )

                store.replaceRecords([selected])
                store.select(selected)
                store.replaceRecords([replacement])

                try expect(store.selectedID == nil, "missing selected record should be cleared")
                try expect(store.selectedRecord == nil, "missing selected record should not resolve")
                try expect(!store.inspectorVisible, "inspector should close when selection disappears")
            }
        }

        await runner.run("timeline store inspector toggle selects latest visible event") {
            try await withIsolatedTimelineStore { store in
                let first = timelineRecord(
                    index: 10,
                    event: AlarmEvent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                        observedAt: Date(timeIntervalSince1970: 9_000),
                        source: "session",
                        name: "screen.unlocked"
                    )
                )
                let latest = timelineRecord(
                    index: 11,
                    event: AlarmEvent(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                        observedAt: Date(timeIntervalSince1970: 9_001),
                        source: "session",
                        name: "application.activated",
                        metadata: ["applicationName": "Finder"]
                    )
                )

                store.replaceRecords([first, latest])
                store.applyDerivedTimelineData(
                    TimelineDerivedState.compute(
                        DerivedTimelineSnapshot(
                            records: [first, latest],
                            filters: store.timelineFilters,
                            filterStates: store.filterStates,
                            searchText: store.searchText,
                            timeRange: store.timeRange,
                            now: Date(timeIntervalSince1970: 9_002)
                        )))

                store.toggleInspector()
                try expect(store.selectedID == latest.id, "inspector toggle should select latest visible event")
                try expect(store.inspectorVisible, "inspector toggle should show the inspector")

                store.toggleInspector()
                try expect(!store.inspectorVisible, "second inspector toggle should hide the inspector")
            }
        }

        await runner.run("timeline preferences round-trip in isolated defaults suite") {
            let suiteName = "MacAlarmTests.\(UUID().uuidString)"
            let defaults = try require(UserDefaults(suiteName: suiteName), "suite should be created")
            defer {
                defaults.removePersistentDomain(forName: suiteName)
            }
            let preferences = TimelinePreferences(defaults: defaults)
            let filter = TimelineFilterDefinition(
                id: "custom.audio",
                title: "Audio",
                symbolName: "waveform",
                color: .audio,
                match: TimelineFilterMatch(source: "custom", nameContains: "audio"),
                defaultState: .spotlight,
                isEnabled: true
            )

            preferences.saveTimelineFilters([filter])
            preferences.saveFilterStates([filter.id: .hidden])
            preferences.saveInspectorAutoOpens(true)
            preferences.saveInspectorSummaryHeaderVisible(false)

            let loadedFilters = preferences.loadTimelineFilters()
            let loadedStates = preferences.loadFilterStates(filters: loadedFilters)

            try expect(loadedFilters.contains { $0.id == filter.id }, "custom filter should round-trip")
            try expect(loadedFilters.contains { $0.id == "builtin.unlock" }, "built-in templates should be merged")
            try expect(loadedStates[filter.id] == .hidden, "filter state should round-trip")
            try expect(preferences.loadInspectorAutoOpens(), "inspector auto-open preference should round-trip")
            try expect(!preferences.loadInspectorSummaryHeaderVisible(), "summary header preference should round-trip")
        }

        await runner.run("recorder health presentation classifies running, stale, and stopped states") {
            let now = Date(timeIntervalSince1970: 10_000)
            let running = AgentStatusSnapshot(
                state: .running,
                generatedAt: now.addingTimeInterval(-5),
                startedAt: now.addingTimeInterval(-60),
                processID: ProcessInfo.processInfo.processIdentifier,
                identity: AgentIdentity(deviceID: "test", displayName: "Test"),
                ledgerPath: "/tmp/events.jsonl",
                runtimeDirectory: "/tmp/runtime",
                heartbeatIntervalSeconds: 60,
                sessionEventsEnabled: true,
                applicationEventsEnabled: true,
                unifiedLogEnabled: false,
                watchedPathCount: 0,
                processedEventCount: 2,
                heartbeatCount: 1,
                latestHeartbeatAt: now.addingTimeInterval(-20)
            )

            let healthy = AgentHealthStore.presentation(snapshot: running, loadError: nil, now: now)
            try expect(healthy.level == .healthy, "fresh running recorder should be healthy")
            try expect(healthy.title == "Recorder running", "healthy title should be concise")

            var stale = running
            stale.latestHeartbeatAt = now.addingTimeInterval(-240)
            let stalePresentation = AgentHealthStore.presentation(snapshot: stale, loadError: nil, now: now)
            try expect(stalePresentation.level == .warning, "stale heartbeat should be warning")
            try expect(stalePresentation.title == "Heartbeat stale", "stale heartbeat should be named")

            var stopped = running
            stopped.processID = -1
            let stoppedPresentation = AgentHealthStore.presentation(snapshot: stopped, loadError: nil, now: now)
            try expect(stoppedPresentation.level == .critical, "missing process should be critical")
            try expect(stoppedPresentation.title == "Recorder stopped", "missing process should be named")
        }

        await runner.run("recorder health store treats missing status as normal unknown state") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let statusURL = directory.appendingPathComponent("runtime/status.json")
            let now = Date(timeIntervalSince1970: 11_000)

            try await Task { @MainActor in
                let store = AgentHealthStore(statusURL: statusURL)
                await store.refresh(now: now)

                try expect(store.snapshot == nil, "missing status should not produce a snapshot")
                try expect(store.loadError == nil, "missing status should not surface as a raw load error")
                try expect(store.lastCheckedAt == now, "missing status should still update checked time")
                try expect(store.presentation.title == "Recorder not set up", "missing status should be installable")
                try expect(
                    store.presentation.detail == "Install the recorder to start local event capture.",
                    "missing status should use user-facing empty-state text"
                )
            }.value
        }

        await runner.run("recorder health presentation hides raw status errors from pill text") {
            let presentation = AgentHealthStore.presentation(
                snapshot: nil,
                loadError: "The file status.json could not be read",
                now: Date(timeIntervalSince1970: 12_000)
            )

            try expect(presentation.level == .warning, "status load errors should be visible as a warning")
            try expect(
                presentation.title == "Recorder status unavailable",
                "status load errors should use plain product language"
            )
            try expect(
                presentation.detail == "Open details to inspect the status issue.",
                "status load errors should avoid raw filesystem text in the pill"
            )
            try expect(
                !presentation.detail.contains("status.json"),
                "raw status file details should stay out of the compact health pill"
            )
        }

        await runner.run("recorder health action content maps state to primary app action") {
            let install = try require(
                RecorderHealthActionContent.primaryAction(
                    for: AgentHealthPresentation(
                        title: "Recorder not set up",
                        detail: "Install the recorder to start local event capture.",
                        level: .unknown
                    )),
                "missing recorder should expose install action"
            )
            try expect(install.buttonTitle == "Install & Start", "missing recorder should install and start")
            try expect(install.action == .install, "missing recorder should route to install")

            let start = try require(
                RecorderHealthActionContent.primaryAction(
                    for: AgentHealthPresentation(
                        title: "Recorder stopped",
                        detail: "Start the recorder to resume local event capture.",
                        level: .critical
                    )),
                "stopped recorder should expose start action"
            )
            try expect(start.buttonTitle == "Start Recorder", "stopped recorder should start")
            try expect(start.action == .start, "stopped recorder should route to start")

            let restart = try require(
                RecorderHealthActionContent.primaryAction(
                    for: AgentHealthPresentation(
                        title: "Heartbeat stale",
                        detail: "Last heartbeat 4m ago",
                        level: .warning
                    )),
                "stale recorder should expose restart action"
            )
            try expect(restart.buttonTitle == "Start or Restart", "warning recorder should offer refresh action")
            try expect(restart.action == .start, "warning recorder should route through start path")

            let healthy = RecorderHealthActionContent.primaryAction(
                for: AgentHealthPresentation(
                    title: "Recorder running",
                    detail: "Heartbeat 5s ago",
                    level: .healthy
                ))
            try expect(healthy == nil, "healthy recorder should not show a primary action")
        }

        await runner.run("recorder setup banner copy distinguishes missing and stopped states") {
            let missing = RecorderSetupBannerContent.content(
                for: AgentHealthPresentation(
                    title: "Recorder not set up",
                    detail: "Install the recorder to start local event capture.",
                    level: .unknown
                )
            )
            try expect(missing.title == "Recorder Not Running", "missing recorder banner should stay general")
            try expect(missing.buttonTitle == "Install & Start", "missing recorder action should install")
            try expect(missing.action == .install, "missing recorder button should route to install")

            let stopped = RecorderSetupBannerContent.content(
                for: AgentHealthPresentation(
                    title: "Recorder stopped",
                    detail: "Start the recorder to resume local event capture.",
                    level: .critical
                )
            )
            try expect(stopped.title == "Recorder Stopped", "stopped recorder banner should be explicit")
            try expect(stopped.buttonTitle == "Start Recorder", "stopped recorder action should not say install")
            try expect(stopped.action == .start, "stopped recorder button should route to start")
        }
    }
}
