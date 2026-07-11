# Verification

Last local verification: 2026-06-22 on macOS `26.5.1`, Swift `6.3.2`.

## Commands Run

```sh
./scripts/verify-release.sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" status
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" health
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" doctor
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" agent-status
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" export-proof --config "$HOME/Library/Application Support/MacAlarm/config.json" --output /tmp/MacAlarm-Proof-Verification
swift run MacAlarmApp
swift run macalarmctl notification-status
swift run macalarmctl test-notification --message "MacAlarm notification system is working"
swift run macalarmctl export-proof --config "$HOME/Library/Application Support/MacAlarm/config.json" --output /tmp/MacAlarm-Proof-SwiftPM
swift run macalarm-agent --duration 1
swift run macalarm-agent --verify-ledger
swift run macalarm-probe --self-test --duration 2
```

Manual app check:

```text
Open DMG, drag MacAlarm.app to Applications, then use Recorder > Install Recorder at Login...
File > Export Proof Bundle...
```

## Results

`./scripts/verify-release.sh` passed. This is the release-readiness gate used by CI. It checks:

- repository metadata
- Swift formatting
- SwiftUI background task policy
- SwiftUI main-thread IO policy
- SwiftUI AppKit boundary policy
- SwiftUI store boundary policy
- debug build
- custom Swift tests
- release app packaging
- app signature verification
- packaged helper smoke test using a temporary config, file-backed HMAC secret, and empty ledger
- zip checksum verification

The custom Swift tests passed:

- ledger appends and verifies
- ledger serializes concurrent appends into one valid chain
- ledger detects tampering
- ledger proof exporter waits for external exclusive lock
- ledger proof exporter writes valid proof bundle
- ledger proof exporter marks tampered ledger invalid
- event matching covers source, name, severity, and metadata
- rule cooldown suppresses repeated alarms
- threshold requires multiple events inside window
- default config encodes and validates
- config validation warns on development fallback key
- agent factory requires key unless development fallback is explicit
- agent factory initializes missing hmac key once
- secret material random key validates byte count
- secret material random key propagates provider failure
- secret material random key rejects short provider output
- file secret store round-trips hmac key with private permissions
- file secret store percent-encodes custom account names into one file
- file secret store rejects path traversal account names
- file secret store rejects symlink secret directory
- file secret store rejects non-regular secret path
- file secret store rejects insecure secret file permissions on read
- config validation rejects unsafe hmac key account
- installed secret initializer uses ledger-adjacent file secret
- custom log event payload round-trips
- notification test runner records delivery attempt
- remote checkpoint outbox writes pending POST payload
- launch agent plist contains agent and config paths
- launch agent manager builds stable lifecycle commands
- launch agent manager install writes default config, initializes secret, and plist
- launch agent manager install disables development fallback after secret init
- launch agent manager archives development fallback ledger before hardening
- installation paths derive user launch agent locations
- agent bounded run records heartbeat and checkpoint outbox
- main menu exposes enabled proof export command
- app notification service builds diagnostic alarm
- app installer helper copy replaces helpers with executable mode
- finder reveal target prepares directories and resolves files off-main
- background task helper propagates cancellation to detached work
- timeline ledger watch target resolves file and directory cases
- timeline ledger loader waits for external exclusive lock
- timeline loader reports continuity not HMAC verification
- timeline derived state filters hidden records unless search matches
- timeline derived state cancellation stops stale work
- timeline presentation prefers spotlight filter
- timeline default filters are stable unique built-ins
- timeline layout spreads dense nodes apart
- timeline layout signature ignores presentation-only changes
- timeline layout placeholder preserves request geometry
- timeline layout cancellation stops stale work
- timeline csv exporter quotes structured fields
- timeline record index gives constant-time selected lookup
- timeline store selects records and auto-opens inspector
- timeline store clears missing selected record after reload
- timeline store inspector toggle selects latest visible event
- timeline preferences round-trip in isolated defaults suite
- recorder health presentation classifies running, stale, and stopped states

The installed recorder health checks passed after reinstalling from the packaged app:

```json
{
  "isCurrent": true,
  "isHeartbeatFresh": true,
  "processRunning": true,
  "statusFileExists": true
}
```

The runtime status snapshot is written to `~/Library/Application Support/MacAlarm/runtime/status.json` with mode `0600`. `macalarmctl doctor` also verified the LaunchAgent and a valid hash-chain ledger. On the latest local reinstall, the active production ledger was intentionally fresh after archiving the older development-fallback ledger.

`macalarmctl export-proof` writes a protected proof directory containing:

- `events.jsonl`
- `verification.json`
- `summary.txt`
- `last-hash.txt`

The command exits `0` when the copied ledger verifies and `3` when tampering is detected.

`swift run MacAlarmApp` built and launched successfully, then was stopped after runtime smoke verification. The packaged app exposes `File > Export Proof Bundle...`, `View > Show Ledger Integrity`, and the native `Notifications` diagnostics/test menu.

`swift run macalarmctl notification-status` passed and reported the expected SwiftPM development state:

```json
{
  "authorizationStatus": "unavailable-unbundled-executable"
}
```

`swift run macalarmctl test-notification --message ...` passed:

```json
{
  "delivery": {
    "channel": "local-notification",
    "detail": "applescript-notification: display notification executed",
    "succeeded": true
  }
}
```

The test-notification path now records the manual test trigger and `notification.delivery.*` result into the HMAC ledger.

`swift run macalarm-agent --duration 1` fired the real `agent-started` alarm.

The default ledger then verified:

```json
{
  "isValid": true,
  "recordCount": 8
}
```

`swift run macalarm-probe --self-test --duration 2` passed:

- wrote and verified HMAC-chained ledger record
- fired edge and threshold rules
- emitted a synthetic session self-test event
- observed a DispatchSource file event on `.state/canary.txt`
- emitted and read a current-process OSLogStore event

## Important Caveat

The session self-test is synthetic. Real screen lock/unlock must be manually validated:

```sh
swift run macalarm-probe --session --duration 30
```

Then lock and unlock the Mac during that window. Expected event names are `screen.locked` and `screen.unlocked`.
