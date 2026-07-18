# Diagnostic Logging Plan

> Status: Phases 0–5 are implemented (`Sources/MacAlarmCore/MacAlarmLog.swift` plus
> instrumentation across agent, ledger, sources, delivery, and viewer). Phase 6
> (CLI `--verbose` plumbing) is intentionally deferred.

A staged walkthrough for adding structured diagnostic logging across MacAlarm. The goal is to make any failure diagnosable from `log stream` output without attaching a debugger — while keeping logs quiet by default, privacy-safe, and out of performance-critical paths.

## Principles

Diagnostic logs answer "what did the code do"; the ledger answers "what happened on the Mac". Never mix them. Diagnostics use `OSLog.Logger`, never `print`, so levels, categories, and Console.app filtering work. Default-level logs must be readable by a stranger and free of event content; verbose detail goes to `.debug`, which macOS discards unless streaming. Errors always log the underlying `error` description and enough context to locate the call site.

## The Self-Ingestion Trap

The default `unifiedLog` config polls predicate `subsystem == 'dev.jc.macalarm.custom'`. All diagnostic logging MUST use subsystem `dev.jc.macalarm.diagnostics` so the agent never records its own debug output into the ledger. Add a comment on the subsystem constant explaining this. `macalarm-probe` currently logs under `dev.jc.macalarm` — leave it; it is exact-match safe too.

## Phase 0 — Foundation (do first, everything depends on it)

New file `Sources/MacAlarmCore/MacAlarmLog.swift`:

- `public enum MacAlarmLog` with `public static let subsystem = "dev.jc.macalarm.diagnostics"`.
- One cached `Logger` per category: `agent`, `pipeline`, `ledger`, `anchor`, `rules`, `notify`, `sources`, `launchagent`, `telegram`, `cli`, `appshell`, `timeline`, `health`, `installer`.
- Signpost helper (`OSSignposter`) for performance intervals, used by the viewer phases.

Conventions (document in the file header):

- `.error` — an operation failed and behavior degrades (append failed, watcher failed, install step failed).
- `.warning`/`.notice` — unexpected but recovered (fallback path taken, reattach, retry).
- `.info` — lifecycle milestones only (started, stopped, installed, rotated, config loaded). Sparse.
- `.debug` — everything useful mid-investigation (per-event flow, lock waits, derivation counts).
- Interpolate dynamic values as `\(value, privacy: .public)` only for non-content data (counts, durations, booleans, error types, file names without user paths). Event names/metadata, full paths, and config values stay `.private` (the default).

## Phase 1 — Agent core (most likely home of "something is not working")

- `MacAlarmAgent/main.swift`: config path chosen, validation issue count, key source (installed vs fallback), log redirection outcome, exit reasons.
- `MacAlarmAgentRuntime.swift`: each `start*()` — source started/skipped and why; task cancellations in `stop()`; bounded-run deadline hits.
- `EventPipeline.swift`: `.debug` per event (source/name public, metadata not logged); rule match count; each delivery result; checkpoint/anchor enqueue outcomes; the `catch` branch in `record()` MUST log `.error` — today it swallows errors into `EventProcessingResult.errorDescription` and nothing surfaces them.
- `AgentStatusStore`: write failures (`.error`), state transitions (`.debug`).

## Phase 2 — Ledger and integrity

- `HashChainLedger.swift`: append failures with error (`.error`); rotation performed with archived segment name (`.info`); verify results — issue count and first failing line (`.info` valid / `.error` invalid); `runSerializedIO` queue depth if ever needed (`.debug`).
- `LedgerFileLock.swift`: lock acquisition failures (`.error`); optionally `.debug` wait timing via signpost if contention is suspected.
- `LedgerHashAnchor.swift` / `LedgerProofExporter.swift`: write/export success (`.debug`) and failure (`.error`).

## Phase 3 — Event sources

- `SessionEventSource.swift`: observer registration/removal (`.debug`), each notification mapped (`.debug`, event name public).
- `FileEventSource.swift`: watch start/stop per path label (`.info`), dispatch source event mask (`.debug`), open/attach failures (`.error`).
- `UnifiedLogReader.swift`: query executed with entry count (`.debug`), store open failures (`.error`).

## Phase 4 — Delivery and control plane

- `Notifiers.swift`: each notifier attempt + result (`.debug`), authorization snapshot on first use (`.info`), AppleScript fallback taken (`.notice`).
- `LaunchAgentManager.swift` + helper files: every install/uninstall step (`.info`), each `launchctl` invocation with exit code (`.debug`, `.error` on nonzero), fallback path decisions (`.notice`).
- `TelegramSupport.swift`: poll failures (`.error`), filtered/skipped alarms (`.debug`). Never log tokens or chat IDs at `.public`.

## Phase 5 — Viewer (MacAlarmAppSupport)

- `TimelineStore+Reloading` / `+LedgerWatching`: reload trigger reason (`.info`), decode duration + record count (`.debug`), watcher reattach transitions (`.notice`).
- `TimelineStore+DerivedState`: derivation started/cancelled/published with counts (`.debug`) — cancellations are prime suspects for "timeline looks stale" bugs.
- `TimelineLayoutEngine` and layout helpers: no per-node logging ever; wrap layout passes in signpost intervals instead.
- `AgentHealthStore` / `AgentHealthPresenter`: status read failures (`.error`), classification transitions (`.debug`).
- `MacAlarmAgentInstaller`, `MacAlarmProofService`, `MacAlarmNotificationService`, menu actions: each user-triggered operation start/outcome (`.info`/`.error`).
- Never log inside SwiftUI `body` or per-frame paths.

## Phase 6 — CLI

CLI user output stays `print`. Add `.debug` diagnostics behind the scenes in `DoctorCommand` probes and `StatusCommand` so `--verbose` flags can be added later without restructuring.

## Verification (each phase)

1. `swift build && swift run -c debug macalarm-tests` — logging must never break tests.
2. `log stream --predicate 'subsystem == "dev.jc.macalarm.diagnostics"' --level debug` while running `swift run macalarm-probe --session --duration 15` (phases 1–4) or the viewer via `./scripts/run-viewer-debug.sh` (phase 5).
3. Confirm the ledger contains no `dev.jc.macalarm.diagnostics` events after a bounded agent run (self-ingestion check).
4. Grep gate idea for CI once done: forbid new `print(` in `Sources/MacAlarmCore` outside CLI output paths.

## Reading Logs Later

- Live: `log stream --predicate 'subsystem == "dev.jc.macalarm.diagnostics"' --level debug`
- Past hour: `log show --last 1h --predicate 'subsystem == "dev.jc.macalarm.diagnostics"' --info --debug`
- Installed agent stdout/stderr (crashes, pre-logger failures): `~/Library/Logs/MacAlarm/`
- Console.app: filter subsystem, then category.
