# Uninstall And Local Data

MacAlarm should be easy to remove and easy to audit. This page documents what the app installs, what the in-app uninstall removes, and how to perform a full local-data cleanup during development or testing.

## Installed Components

A normal per-user install may create:

```text
/Applications/MacAlarm.app

~/Library/Application Support/MacAlarm/
  MacAlarm.app
  bin/macalarmctl
  config.json
  events.jsonl
  runtime/status.json
  secrets/ledger-hmac-key
  archives/

~/Library/Logs/MacAlarm/

~/Library/LaunchAgents/com.jc-tec.macalarm.agent.plist

~/Library/Mobile Documents/com~apple~CloudDocs/MacAlarm/     # unsandboxed iCloudDrive anchors
  anchor-latest.json
  anchor-history.jsonl

~/Library/Mobile Documents/iCloud~com~jc-tec~macalarm/Documents/MacAlarm/   # sandboxed (App Store) iCloudDrive anchors
  anchor-latest.json
  anchor-history.jsonl
```

The iCloud Drive `MacAlarm` folder holds ledger hash anchors (see `hashAnchor` in `config.json`). Its exact location depends on `hashAnchor.destination`:

- `iCloudDrive` (default): the unsandboxed build uses `~/Library/Mobile Documents/com~apple~CloudDocs/MacAlarm/`; the sandboxed Mac App Store build uses its ubiquity container `~/Library/Mobile Documents/iCloud~com~jc-tec~macalarm/Documents/MacAlarm/`. Both sync off the Mac by design; a full cleanup should remove the folder from iCloud Drive as well.
- `directory`: anchors live at the literal `hashAnchor.directory` path — remove that folder instead.

The sandboxed App Store build also keeps all of its ledger/config/secrets/runtime/outbox/spool state inside the App Group container at `~/Library/Group Containers/S8662L649U.com.jc-tec.macalarm.shared/`; removing that directory clears the sandboxed install. If `storage.maxLedgerFileBytes` is set, rotated ledger segments named `events-rotated-*.jsonl` sit beside `events.jsonl`.

Packaged builds prefer the visible login item helper bundled inside `MacAlarm.app`:

```text
MacAlarm.app/Contents/Library/LoginItems/MacAlarm Recorder.app
```

The LaunchAgent plist is the fallback path for development, diagnostics, and systems where the bundled login item path is unavailable.

## Stop Recording

In `MacAlarm.app`, choose:

```text
Recorder > Stop Recorder
```

This stops the active recorder but keeps local data.

For the bundled `SMAppService` login item, Apple does not expose a separate "stop but remain registered" state. Stopping removes the active registration. Start it again with:

```text
Recorder > Start or Restart Recorder
```

## Uninstall Recorder

In `MacAlarm.app`, choose:

```text
Recorder > Uninstall Recorder...
```

This removes the recorder registration and fallback LaunchAgent plist when present. It intentionally keeps the ledger, config, secrets, logs, and proof material.

Keeping local data is deliberate: users may need the ledger after an incident.

## Full Local Data Cleanup

Use this only when you really want to remove local MacAlarm state:

```sh
rm -rf \
  "/Applications/MacAlarm.app" \
  "$HOME/Applications/MacAlarm.app" \
  "$HOME/Library/Application Support/MacAlarm" \
  "$HOME/Library/Logs/MacAlarm" \
  "$HOME/Library/LaunchAgents/com.jc-tec.macalarm.agent.plist" \
  "$HOME/Library/LaunchAgents/com.jc-tec.macalarm.recorder.plist" \
  "$HOME/Library/LaunchAgents/com.jc-tec.macalarm.plist"
```

Optional development cleanup:

```sh
find "$HOME/Library/Preferences" -maxdepth 1 -type f \( \
  -name 'MacAlarm*.plist' -o \
  -name 'macalarm*.plist' -o \
  -name 'com.jc-tec.macalarm*.plist' \
\) -delete

find /private/tmp /var/tmp "${TMPDIR:-/tmp}" -maxdepth 5 \( \
  -iname '*macalarm*' -o \
  -iname '*com.jc-tec.macalarm*' \
\) -exec rm -rf {} +
```

Do not run broad system cleanup commands from project scripts. Keep uninstall behavior scoped to known MacAlarm paths.

## Verify Removal

```sh
pgrep -afil 'MacAlarm|macalarm' || true

uid="$(id -u)"
for label in com.jc-tec.macalarm.agent com.jc-tec.macalarm.recorder com.jc-tec.macalarm; do
  launchctl print "gui/$uid/$label" >/dev/null 2>&1 && echo "loaded $label" || echo "not loaded $label"
done

find "$HOME" \( \
  -path "$HOME/Dev/Logging System" -o \
  -path "$HOME/Dev/Logging System/*" \
\) -prune -o \( \
  -iname '*macalarm*' -o \
  -iname '*com.jc-tec.macalarm*' \
\) -print 2>/dev/null
```

The last command intentionally excludes a common source checkout path. Adjust it for your local clone.

## macOS Background Items Cache

macOS may keep stale Background Items or launchd override metadata after a development install is removed. That cache is Apple-managed and can survive until logout or restart.

This kind of stale row does not mean the recorder is running. Trust these checks first:

```sh
pgrep -afil 'MacAlarm|macalarm' || true
launchctl print "gui/$(id -u)/com.jc-tec.macalarm.agent"
```

If the service is not found and no process is running, the recorder is gone.

Avoid resetting all Background Items globally unless you are intentionally troubleshooting your own machine; it can affect unrelated apps.
