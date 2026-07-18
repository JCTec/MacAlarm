# MacAlarm Technical Plan

This plan turns MacAlarm from a working research package into an open-source macOS security utility that a normal user can install, understand, and trust.

The north-star milestone is:

```text
Install MacAlarm, log out or reboot, unlock the Mac, and open the app to see a clear, verified account of what happened without touching Terminal.
```

## Current Baseline

MacAlarm already has the hardest foundation pieces:

- Pure Swift 6 package.
- Native macOS event hooks for session, sleep/wake, app lifecycle, filesystem watches, and unified-log reads.
- Hash-chain JSONL ledger with HMAC-SHA256 record integrity.
- Rule engine with cooldown, threshold, edge, and quiet-hour behavior.
- Local notification path with AppleScript fallback for dev builds.
- SwiftUI timeline viewer hosted inside a reliable AppKit one-window shell.
- CSV export from native macOS menu commands.
- Outbox-only remote checkpoint scaffold, with no live network sending.

The next work should focus on product reliability and trust surfaces before adding remote delivery.

## Phase 1: Agent Lifecycle And Health

Goal: the app should know whether monitoring is actually running.

### User-Facing Behavior

- The top bar shows a health strip:
  - Green: agent is running, heartbeat is recent, ledger verifies, notification path is available.
  - Yellow: agent is running but one supporting system is degraded.
  - Red: no recent heartbeat, ledger verification failed, or notifications cannot be delivered.
- The viewer shows:
  - agent status
  - PID
  - last heartbeat timestamp
  - ledger path
  - record count
  - last hash prefix
  - notification channel status
  - LaunchAgent installation state
- If the agent is stopped, the app should make that obvious without alarming theatrics.

### Core Types

Add these to `MacAlarmCore`:

```swift
public struct AgentStatus: Codable, Sendable, Equatable {
    public var state: AgentState
    public var pid: Int?
    public var lastHeartbeat: Date?
    public var launchAgent: LaunchAgentStatus
    public var ledger: LedgerHealth
    public var notifications: NotificationHealth
    public var checkedAt: Date
}

public enum AgentState: String, Codable, Sendable {
    case running
    case stopped
    case stale
    case unknown
}

public struct LedgerHealth: Codable, Sendable, Equatable {
    public var isValid: Bool
    public var recordCount: Int
    public var lastHash: String
    public var issues: [String]
}

public struct NotificationHealth: Codable, Sendable, Equatable {
    public var localNotificationAvailable: Bool
    public var appleScriptFallbackAvailable: Bool
    public var lastDeliveryAt: Date?
    public var lastFailure: String?
}

public struct LaunchAgentStatus: Codable, Sendable, Equatable {
    public var isInstalled: Bool
    public var label: String
    public var plistPath: String
    public var lastExitStatus: Int?
    public var launchctlSummary: String?
}
```

### Runtime Files

Use `~/Library/Application Support/MacAlarm/runtime/`:

```text
runtime/
  agent.pid
  agent-status.json
  last-heartbeat.json
```

`agent-status.json` should be best-effort and user-readable. The ledger remains the source of truth for event history.

### Agent Changes

Update `MacAlarmAgentRuntime`:

- Write `agent.pid` on start.
- Remove `agent.pid` on clean stop.
- Write `agent-status.json` on start, heartbeat, and stop.
- Record `agent.started`, `agent.heartbeat`, and `agent.stopped` as it already does.
- Add `agent.start.failed` event for startup failures that occur after the ledger is available.
- Add stale heartbeat detection in the app, not the agent.

### App Changes

Add a store object:

```text
Sources/MacAlarmApp/
  AgentHealthStore.swift
```

Responsibilities:

- Poll runtime files every 2 seconds while app is active.
- Read runtime health from `AgentHealthStore` and live chain-continuity state from `TimelineStore`.
- Derive a single `HealthLevel`.
- Expose short UI strings and detailed diagnostics.

Proposed enum:

```swift
enum HealthLevel {
    case healthy
    case degraded
    case critical
    case unknown
}
```

### UI Work

Modify top bar:

- Add compact health pill next to `MacAlarm`.
- Make the health pill clickable to open a small popover or inspector section.
- Show:
  - `Running`
  - `Last heartbeat 42s ago`
  - `Ledger verified`
  - `Local alerts OK`

### CLI Work

Current commands:

```sh
macalarmctl status
macalarmctl health
macalarmctl doctor
```

`status` reads `storage.runtimeDirectory/status.json` and emits machine-readable current runtime health, including process liveness and heartbeat freshness.

`health` reads the same status snapshot and prints a one-screen human runtime summary.

`doctor` performs the deeper installed-agent diagnostics: installed binary/plist checks, config validation, LaunchAgent visibility, notification status, ledger integrity, latest-event reporting, human output, and `--json` machine output.

### Tests

Add Swift tests for:

- Status JSON decoding.
- Heartbeat freshness classification.
- Missing PID file.
- Stale PID file where process is gone.
- Ledger valid plus agent stopped returns degraded or critical depending on policy.

### Acceptance Criteria

- User can open the viewer and immediately know whether MacAlarm is watching.
- If the agent is not running, the UI says so within 3 seconds.
- If live chain continuity is broken, the UI shows a chain issue and points to the HMAC-backed integrity view.
- `swift run macalarmctl status` prints valid JSON.
- Tests cover all health classifications.

## Phase 2: LaunchAgent Install, Start, Stop, Restart

Goal: users should not need Terminal for normal operation.

### User-Facing Behavior

The app gets a simple agent control panel:

- Install LaunchAgent
- Uninstall LaunchAgent
- Start
- Stop
- Restart
- Open logs
- Reveal ledger

The app should be explicit that this is a visible user LaunchAgent, not stealth persistence.

### LaunchAgent Location

Use:

```text
~/Library/LaunchAgents/com.jctec.macalarm.agent.plist
```

### LaunchAgent Label

Use:

```text
com.jctec.macalarm.agent
```

### Core Installer API

Add:

```text
Sources/MacAlarmCore/
  LaunchAgentManager.swift
```

Responsibilities:

- Generate plist from `LaunchAgentPlist`.
- Write plist atomically.
- Validate plist path and executable path.
- Call `launchctl bootstrap gui/$UID`.
- Call `launchctl bootout gui/$UID`.
- Call `launchctl kickstart -k gui/$UID/com.jctec.macalarm.agent`.
- Query `launchctl print gui/$UID/com.jctec.macalarm.agent`.

Possible API:

```swift
public struct LaunchAgentManager {
    public func install(configURL: URL, executableURL: URL) throws
    public func uninstall() throws
    public func start() throws
    public func stop() throws
    public func restart() throws
    public func status() -> LaunchAgentStatus
}
```

### CLI Commands

Add:

```sh
macalarmctl install-agent --config ~/Library/Application\ Support/MacAlarm/config.json
macalarmctl uninstall-agent
macalarmctl start-agent
macalarmctl stop-agent
macalarmctl restart-agent
macalarmctl agent-status
```

### App Integration

Add:

```text
Sources/MacAlarmApp/
  AgentControlPanel.swift
  AgentControlStore.swift
```

The app should call the same core manager as the CLI.

### Logging

LaunchAgent should write stdout/stderr to:

```text
~/Library/Logs/MacAlarm/agent.out.log
~/Library/Logs/MacAlarm/agent.err.log
```

The app should include a menu item:

```text
Recorder > Open Recorder Logs
```

### Safety Constraints

- Never install without explicit user action.
- Never hide the LaunchAgent.
- Never require root for Phase 2.
- Never bypass LaunchServices, TCC, or notification prompts.

### Tests

Unit tests:

- Plist contains expected label, executable, arguments, log paths.
- Manager refuses non-absolute executable paths.
- Manager refuses config path outside expected form unless explicitly allowed.

Manual QA:

- Install agent.
- Log out and log in.
- Confirm `agent.started`.
- Confirm heartbeat appears.
- Stop agent.
- Confirm UI turns red after stale threshold.
- Restart agent.
- Confirm UI recovers.

### Acceptance Criteria

- A user can install and start monitoring from the app.
- Reboot/login preserves monitoring.
- Uninstall removes the plist and stops the job.
- App health reflects LaunchAgent state within 5 seconds.

## Phase 3: Incident Grouping

Goal: turn event streams into readable stories.

Raw events are useful, but users need an answer to: "What happened while I was away?"

### Incident Examples

```text
Access window
  system.didWake
  screen.unlocked
  application.activated Finder
  application.activated Terminal
  screen.locked

Monitoring interruption
  agent.stopped
  heartbeat missing for 8m
  agent.started

Config tamper
  filesystem.modified config.json
  ledger verified
  notification delivered
```

### Core Types

Add:

```text
Sources/MacAlarmCore/
  Incident.swift
  IncidentBuilder.swift
```

Proposed model:

```swift
public struct Incident: Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: IncidentKind
    public var severity: AlarmSeverity
    public var title: String
    public var summary: String
    public var startedAt: Date
    public var endedAt: Date?
    public var eventIDs: [UUID]
    public var confidence: IncidentConfidence
    public var metadata: [String: String]
}

public enum IncidentKind: String, Codable, Sendable {
    case accessWindow
    case sleepWakeWindow
    case monitoringInterruption
    case notificationFailure
    case fileTamper
    case ledgerIntegrityIssue
    case applicationBurst
    case unknown
}

public enum IncidentConfidence: String, Codable, Sendable {
    case exact
    case inferred
    case partial
}
```

### Incident Builder Rules

Build incidents from ledger records in memory first.

Rules:

- `screen.unlocked` starts an access window.
- `screen.locked` closes the access window.
- `system.didWake` within 2 minutes before unlock attaches to the access window.
- App activations within an open access window attach to that incident.
- Missing heartbeat longer than threshold creates monitoring interruption.
- File changes in watched paths create file tamper incidents.
- Notification failures attach to the triggering alarm.

### App UI

Add an `Incidents` mode:

- Timeline still remains primary.
- A segmented control toggles:
  - Events
  - Incidents
- Incident nodes are larger and span time ranges.
- Inspector shows:
  - summary
  - timeline of included events
  - duration
  - key apps touched
  - proof hashes for first and last records

### Tests

Add deterministic test fixtures:

```text
Tests/Fixtures/
  access-window.jsonl
  monitoring-interruption.jsonl
  file-tamper.jsonl
```

If staying with custom `macalarm-tests`, add fixture readers under `Sources/MacAlarmTests`.

Test:

- Unlock then lock becomes one access window.
- Wake before unlock attaches to access window.
- App activations inside window attach.
- App activations outside window do not attach.
- Missing heartbeat creates interruption.

### Acceptance Criteria

- The app can show the last 24 hours as incidents instead of only events.
- Selecting an incident explains what happened in one human-readable paragraph.
- Tests prove incident grouping is deterministic.

## Phase 4: Integrity View And Proof Export

Goal: make the hash-chain work visible and useful.

### User-Facing Behavior

Add a `Ledger` or `Integrity` view with:

- verification status
- total records
- first record timestamp
- last record timestamp
- last hash
- number of issues
- broken line numbers if any
- export proof bundle

### Proof Bundle

Export a protected directory:

```text
MacAlarm-Proof-2026-06-17/
  events.jsonl
  verification.json
  summary.txt
  last-hash.txt
```

Future optional:

```text
  remote-checkpoints/
  detached-signature.txt
```

### Core API

Implemented:

```text
LedgerProofExporter.swift
```

API:

```swift
public struct LedgerProofExporter {
    public init(ledgerURL: URL, hmacKey: Data) throws
    public func inspectLedger(checkedAt: Date = .now) throws -> LedgerIntegritySnapshot
    public func exportProofBundle(to destinationURL: URL, exportedAt: Date = .now) throws -> LedgerProofBundle
}
```

The CLI exposes this as:

```sh
macalarmctl export-proof [--config PATH] --output DIR
```

The command resolves the HMAC key from the installed private secret file, performs ledger read/copy/verification in a detached background task, and returns exit code `0` for a valid bundle or `3` when verification detects tampering.

### UI

Add:

- native menu item: `File > Export Proof Bundle...`
- integrity section in inspector for selected event
- dedicated integrity view accessible from top health pill

Current status: selected events expose hash-chain context in the inspector. The dedicated integrity view is implemented and reachable from the health popover, ledger status badge, and `View > Show Ledger Integrity`. Native menu proof export is implemented.

### Tests

- Export includes all expected files.
- Exported verification result matches in-app verification.
- Tampered ledger export marks `isValid = false`.

### Acceptance Criteria

- CLI and app menu export write a readable proof bundle.
- The app shows HMAC-backed verification status, record count, first/last timestamps, last hash, and issues.
- Broken hash chain is obvious in exported `verification.json`.
- A dedicated integrity dashboard is available in the viewer.

## Phase 5: Rules Editor

Goal: make alert rules configurable without editing JSON by hand.

### Initial Rules UI

Start with simple toggles:

- Alert on screen unlock.
- Alert on wake.
- Alert when watched file changes.
- Alert when agent stops.
- Alert when heartbeat becomes stale.
- Quiet hours enabled.
- Quiet hours start/end.
- Notification sound.

Avoid exposing every rule-engine feature in v1.

### Config Store

Add:

```text
Sources/MacAlarmApp/
  SettingsStore.swift
  RulesSettingsView.swift
```

Use `MacAlarmConfig` as the persisted model.

Config path:

```text
~/Library/Application Support/MacAlarm/config.json
```

### Validation

Every save must:

- encode pretty JSON
- validate with `ConfigValidator`
- write atomically
- create backup:

```text
config.backup-YYYYMMDD-HHMMSS.json
```

### UI Safety

- If config is invalid, do not overwrite the last valid config.
- Show validation errors in the settings view.
- Offer "Reveal Config" for advanced users.
- Offer "Reset to Default Config".

### Tests

- Default toggles map to expected rules.
- Invalid quiet-hour values fail validation.
- Atomic save creates a valid config.
- Backup file is created before overwrite.

### Acceptance Criteria

- A non-developer can enable unlock/wake/file alerts from the app.
- The agent can restart and load the edited config.
- Invalid settings cannot silently break monitoring.

## Phase 6: Notification Maturity

Goal: local notifications should be boringly reliable before Telegram or remote POST.

### Bundled Notification Path

Implemented for the packaged app:

- request UserNotifications permission from the app
- show notification authorization state
- use `UNUserNotificationCenter` as primary path
- keep AppleScript fallback for dev and CLI contexts

### Notification Doctor

Add diagnostics:

- app notification permission. Done in the Notifications diagnostics view.
- Focus mode warning if detectable
- AppleScript fallback availability
- last delivery attempt
- last delivery failure

### App UI

Add:

- `Send Test Alert`. Done.
- `Notification Status`. Done.
- `Open System Notification Settings`. Done.

Current status: app-side notification diagnostics are reachable from the native `Notifications` menu. CLI and app test alerts record the trigger and delivery result in the HMAC ledger. Health-strip degradation for disabled notifications and Focus-mode detection remain future work.

### Tests

Some notification tests remain manual because macOS UI authorization is involved.

Automated:

- notifier result encoding
- fallback selection logic
- delivery event recording

Manual:

- permission prompt appears
- test notification appears
- delivery event appears in ledger. Done for CLI/app test notifications and agent alarms.

### Acceptance Criteria

- User can confirm notifications work from inside the app.
- If notifications are disabled, the diagnostics view shows the authorization state.
- Delivery attempts are always recorded in the ledger.

## Phase 7: Packaging And Release

Goal: make the repository credible to outside contributors.

### Build System

Keep SwiftPM for core development, but add release packaging.

Options:

1. SwiftPM plus script-generated `.app`.
2. Xcode project generated or committed for signed app distribution.
3. Future Homebrew cask.

Short-term:

```text
scripts/
  run-viewer-debug.sh
  package-debug-app.sh
  install-launch-agent.sh
  uninstall-launch-agent.sh
```

Long-term:

```text
.github/workflows/
  macos-build.yml
  swift-test.yml
```

### Signing And Notarization

Not required for early source release, but document the path:

- Developer ID Application certificate.
- Hardened Runtime.
- Notarization.
- Stapling.

### Release Artifacts

Each release should include:

- `.zip` app bundle
- SHA256 checksum
- source archive
- release notes
- verification notes

### Acceptance Criteria

- Fresh clone builds with documented commands.
- CI runs tests.
- README has screenshots.
- A contributor can understand the privacy boundary in under 5 minutes.

## Phase 8: Remote Delivery And Checkpoints

Goal: add external safety without compromising the local-first trust model.

Do this after local agent, health, notifications, and proof export are stable.

### Remote Checkpoint First

Start with hash checkpoints, not full event upload:

```json
{
  "deviceID": "local-user-controlled-id",
  "recordCount": 1234,
  "lastHash": "abc123...",
  "observedAt": "2026-06-17T04:45:00Z"
}
```

This proves the local ledger existed at a point in time without exposing detailed activity.

### Later Remote Event Upload

If added, make it opt-in and explicit:

- disabled by default
- visible in UI
- redactable fields
- retry outbox
- backpressure limits
- TLS only
- no secret tokens in config examples

### Telegram

Telegram should be implemented as a notifier adapter after remote checkpointing:

```text
TelegramNotifier.swift
```

Config:

```json
{
  "telegram": {
    "enabled": false,
    "botTokenKeychainAccount": "telegram-bot-token",
    "chatID": "123456"
  }
}
```

Token storage must use Keychain, not plaintext config.

### Acceptance Criteria

- Remote functionality is off by default.
- UI clearly shows when remote delivery is enabled.
- Failed remote delivery never blocks local ledger writes.
- Tests cover outbox retry state transitions.

## Security And Privacy Rules

These are non-negotiable for open source trust:

- No keylogging.
- No screenshots.
- No hidden microphone/camera.
- No chat/message scraping.
- No browser-history scraping.
- No stealth persistence.
- No hidden privilege escalation.
- No bypassing macOS TCC prompts.
- No remote upload by default.
- No plaintext secrets in config examples.

MacAlarm should feel like a visible seatbelt, not spyware.

## Suggested Issue Breakdown

Use these as GitHub issues.

### Milestone: Local Agent UX

- Add `AgentStatus` and health models. Done for runtime snapshots.
- Write runtime status files from agent. Done at `storage.runtimeDirectory/status.json`.
- Add `macalarmctl status`. Done with JSON output.
- Add `macalarmctl health`. Done with human output.
- Extend implemented `macalarmctl doctor` with suggested fixes as status files mature.
- Add `AgentHealthStore` to app. Done.
- Add health pill to top bar. Done with a SwiftUI popover.
- Add stale heartbeat detection. Done in `AgentHealthStore` and `macalarmctl status`/`health`.

### Milestone: LaunchAgent Management

- Add `LaunchAgentManager`. Done with injectable command runner.
- Add install/uninstall/start/stop/restart CLI commands. Done as `macalarmctl agent-*`.
- Add app control panel. Done in the Recorder menu with install, status, restart, stop, uninstall, logs, and ledger actions.
- Add agent log paths. Done in app menu and installer output.
- Add manual QA checklist.

### Milestone: Timeline Intelligence

- Add `Incident` model.
- Add `IncidentBuilder`.
- Add incident fixtures.
- Add Events/Incidents segmented UI.
- Add incident inspector.

### Milestone: Integrity UX

- Add integrity view. Done.
- Add proof bundle exporter. Done.
- Add proof export menu item. Done.
- Add tamper fixture.

### Milestone: Settings And Rules

- Add settings store.
- Add simple rules editor.
- Add config backups.
- Add config validation UI.

### Milestone: Release Readiness

- Add screenshots.
- Add architecture diagram.
- Add GitHub Actions.
- Add release packaging script.
- Add threat model quick-start.

## Recommended Execution Order

1. Agent health models and runtime files.
2. Health strip in app.
3. `macalarmctl status`, `health`, and richer `doctor` remediation.
4. LaunchAgent manager in core.
5. Install/start/stop controls in app.
6. Incident builder.
7. Integrity view and proof export.
8. Rules editor.
9. Notification maturity.
10. Packaging and CI.
11. Remote checkpoints.
12. Telegram/webhook notifiers.

## Definition Of Open-Source Worthy v1

MacAlarm reaches v1 when all of this is true:

- A fresh clone builds and tests on supported macOS.
- The app opens without Terminal-specific hacks.
- The user can install and uninstall the LaunchAgent.
- The app clearly shows whether monitoring is active.
- Lock/unlock/wake/app/file events appear in the timeline.
- Ledger verification is visible.
- Proof export works.
- Notifications can be tested from the app.
- Privacy boundaries are documented and enforced by design.
- Remote/Telegram functionality is absent or off by default.
