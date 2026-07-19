# Sandbox Behavior

MacAlarm ships in two shapes from one codebase: the unsandboxed SwiftPM/dev build
and the sandboxed Mac App Store build. This document is the single reference for
what every feature does in each, including the **exact attributed-failure wording**
a sandboxed build emits when a capability is genuinely unavailable.

Two governing principles hold everywhere:

- **No unknown behavior.** Anything unavailable under the App Sandbox fails loudly
  and attributably — a diagnostic log naming the sandbox, a ledger event where the
  ledger is writable, and accurate UI copy where UI exists. A runtime-attributed
  failure for a genuinely absent environment (iCloud signed out, missing
  entitlement) is *correct behavior*, not a bug.
- **No temporary solutions.** Every sandboxed behavior below is the permanent
  architecture, not a placeholder.

All sandbox detection and messaging flow through `SandboxEnvironment`
(`isSandboxed` reads `APP_SANDBOX_CONTAINER_ID`; `unavailableReason(_:)` renders the
uniform prefix). Grep for `unavailable under App Sandbox` to find every
attributed-failure surface.

## Feature matrix

| Feature | Sandboxed (Mac App Store) | Unsandboxed (SwiftPM / dev) |
| --- | --- | --- |
| **Shared state** (ledger, config, secrets, runtime status, outbox, spool) | App Group container `S8662L649U.com.jc-tec.macalarm.shared` (`Application Support/MacAlarm`), so app + recorder + macalarmctl share one source of truth. If the container is unresolvable, install/startup fail with `unavailable under App Sandbox: the app group container '…' could not be resolved` — never a silent private-container fallback. | `~/Library/Application Support/MacAlarm/…` (unchanged). |
| **Recorder install** | Bundled login item `com.jc-tec.macalarm.recorder` via `SMAppService.loginItem` (Background Items approval), with the app-bundled `com.jc-tec.macalarm.agent.plist` as the `SMAppService.agent` fallback. The legacy `~/Library/LaunchAgents` install is `unavailable under App Sandbox: it writes into ~/Library outside the container` and throws `AppInstallerError.sandboxRequiresBundledRecorder`. | `SMAppService` when packaged, else legacy per-user `LaunchAgent`. |
| **LaunchServices registration** of the helper app | Skipped: `LaunchServices registration of the helper app unavailable under App Sandbox: lsregister cannot scan the container; skipping`. | Runs `lsregister -f`. |
| **Hash anchoring** (`hashAnchor.destination = iCloudDrive`, default) | iCloud **ubiquity container** `url(forUbiquityContainerIdentifier: iCloud.com.jc-tec.macalarm)/Documents/MacAlarm`. iCloud signed out → one `anchor.write.failed` ledger event + one attributed `.error` log (`iCloud Drive is unavailable (signed out, or ubiquity container '…' is nil); …`), repeat-suppressed, surfaced in `doctor`. | `~/Library/Mobile Documents/com~apple~CloudDocs/MacAlarm`. |
| **Hash anchoring** (`hashAnchor.destination = directory`) | The literal `hashAnchor.directory` (must be inside the container to be writable). | The literal `hashAnchor.directory`. |
| **Custom event transport** (spool) | Producers write canonical-JSON events into `<container>/…/spool`; the recorder ingests + deletes them. Primary and only reliable transport. | Same spool under `~/Library/Application Support/MacAlarm/spool`. |
| **Unified-log ingestion** | `currentProcess`-scope templates work. `system`-scope templates are `unavailable under App Sandbox: system-scope OSLogStore requires an entitlement the sandbox denies` → one `unifiedLog`/`query.unavailable` event (`reason=app-sandbox`) per template per run, then skipped. `ConfigValidator` warns. | All scopes work (kept for third-party producers logging to `dev.jc.macalarm.custom`). |
| **macalarmctl emit-log** | Writes to the spool when the installed layout is present (the transport the recorder ingests); a custom `--subsystem` still uses unified logging. | Same preference; falls back to unified logging with the default subsystem when no install is present. |
| **Folder watching — user-selected** | App-process `WatchService` resolves security-scoped bookmarks and forwards changes into the spool as `custom` events tagged `origin=viewer-watch`. **Active only while MacAlarm.app is running** — the grant cannot cross into the launchd recorder. Manage via Recorder → *Watched Folders…*. | Also available; same behavior. |
| **Folder watching — agent config paths** (`filesystem.watchedPaths`) | Only paths **inside the container** watch. Anything else emits one `filesystem`/`watch.unavailable` event (`reason=app-sandbox`, `… unavailable under App Sandbox: the path is outside the App Group container; skipping`) per path per run. `ConfigValidator` errors (critical) if such a path is `required=true`, warns otherwise. | Watches any configured path directly. |
| **AppleScript notifier** | Delivery fails with `unavailable under App Sandbox: AppleScript notifications spawn osascript`; `ConfigValidator` warns when `appleScriptFallback` is enabled. UserNotifications is the sandboxed channel. | Runs `osascript`. |
| **UserNotifications** | Works (requires the app bundle); the primary/sandboxed notification channel. | Works. |
| **Telegram / remote checkpoint** | Works — the app and helper carry `com.apple.security.network.client`. Without that entitlement, Telegram delivery fails with `unavailable under App Sandbox: Telegram needs the com.apple.security.network.client entitlement` and `ConfigValidator` warns. | Works. |
| **doctor** | Reports `Sandboxed: true`, probes the App Group container (attributing failures to the sandbox), and reports the anchor destination + last anchor status. | Reports `Sandboxed: false`; anchor + ledger sections as usual. |

## What is not a bug

- `anchor.write.failed` while iCloud is signed out.
- `query.unavailable` for a `system`-scope unified-log template under the sandbox.
- `watch.unavailable` for a configured agent watch path outside the container.
- Folder watching pausing when MacAlarm.app is not running.

Each of these is an intended, attributed response to a genuinely absent capability.

## Identifiers

- App / bundle id: `com.jc-tec.macalarm`
- Recorder login item: `com.jc-tec.macalarm.recorder`
- Agent LaunchAgent label: `com.jc-tec.macalarm.agent`
- App Group: `S8662L649U.com.jc-tec.macalarm.shared`
- iCloud container: `iCloud.com.jc-tec.macalarm`
- Log namespaces (unchanged, not bundle ids): `dev.jc.macalarm.custom` (custom-event
  subsystem), `dev.jc.macalarm.diagnostics` (MacAlarm's own diagnostics).
