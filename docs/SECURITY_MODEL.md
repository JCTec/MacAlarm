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

Changing, deleting, or reordering records breaks verification unless the attacker also has the HMAC key. The default per-user background recorder stores that key in a private file under Application Support so background recording never blocks on Keychain UI; future remote checkpoints should periodically preserve the latest hash outside the Mac.

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
