# Security Model

MacAlarm should be treated as a local detection and alerting agent, not an anti-forensics rootkit or a perfect tamper-proof audit system.

## Protects Against

- casual local tampering with event history
- missed high-signal local events
- unauthorized or unexpected unlocks
- changes to canary/config files
- repeated suspicious events through threshold rules
- agent failure through heartbeat rules once implemented

## Does Not Fully Protect Against

- an attacker with root who can alter the binary, ledger, launchd config, or private secret file
- kernel-level compromise
- stolen notification/server credentials once network delivery is added
- macOS log schema changes
- disabled user-session delivery while the user is logged out

## Tamper Evidence

The ledger signs each record with HMAC-SHA256 over:

1. the normalized event
2. the previous record hash

Changing, deleting, or reordering records breaks verification unless the attacker also has the HMAC key. The default per-user background recorder stores that key in a private file under Application Support so background recording never blocks on Keychain UI.

Because a same-user attacker who obtains that key could rewrite or truncate the local chain, the agent also anchors the chain head outside its own trust domain. When `hashAnchor` is enabled (the default), the agent periodically writes the current record count and last hash to the destination named by `hashAnchor.destination`:

- `iCloudDrive` (the default) puts anchors in iCloud Drive so they leave the Mac through file sync. Unsandboxed builds resolve `~/Library/Mobile Documents/com~apple~CloudDocs/MacAlarm`. The sandboxed Mac App Store build resolves the app's iCloud **ubiquity container** — `url(forUbiquityContainerIdentifier: "iCloud.com.jc-tec.macalarm")/Documents/MacAlarm` — which appears in iCloud Drive as `~/Library/Mobile Documents/iCloud~com~jc-tec~macalarm/Documents/MacAlarm`.
- `directory` writes anchors to the literal `hashAnchor.directory` path, for pinning anchors to a specific local or third-party-synced folder.

A config written before `destination` existed decodes as `directory` and keeps writing to its configured path unchanged. `anchor-latest.json` is the fast comparison surface and `anchor-history.jsonl` is append-only, so rolling back the latest anchor is itself detectable. Anchors are written on agent start, on stop, and every `hashAnchor.anchorEveryHeartbeats` heartbeats; `LedgerAnchorComparison` reports truncation (fewer records than the anchor saw) and rewrites (a different hash at the anchored position). Anchor write failures never block recording: when iCloud is signed out (the ubiquity container resolves to nil) the agent records a single `anchor.write.failed` warning event, logs one attributed `.error`, and reports the last anchor status in `macalarmctl doctor`. This is a permanent attributed-failure state — the agent never quietly writes the anchor somewhere else.

The ledger coordinates cooperative local processes with advisory file locks. Writers hold an exclusive lock during append; verification, proof export, and the live timeline loader hold shared locks while reading ledger bytes, which prevents readers from copying a partial append from another MacAlarm process.

`macalarmctl export-proof` preserves a point-in-time copy of the ledger alongside `verification.json`, `summary.txt`, and `last-hash.txt` in a protected directory. The bundle is readable without MacAlarm and is intended for local incident review, bug reports, and future remote checkpoint comparison.

## Credential Handling

Do not store notification/server tokens or HMAC keys in source, plists, or world-readable config files.

Default config requires a stored HMAC key. The app installer and `macalarmctl agent-install` initialize a random 32-byte key in `~/Library/Application Support/MacAlarm/secrets` before starting the background recorder, then disable `secrets.allowDevelopmentFallbackKey` in the installed config once a real key exists. `macalarmctl init-secret --config PATH` can also initialize or rotate that installed key manually. If install detects a ledger that verifies with the older development fallback key, it archives that ledger and starts a fresh active production chain. `secrets.allowDevelopmentFallbackKey` exists only for local development and tests; config validation warns when it is enabled.

Production order:

1. Installed private file secret for the per-user background recorder.
2. Remote rotation process.
3. Remote ledger hash checkpoint.

MacAlarm does not use Keychain for the current background recorder install path. Background recording must not surprise users with a credential prompt; any future Keychain use needs an explicit visible app flow and documentation before it is enabled.

## Deployment Model

Start with a per-user background item because session notifications belong to the GUI login session. Add a root LaunchDaemon only when there is a concrete need for protected storage or privileged log access.

Endpoint Security should be a separate signed helper with explicit documentation, entitlement requirements, and user/admin consent.
