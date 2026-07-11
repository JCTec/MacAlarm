# Custom Events

MacAlarm can ingest custom events through macOS Unified Logging. This is useful for scripts, apps, build jobs, backup jobs, and security checks that already know something important happened and want it preserved in the tamper-evident ledger.

## Event Shape

Custom events are normalized into `AlarmEvent` values with:

```text
source: custom
name: your.event.name
severity: debug | info | notice | warning | critical
metadata: string key/value pairs
```

In the timeline, these events appear in the `Custom` category.

## Emit A Custom Event

From this repository:

```sh
swift run macalarmctl emit-log \
  --name script.backup.finished \
  --severity notice \
  --message "Nightly backup finished" \
  --metadata script=nightly-backup \
  --metadata status=ok
```

From an installed release bundle:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" emit-log \
  --name script.backup.finished \
  --severity notice \
  --message "Nightly backup finished" \
  --metadata script=nightly-backup \
  --metadata status=ok
```

The command writes a structured payload to Unified Logging using:

```text
subsystem: dev.jc.macalarm.custom
category: event
prefix: MACALARM_EVENT
```

You can override the subsystem or category if needed:

```sh
macalarmctl emit-log \
  --subsystem com.example.security \
  --category audit \
  --name ssh.key.rotation \
  --severity warning
```

If you use a custom subsystem, add a matching unified-log query to the MacAlarm config.

## Enable Agent Ingestion

Unified-log ingestion is disabled by default. Enable it in:

```text
~/Library/Application Support/MacAlarm/config.json
```

Minimal custom-event config:

```json
{
  "unifiedLog": {
    "enabled": true,
    "pollIntervalSeconds": 10,
    "queries": [
      {
        "name": "macalarm-custom-events",
        "scope": "system",
        "predicateFormat": "subsystem == 'dev.jc.macalarm.custom'",
        "lookbackSeconds": 30,
        "limit": 100
      }
    ]
  }
}
```

Keep the rest of the generated config fields intact. After editing:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" validate-config \
  --config "$HOME/Library/Application Support/MacAlarm/config.json"
launchctl kickstart -k "gui/$(id -u)/dev.jc.macalarm.agent"
```

## Alert On Custom Events

Rules can match custom events like any other source:

```json
{
  "id": "backup-failed",
  "match": {
    "source": "custom",
    "name": "script.backup.failed",
    "minimumSeverity": "warning",
    "metadataEquals": {
      "script": "nightly-backup"
    }
  },
  "severity": "critical",
  "message": "Nightly backup failed",
  "cooldownSeconds": 300
}
```

## Swift Producer Example

Any Swift app can emit the same payload:

```swift
import OSLog

let log = Logger(subsystem: "dev.jc.macalarm.custom", category: "event")
log.notice("MACALARM_EVENT {\"metadata\":{\"script\":\"nightly-backup\"},\"name\":\"script.backup.finished\",\"severity\":\"notice\"}")
```

For production producers, prefer using `JSONEncoder` to build the payload instead of hand-writing JSON.

## Notes

- Unified Logging is good for open integration because it is native and auditable.
- It is polling-based, so it is not as immediate as a future local XPC or Unix-domain socket ingestion API.
- System-scope log reads may be affected by macOS privacy policy and log retention.
- The agent deduplicates unified-log matches across polling windows to avoid repeatedly recording the same custom event.
