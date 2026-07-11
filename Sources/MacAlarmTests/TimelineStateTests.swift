import Foundation
import MacAlarmCore

@testable import MacAlarmAppSupport

extension MacAlarmTests {
    static func runTimelineStateTests(_ runner: TestRunner) async {
        await runner.run("timeline ledger watch target resolves file and directory cases") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let missingLedgerURL = directory.appendingPathComponent("events.jsonl")
            let directoryTarget = TimelineLedgerWatchTarget.resolve(ledgerURL: missingLedgerURL)
            try expect(directoryTarget == .directory(directory.path), "missing ledger should watch prepared directory")

            try Data("ledger".utf8).write(to: missingLedgerURL)
            let fileTarget = TimelineLedgerWatchTarget.resolve(ledgerURL: missingLedgerURL)
            try expect(fileTarget == .ledgerFile(missingLedgerURL.path), "existing ledger should watch the file")
        }

        #if canImport(Darwin)
            await runner.run("timeline ledger loader waits for external exclusive lock") {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                defer { try? FileManager.default.removeItem(at: directory) }

                let ledgerURL = directory.appendingPathComponent("events.jsonl")
                let key = Data("unit-test-key".utf8)
                let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key)
                try await ledger.append(AlarmEvent(source: "test", name: "timeline.locked-read"))

                let helper = Process()
                helper.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                helper.arguments = ["--hold-exclusive-lock", ledgerURL.path, "500000"]
                let readyPipe = Pipe()
                helper.standardOutput = readyPipe
                try helper.run()
                defer {
                    if helper.isRunning {
                        helper.terminate()
                        helper.waitUntilExit()
                    }
                }

                let readyData = readyPipe.fileHandleForReading.readData(ofLength: 6)
                try expect(
                    String(data: readyData, encoding: .utf8) == "ready\n",
                    "helper should hold lock"
                )

                let start = Date()
                let snapshot = try TimelineLedgerLoader.load(from: ledgerURL)
                let elapsed = Date().timeIntervalSince(start)

                helper.waitUntilExit()
                try expect(helper.terminationStatus == 0, "lock helper should exit cleanly")
                try expect(elapsed >= 0.25, "timeline loader should wait for the external exclusive lock")
                try expect(snapshot.continuity.isValid, "timeline loader should still load a linked chain")
                try expect(snapshot.records.count == 1, "timeline loader should preserve records")
                try expect(
                    snapshot.recordIndex.record(for: snapshot.records.first?.id) == snapshot.records.first,
                    "timeline loader should prepare record lookup with the loaded records"
                )
            }
        #endif

        await runner.run("timeline loader reports continuity not HMAC verification") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let ledgerURL = directory.appendingPathComponent("events.jsonl")
            let key = Data("unit-test-key".utf8)
            let ledger = try HashChainLedger(fileURL: ledgerURL, hmacKey: key)
            try await ledger.append(AlarmEvent(source: "test", name: "original"))

            var contents = try String(contentsOf: ledgerURL, encoding: .utf8)
            contents = contents.replacingOccurrences(of: "original", with: "tampered")
            try contents.write(to: ledgerURL, atomically: true, encoding: .utf8)

            let timelineSnapshot = try TimelineLedgerLoader.load(from: ledgerURL)
            let proofSnapshot = try LedgerProofExporter(ledgerURL: ledgerURL, hmacKey: key).inspectLedger()

            try expect(
                timelineSnapshot.continuity.isValid,
                "timeline loader should only check previous-hash continuity"
            )
            try expect(!proofSnapshot.verification.isValid, "HMAC verification should detect tampered event payload")
        }

        await runner.run("timeline derived state filters hidden records unless search matches") {
            let base = Date(timeIntervalSince1970: 1_000)
            let unlock = timelineRecord(
                index: 0,
                event: AlarmEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, observedAt: base,
                    source: "session",
                    name: "screen.unlocked")
            )
            let app = timelineRecord(
                index: 1,
                event: AlarmEvent(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    observedAt: base.addingTimeInterval(1),
                    source: "session",
                    name: "application.activated",
                    metadata: ["applicationName": "Finder"]
                )
            )
            let filters = TimelineFilterDefinition.defaultTemplates
            var states = Dictionary(uniqueKeysWithValues: filters.map { ($0.id, $0.defaultState) })
            states["builtin.apps"] = .hidden

            let normal = TimelineDerivedState.compute(
                DerivedTimelineSnapshot(
                    records: [unlock, app], filters: filters, filterStates: states, searchText: "", timeRange: 60,
                    now: base.addingTimeInterval(10))
            )
            try expect(
                normal.visibleRecords.map(\.id) == [unlock.id], "hidden app event should be omitted without search")

            let searched = TimelineDerivedState.compute(
                DerivedTimelineSnapshot(
                    records: [unlock, app], filters: filters, filterStates: states, searchText: "finder", timeRange: 60,
                    now: base.addingTimeInterval(10))
            )
            try expect(searched.visibleRecords.map(\.id) == [app.id], "search should surface matching hidden event")
            try expect(searched.hiddenSearchResults.contains(app.id), "search result should retain hidden marker")
        }

        await runner.run("timeline derived state cancellation stops stale work") {
            let base = Date(timeIntervalSince1970: 1_500)
            let records = (0..<200).map { index in
                timelineRecord(
                    index: index,
                    event: AlarmEvent(
                        id: UUID(),
                        observedAt: base.addingTimeInterval(Double(index)),
                        source: "session",
                        name: "application.activated",
                        metadata: ["applicationName": "App \(index)"]
                    )
                )
            }
            let snapshot = DerivedTimelineSnapshot(
                records: records,
                filters: TimelineFilterDefinition.defaultTemplates,
                filterStates: [:],
                searchText: "app",
                timeRange: 300,
                now: base.addingTimeInterval(250)
            )
            let task = Task.detached(priority: .userInitiated) {
                while !Task.isCancelled {
                    await Task.yield()
                }
                return TimelineDerivedState.computeIfNotCancelled(snapshot)
            }
            task.cancel()

            let derived = await task.value
            try expect(derived == nil, "cancelled derived timeline computation should not publish stale results")
        }

        await runner.run("timeline presentation prefers spotlight filter") {
            let record = timelineRecord(
                index: 0,
                event: AlarmEvent(source: "custom", name: "audio.detector.triggered")
            )
            let normal = TimelineFilterDefinition(
                id: "custom.audio-normal",
                title: "Audio Normal",
                symbolName: "waveform",
                color: .audio,
                match: TimelineFilterMatch(source: "custom", nameContains: "audio"),
                defaultState: .normal
            )
            let spotlight = TimelineFilterDefinition(
                id: "custom.audio-priority",
                title: "Audio Priority",
                symbolName: "mic.fill",
                color: .notification,
                match: TimelineFilterMatch(source: "custom", nameContains: "audio"),
                defaultState: .spotlight
            )
            let presentation = TimelineDerivedState.presentation(
                for: record,
                matches: [normal, spotlight],
                filterStates: [normal.id: .normal, spotlight.id: .spotlight]
            )

            try expect(presentation.title == "Audio Priority", "spotlight filter should drive presentation")
            try expect(presentation.symbolName == "mic.fill", "spotlight icon should drive presentation")
        }

        await runner.run("timeline display state handles empty and hidden filter sets") {
            let audio = TimelineFilterDefinition(
                id: "custom.audio-hidden",
                title: "Audio Hidden",
                symbolName: "waveform",
                color: .audio,
                match: TimelineFilterMatch(source: "custom", nameContains: "audio"),
                defaultState: .normal
            )

            let noEnabledFilters = TimelineDerivedState.displayState(
                for: [],
                enabledFiltersAreEmpty: true,
                filterStates: [:]
            )
            let noMatchingFilter = TimelineDerivedState.displayState(
                for: [],
                enabledFiltersAreEmpty: false,
                filterStates: [:]
            )
            let hiddenMatch = TimelineDerivedState.displayState(
                for: [audio],
                enabledFiltersAreEmpty: false,
                filterStates: [audio.id: .hidden]
            )

            try expect(noEnabledFilters == .normal, "no enabled filters should show records normally")
            try expect(noMatchingFilter == .hidden, "records with no matching enabled filter should hide")
            try expect(hiddenMatch == .hidden, "matching filters explicitly hidden should hide records")
        }

        await runner.run("category display state exposes stable filter UI text") {
            try expect(CategoryDisplayState.normal.settingsLabel == "Visible", "normal settings text should be stable")
            try expect(
                CategoryDisplayState.spotlight.settingsLabel == "Priority",
                "spotlight settings text should fit the compact pill"
            )
            try expect(CategoryDisplayState.hidden.settingsLabel == "Hidden", "hidden settings text should be stable")
            try expect(
                CategoryDisplayState.spotlight.tipText == "Prioritized",
                "hover tip should keep the more descriptive wording"
            )
            try expect(
                CategoryDisplayState.hidden.accessibilityText == "Hidden from timeline",
                "accessibility text should explain the behavior"
            )
        }

        await runner.run("timeline filter draft requires title and criteria") {
            var blank = TimelineFilterDraft()
            blank.title = "Audio"
            blank.source = ""

            try expect(!blank.match.hasCriteria, "blank draft match should report no criteria")
            try expect(!blank.canCreate, "draft should reject title-only all-events filters")

            var sourceOnly = TimelineFilterDraft()
            sourceOnly.title = "  Custom Events  "
            sourceOnly.source = " custom "

            try expect(sourceOnly.match.hasCriteria, "source should count as a filter criterion")
            try expect(sourceOnly.canCreate, "title plus source criterion should be creatable")
        }

        await runner.run("timeline filter draft factory trims values and falls back color") {
            var draft = TimelineFilterDraft()
            draft.title = "  Audio Detector  "
            draft.symbolName = "waveform"
            draft.colorID = "missing-color"
            draft.source = " custom "
            draft.nameContains = " audio "
            draft.metadataKey = " device "
            draft.metadataValue = " microphone "

            let filter = TimelineFilterDraftFactory().makeFilter(from: draft)

            try expect(filter.id.hasPrefix("custom."), "custom filter ids should use custom prefix")
            try expect(filter.title == "Audio Detector", "factory should trim filter titles")
            try expect(filter.color == .custom, "unknown draft colors should fall back to custom")
            try expect(filter.defaultState == .spotlight, "new filters should default to priority")
            try expect(!filter.isBuiltIn, "created filters should be user filters")
            try expect(filter.isEnabled, "created filters should start enabled")
            try expect(filter.match.source == "custom", "factory should trim source")
            try expect(filter.match.nameContains == "audio", "factory should trim name contains")
            try expect(filter.match.metadataKey == "device", "factory should trim metadata key")
            try expect(filter.match.metadataValue == "microphone", "factory should trim metadata value")
        }

        await runner.run("timeline filter draft catalog exposes audio template") {
            let template = TimelineFilterDraft.audioTemplate

            try expect(template.canCreate, "audio template should be creatable")
            try expect(template.symbolName == "waveform", "audio template should use waveform icon")
            try expect(template.colorID == "audio", "audio template should use audio color preset")
            try expect(template.match.source == "custom", "audio template should target custom events")
            try expect(template.match.nameContains == "audio", "audio template should match audio event names")
            try expect(
                TimelineFilterDraft.iconPresets.contains(template.symbolName),
                "audio template icon should be present in picker presets"
            )
            try expect(
                TimelineFilterDraft.colorPresets.contains { $0.id == template.colorID },
                "audio template color should be present in picker presets"
            )
        }

        await runner.run("timeline default filters are stable unique built-ins") {
            let filters = TimelineFilterDefinition.defaultTemplates
            let ids = filters.map(\.id)
            let uniqueIDs = Set(ids)

            try expect(!filters.isEmpty, "default templates should not be empty")
            try expect(ids.count == uniqueIDs.count, "default template ids should be unique")
            try expect(filters.allSatisfy(\.isBuiltIn), "default templates should all be built-in filters")
            try expect(!ids.contains("builtin.custom"), "custom should be user-created, not a default template")
            try expect(!ids.contains("builtin.other"), "other should not be exposed as a default template")
            try expect(
                ids == [
                    "builtin.unlock",
                    "builtin.lock",
                    "builtin.sleep-wake",
                    "builtin.apps",
                    "builtin.files",
                    "builtin.notifications",
                    "builtin.agent",
                    "builtin.logs",
                    "builtin.ledger",
                ],
                "default templates should keep a stable visible order"
            )
        }

        await runner.run("timeline record derives stable title subtitle and search text") {
            let event = AlarmEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                observedAt: Date(timeIntervalSince1970: 2_100),
                source: "session",
                name: "application.activated",
                severity: .warning,
                metadata: [
                    "applicationName": "Finder",
                    "bundleIdentifier": "com.apple.finder",
                    "windowTitle": "Desktop",
                ]
            )
            let record = timelineRecord(index: 12, event: event)

            try expect(record.category == .app, "application events should classify as app timeline records")
            try expect(record.title == "Finder", "app title should prefer applicationName metadata")
            try expect(record.subtitle == "com.apple.finder", "subtitle should prefer bundle identifier metadata")
            try expect(record.searchText.contains("finder"), "search text should include app title")
            try expect(record.searchText.contains("windowtitle"), "search text should include metadata keys")
            try expect(record.searchText.contains("desktop"), "search text should include metadata values")
            try expect(record.searchText.contains("warning"), "search text should include severity")
        }

        await runner.run("timeline category inspector summary insights are stable") {
            try expect(
                TimelineCategory.allCases.allSatisfy { !$0.inspectorSummaryInsight.isEmpty },
                "each category should explain why it matters"
            )
            try expect(
                TimelineCategory.unlock.inspectorSummaryInsight.contains("high-signal access"),
                "unlock insight should identify access significance"
            )
            try expect(
                TimelineCategory.agent.inspectorSummaryInsight.contains("monitoring continuity"),
                "agent insight should explain continuity"
            )
            try expect(
                TimelineCategory.custom.inspectorSummaryInsight.contains("domain-specific context"),
                "custom insight should explain integration value"
            )
            try expect(
                TimelineCategory.other.inspectorSummaryInsight.contains("tamper-evident ledger"),
                "fallback insight should describe ledger recording"
            )
        }

        await runner.run("timeline csv exporter quotes structured fields") {
            let event = AlarmEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                observedAt: Date(timeIntervalSince1970: 4_000),
                source: "session",
                name: "application.activated",
                metadata: [
                    "applicationName": "Finder, \"Main\"\nWindow",
                    "bundleIdentifier": "com.apple.finder",
                ]
            )
            let record = timelineRecord(index: 4, event: event)
            let csv = TimelineCSVExporter.export(records: [record])

            try expect(
                TimelineCSVExporter.csvEscape("a,b\"c\n") == "\"a,b\"\"c\n\"",
                "csv escaping should quote commas, quotes, and newlines")
            try expect(csv.hasPrefix(TimelineCSVExporter.header), "csv should start with the stable header")
            try expect(csv.contains("\"Finder, \"\"Main\"\"\nWindow\""), "csv should escape multiline titles")
            try expect(csv.contains(record.record.hash), "csv should include record hash")
        }

        await runner.run("timeline record index gives constant-time selected lookup") {
            let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
            let first = timelineRecord(
                index: 5,
                event: AlarmEvent(
                    id: duplicateID, observedAt: Date(timeIntervalSince1970: 5_000), source: "session",
                    name: "screen.unlocked")
            )
            let duplicate = timelineRecord(
                index: 6,
                event: AlarmEvent(
                    id: duplicateID, observedAt: Date(timeIntervalSince1970: 5_001), source: "custom",
                    name: "duplicate.id")
            )
            let index = TimelineRecordIndex(records: [first, duplicate])

            try expect(
                index.record(for: duplicateID) == first, "record index should preserve first-match selection behavior")
            try expect(index.contains(duplicateID), "record index should report known IDs")
            try expect(index.record(for: nil) == nil, "record index should ignore nil selection")
            try expect(!index.contains(UUID()), "record index should reject unknown IDs")
        }

    }
}
