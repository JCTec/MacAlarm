# macOS Alarm Hook Matrix

Scope: authorized monitoring for your own Mac or managed machines. This project intentionally avoids keylogging, screenshots, hidden surveillance, and private-content capture.

## Hook Summary

| Hook | Swift API | Current status | Notes |
| --- | --- | --- | --- |
| Screen lock/unlock | `DistributedNotificationCenter` names `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` | Implemented, manual validation required | These names are practical macOS signals but should be tested on each supported macOS release. |
| Sleep/wake | `NSWorkspace.willSleepNotification`, `NSWorkspace.didWakeNotification` | Implemented | Good LaunchAgent signal. |
| Screen sleep/wake | `NSWorkspace.screensDidSleepNotification`, `NSWorkspace.screensDidWakeNotification` | Implemented | Useful when display state matters separately from system sleep. |
| App activate/launch/terminate | `NSWorkspace` notifications | Implemented | Good for correlation after unlock. Do not treat as app-content monitoring. |
| File/canary changes | `DispatchSource.makeFileSystemObjectSource` | Implemented and verified | Watches one file or directory descriptor. For recursive trees, add FSEvents later. |
| Recent unified log entries | `OSLogStore` | Implemented and verified for current process | System-wide security predicates may require privileges and can vary by macOS release. |
| Local notification | `UserNotifications` in app bundles, AppleScript fallback for SwiftPM CLI | Implemented and verified | SwiftPM executables are not `.app` bundles, so the fallback is the current dev path. |
| Telegram delivery | Future notifier adapter | Deferred | Local notifications are the current priority. |
| Remote server POST | Pending outbox payload model | Scaffolded, not sending | Writes POST-ready JSON payloads only when explicitly enabled. |
| Tamper-evident ledger | `CryptoKit.HMAC<SHA256>` | Implemented and verified | Detects tampering; does not prevent root/admin tampering. |
| launchd install | LaunchAgent/LaunchDaemon plist | Designed, not implemented | Production deployment should use a visible LaunchAgent first. |
| OpenBSM/auditd | system audit facility | Researched, not implemented | Powerful but noisy and operationally sensitive. |
| Endpoint Security | Apple Endpoint Security framework | Roadmap | Best high-fidelity process/file telemetry path, but requires entitlement/signing work. |

## Alarm Rule Types

- Edge rule: one event raises one alert, e.g. `screen.unlocked`.
- Cooldown rule: suppress repeated matches for a configured interval.
- Threshold rule: N events within a time window, e.g. repeated auth failures.
- Quiet-hours rule: only alert during sensitive local hours.
- Heartbeat rule: alert when the agent stops checking in.
- Tamper rule: alert when config, ledger, LaunchAgent, or canary files change.

## Recommended MVP

1. Visible per-user LaunchAgent.
2. Session hooks: lock, unlock, sleep, wake, screen sleep/wake.
3. Canary/config file watcher.
4. HMAC-chained JSONL ledger.
5. Rule engine with cooldown and threshold support.
6. Console/local notification dispatchers.
7. Heartbeat and missing-heartbeat alerts.
8. Optional OSLogStore reader for recent, narrow predicates.

## Production Additions

- Keychain-backed secret provider for HMAC credentials.
- Telegram and remote-server delivery after local notifications are stable.
- LaunchAgent installer/uninstaller with clear user-facing behavior.
- Signed release builds.
- Config schema with migration tests.
- Remote hash checkpoints.
- Privileged LaunchDaemon only for protected storage or privileged log access.
- Endpoint Security helper only after entitlement feasibility is confirmed.

## Sources

- Apple `NSWorkspace.didWakeNotification`: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification
- Apple `DistributedNotificationCenter`: https://developer.apple.com/documentation/foundation/distributednotificationcenter
- Apple `OSLogStore`: https://developer.apple.com/documentation/oslog/oslogstore
- Apple CryptoKit HMAC: https://developer.apple.com/documentation/cryptokit/hmac
- Apple Endpoint Security: https://developer.apple.com/documentation/endpointsecurity
- Apple launchd guide: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
