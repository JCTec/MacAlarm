# Architecture

MacAlarm is split into collection, normalization, persistence, rule evaluation, and dispatch.

## Package Layout

```text
Package.swift
Sources/
  MacAlarmCore/
    AlarmEvent.swift
    AgentStatus.swift
    HashChainLedger.swift
    LedgerHashAnchor.swift
    RuleEngine.swift
    SessionEventSource.swift
    FileEventSource.swift
    LaunchAgentManager.swift
    LaunchAgentCommandModels.swift
    LaunchAgentInstallPreparation.swift
    LaunchAgentLedgerMigration.swift
    LaunchAgentProcessRunner.swift
    LaunchAgentSecrets.swift
    LaunchAgentStatusParser.swift
    UnifiedLogReader.swift
    Notifiers.swift
  MacAlarmAppSupport/
    App/
    State/
    Timeline/
    Inspector/
    Filters/
    SharedUI/
  MacAlarmApp/
    main.swift
  MacAlarmAgent/
    main.swift
  MacAlarmCLIKit/
    DoctorCommand.swift
    DoctorReport.swift
    DoctorReportRenderer.swift
  MacAlarmCLI/
    MacAlarmCLI.swift
    StatusCommand.swift
  MacAlarmProbe/
    main.swift
  MacAlarmTests/
    MacAlarmTests.swift
    CoreTests.swift
    CoreLedgerTests.swift
    CoreRuleTests.swift
    CoreConfigSecretTests.swift
    CoreOperationsTests.swift
    CoreLaunchAgentTests.swift
    AgentRuntimeTests.swift
    AppSupportTests.swift
    CLIKitTests.swift
    TimelineStateTests.swift
    TimelineLayoutTests.swift
    TimelineStoreTests.swift
```

## Core Boundaries

`AlarmEvent` is the normalized event contract. Collectors should map native macOS data into this model and avoid leaking framework-specific objects into the rest of the system.

`HashChainLedger` is an actor because multiple collectors may append concurrently. It writes JSONL records and signs each record with HMAC-SHA256 over the previous hash plus the event payload. File IO is queued through utility-priority tasks inside the actor so appends stay linear without pinning a cooperative executor thread during disk reads, parsing, locking, or writes. The ledger also uses advisory file locks: appends take an exclusive lock, while verification, proof export, and the live timeline loader take shared locks before reading bytes so another process cannot expose a partial append to readers.

The ledger supports opt-in segment rotation through `storage.maxLedgerFileBytes` (nil, the default, disables it). When the active file reaches the limit, an append renames it to a timestamped `events-rotated-*.jsonl` sibling and seeds the fresh active file with a `ledger.rotated` record whose `previousHash` is the archived segment's chain head, so the chain stays continuous across files. `verify()` and `readAllRecords()` walk archived segments in name order before the active file; `readRecords()` intentionally reads only the active segment because the live timeline shows recent history.

`LedgerHashAnchor` preserves the chain head outside the ledger's own trust domain. `hashAnchor.destination` selects where anchors land: `iCloudDrive` (default) resolves the CloudDocs folder unsandboxed and the app's iCloud ubiquity container (`iCloud.com.jctec.macalarm/Documents/MacAlarm`) when sandboxed, while `directory` uses the literal `hashAnchor.directory`. `AnchorDestinationResolver` performs that resolution behind a `UbiquityContainerResolving` protocol (fakeable in tests) and throws `MacAlarmError.iCloudUnavailable` when iCloud is signed out; `ResolvingLedgerHashAnchorSink` runs the resolution off the main thread (the ubiquity lookup blocks) and delegates to `FileLedgerHashAnchorSink`, which writes `anchor-latest.json` plus an append-only `anchor-history.jsonl`. `LedgerAnchorComparison` reports truncation or rewrites against an anchor. The pipeline writes anchors on agent start/stop and on a heartbeat cadence; an unavailable destination records a single `anchor.write.failed` warning event (repeat-suppressed) instead of blocking collection or writing elsewhere. A config predating `destination` decodes as `directory`, preserving prior behavior exactly.

### Event spool transport

`EventSpool` is the canonical custom-event transport for both sandboxed and unsandboxed builds. Producers — the viewer app's `WatchService` and `macalarmctl emit-log` — write one canonical-JSON `CustomLogEventPayload` per event (atomic, mode 0600, UUID filename) into `storage.spoolDirectory` (`<App Group container>/…/spool` when sandboxed, so app, recorder, and macalarmctl share it). The agent watches the spool with a `FileEventSource` and a reentrancy-safe `SpoolIngestor` actor, ingesting files in name order as source `custom`, preserving the event id from the filename (idempotent re-ingest), and deleting each after a successful append. Unified-log ingestion remains available unsandboxed for third-party producers logging to `dev.jc.macalarm.custom`; system-scope templates are attributed-unavailable under the sandbox.

### App-process folder watching (`WatchService`)

Under the sandbox the launchd-launched recorder can only watch paths inside the App Group container. User-selected folders are instead watched by `WatchService` in the app process: `WatchedFolderBookmarks` persists app-scope security-scoped bookmarks (added through Recorder → *Watched Folders…*), resolves them at launch, and `WatchService` runs a `FileEventSource` per folder, forwarding changes into the spool as `custom` events tagged `origin=viewer-watch`. Because the bookmark grant cannot cross into the recorder, sandboxed folder watching is active only while MacAlarm.app runs — the permanent App Store architecture (see [SANDBOX_BEHAVIOR.md](SANDBOX_BEHAVIOR.md)).

`RuleEngine` is an actor because cooldown and threshold windows are mutable state. Rules are intentionally data-oriented so they can later be loaded from a signed config file.

`AlarmDispatcher` fans out alert delivery concurrently. Individual notifiers return structured delivery results instead of only throwing.

`AgentStatusStore` writes `storage.runtimeDirectory/status.json` as a lightweight operational status surface. It is intentionally separate from the tamper-evident ledger: status is for fast UI/CLI health reads, while ledger verification remains the integrity proof.

`LaunchAgentManager` is the Swift control boundary for preparing the per-user recorder and managing the legacy LaunchAgent fallback. Packaged app installs prefer Apple's `SMAppService.loginItem` with the bundled `Contents/Library/LoginItems/MacAlarm Recorder.app`, then fall back to the app-bundled `Contents/Library/LaunchAgents/com.jctec.macalarm.agent.plist` when needed. The legacy manager remains for CLI diagnostics, development builds, and fallback installs. The manager file stays focused on the public lifecycle surface, while command/status models, install preparation, secret hardening, development-fallback ledger migration, process execution, and launchctl output parsing live in focused LaunchAgent helper files.

## CLI Boundaries

`MacAlarmCLI` is the executable entrypoint for `macalarmctl`. Deeper command behavior that benefits from direct unit coverage lives in `MacAlarmCLIKit`; `DoctorCommand` uses that target for report models, file probes, process execution summaries, ledger freshness rules, and report rendering. Process waits and filesystem probes remain off the main command path through async helpers.

## Viewer Boundaries

The viewer is split so app logic can be tested without launching the macOS app:

- `MacAlarmApp` is only the executable entrypoint.
- `MacAlarmAppSupport/App` owns the AppKit lifecycle, menus, window setup, and installer UI.
- `MacAlarmAppSupport/State` owns ledger loading, filtering, search derivation, preferences, agent health, and timeline value models.
- `MacAlarmAppSupport/Timeline` owns the horizontal timeline and layout engine.
- `MacAlarmAppSupport/Inspector`, `Filters`, and `SharedUI` keep SwiftUI components focused and reusable.

The `App` folder owns native AppKit shell behavior. The application delegate entry point for menus lives in `MainMenuController`, concrete menu construction lives in `MacAlarmMainMenuBuilder` and focused menu-section extensions, menu item wiring lives in `MacAlarmMenuItemFactory`, menu command handlers live in focused action files, window creation lives in `MainWindowController`, and reusable alert/status formatting helpers live outside the individual menu action files.

`SharedUI` is intentionally component-oriented: reusable controls such as `BrandMark`, `AgentHealthPill`, `AgentHealthPopover`, `SearchField`, `InspectorToggleButton`, and `LedgerStatusBadge` live in focused files instead of a catch-all toolbar module. Spacing and radius tokens live in `DesignTokens`; shared primitives such as `IconTile`, `PanelHeader`, `ToolbarIconButton`, and `StatusBadge` each own one file. Filter controls follow the same rule: the bar, button, hover tip, draft editor, list row, state pill, and template badge stay in separate files.

Inspector sheets and panels keep orchestration separate from repeated sections. For example, `LedgerIntegrityView` and `NotificationDiagnosticsView` own store lifetime and user actions, while their header state, summary grids, issue/test sections, and action rows live in focused files that render plain values and callbacks. The timeline inspector follows the same pattern: the pinned header, summary card, icon, tag row, and category insight copy are separate from the scroll/selection container.

Timeline screen composition follows the same rule: `ContentView` owns the root split-view/sheet composition, `TopControlBar` owns toolbar orchestration, and `TimelineStatusRow` renders plain status values.

`TimelineStore` is the main-actor publishing boundary for the viewer, but its behavior is split by responsibility. Ledger reloads prepare a `TimelineRecordSet` off-main so decoded records and their lookup index arrive together. Derived timeline state is also computed off-main, cancellation-aware, and then published as one coherent `DerivedTimelineData` value. `DerivedTimelineSnapshot` and `DerivedTimelineData` are plain transfer models, while `TimelinePresentationResolver` owns filter-state precedence and fallback presentation rules. Views still access focused read-only properties such as `records`, `visibleRecords`, and `visibleDisplayRecords`, but the store avoids rebuilding indexes or publishing several related arrays in sequence for one logical update.

State models are split by purpose. Serializable filter contracts live in `TimelineFilterDefinition`, `TimelineFilterMatch`, `TimelineFilterColor`, and `CategoryDisplayState`; shipped built-in filter choices live separately in `TimelineDefaultFilters`; custom filter draft presets and factory behavior live in `TimelineFilterDraftCatalog` and `TimelineFilterDraftFactory`; shared timeline range choices live in `TimeRangePreset` so toolbar and menu actions use the same durations; filter/search output is produced by `TimelineDerivedState`. Timeline record identity, display wrappers, presentation values, prominence sizing, severity colors, and date formatting live in focused files instead of one mixed model bucket.

SwiftUI store observation stays at the root screen boundary in `ContentView`; toolbar, canvas, inspector, sheet, and shared UI components receive plain values, bindings, and callbacks. For example, `TopControlBar`, `TimelineCanvasView`, `TimelineInspector`, `TimelineFilterSettingsView`, `LedgerIntegrityView`, `NotificationDiagnosticsView`, `BrandMark`, `AgentHealthPill`, `CategoryFilterBar`, `TimeRangeControl`, `ZoomControl`, `InspectorToggleButton`, `TimelineStatusRow`, and `LedgerStatusBadge` do not read timeline or health stores directly.

AppKit commands stay in the `App` layer. `MainWindowController` injects `MacAlarmAppActions` into `ContentView` for proof export and notification settings, so SwiftUI views do not reach through `NSApplication.shared.delegate` or own menu/window behavior directly. `./scripts/check-swiftui-appkit-boundaries.sh` enforces that `NSApplication`/`NSApp` shell access stays in `MacAlarmAppSupport/App`.

- `TimelineStore+Reloading` starts the live ledger load/watch cycle.
- `TimelineStore+LedgerWatching` handles file-system reattachment when the ledger is created, renamed, or deleted.
- `TimelineStore+DerivedState` schedules off-main filter/search derivation.
- `TimelineStore+Filters` owns filter mutation and presentation fallback helpers.
- `TimelineStore+Selection` owns inspector selection and visibility transitions.
- `TimelineStore+Export` prepares CSV off-main and commits the finished string to the pasteboard.
- `TimelineStore+Preferences` debounces UserDefaults writes.

Pure helpers such as `TimelineDerivedState`, `TimelineLayoutEngine`, `TimelineCanvasLayoutState`, `TimelineTickPlanner`, `TimelineEventLabelPositioner`, `TimelineCSVExporter`, and `TimelineRecordIndex` are kept outside SwiftUI so they can be tested without rendering views. Timeline placement has a cancellable path for SwiftUI rendering so rapid zoom, resize, or filter changes cancel stale layout work instead of letting old jobs publish late results. `TimelineCanvasLayoutState` ensures a changed request shows a correctly sized placeholder instead of stale nodes while the next background layout completes. Layout value contracts such as `TimelineLayout`, `TimelineLayoutRequest`, and `TimelineLayoutSignature` live separately from the placement algorithm. Geometry, time mapping, lane planning, tick-label clustering, node-label positioning, and collision scoring are split into focused layout helpers so performance-sensitive timeline math stays readable and directly testable.

`AgentHealthStore` reads the agent runtime status snapshot off-main and publishes it to the top bar. `AgentHealthPresenter` owns the pure classification/presentation rules for healthy, stale, degraded, stopped, and unknown states, so health behavior stays testable without launching SwiftUI.

Expensive viewer work should not run directly in SwiftUI `body` or menu actions. The current app backgrounds ledger reads/JSON decoding, derived timeline filtering, timeline placement, preference encoding, proof export, notification diagnostics, Finder target preparation, and LaunchAgent process waits, then publishes finished values back to the main actor. `./scripts/check-swiftui-main-thread-io.sh` prevents obvious synchronous file-content reads, direct process spawns, and process waits from being added directly to `MacAlarmAppSupport`.

App-support code uses `MacAlarmBackgroundTask` as the standard wrapper around detached work. That keeps cancellation propagation consistent for SwiftUI tasks, menu actions, proof export, notification diagnostics, Finder preparation, CSV export, and installer helper operations. New app-side background work should use this wrapper instead of calling `Task.detached` directly.

The viewer also treats the ledger path as dynamic: off-main watcher target resolution decides whether to watch the ledger file or prepare and watch the parent MacAlarm support directory. When the ledger appears, is renamed, or is deleted, the watcher reloads and reattaches instead of silently going stale.

## Test Boundaries

The custom Swift runner stays intentionally small. `MacAlarmTests.swift` only handles process entry, the Darwin lock helper, and the top-level test order. Core package suites are split by domain: `CoreLedgerTests.swift` covers the hash-chain ledger and proof export, `CoreRuleTests.swift` covers event matching and rules, `CoreConfigSecretTests.swift` covers config validation and secret storage, `CoreOperationsTests.swift` covers custom log payloads, notification diagnostics, and remote checkpoint outbox behavior, and `CoreLaunchAgentTests.swift` covers install paths and LaunchAgent lifecycle commands. CLI doctor presentation and probe contracts live in `CLIKitTests.swift`; bounded agent runtime behavior lives in `AgentRuntimeTests.swift`; app shell, menu, notification, installer, Finder, and background-task helpers live in `AppSupportTests.swift`; pure timeline filtering, record, export, and ledger-loading behavior lives in `TimelineStateTests.swift`; timeline placement and rendering math lives in `TimelineLayoutTests.swift`; and main-actor store/preferences/health presentation behavior lives in `TimelineStoreTests.swift`.

`FileEventSource` lifecycle is main-actor isolated because the agent runtime owns source creation and cancellation from the main actor. The actual filesystem event delivery still runs on the source's private dispatch queue, then hands normalized `FileEvent` values into the async pipeline.

## Native API Choices

- Swift 6 language mode for strict concurrency checks.
- `Sendable` event/rule/delivery models.
- `actor` isolation for mutable ledger, rule, and dispatch state.
- `CryptoKit` for HMAC-SHA256 instead of OpenSSL/CommonCrypto dependency.
- `OSLog.Logger` and `OSLogStore` for unified-log emission/readback.
- `AppKit.NSWorkspace` for session/environment notifications.
- `Foundation.DistributedNotificationCenter` for practical lock/unlock notification names.
- `DispatchSourceFileSystemObject` for canary file monitoring.
- `UserNotifications` for bundled-app local alerts.
- AppleScript `display notification` fallback for SwiftPM CLI/dev alerts.
- POST-ready outbox JSON for future server delivery, without network sending.

## Non-Goals

- Hidden monitoring.
- Keystroke capture.
- Screenshot capture.
- Private-content capture.
- Bypassing macOS privacy prompts.
- Pretending local files are tamper-proof against root.
