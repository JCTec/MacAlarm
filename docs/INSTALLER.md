# MacAlarm Installer

MacAlarm ships as a drag-to-Applications macOS app.

The DMG is only a transport surface. It should show `MacAlarm.app` and the
Applications alias; recorder install/start controls belong inside
`MacAlarm.app` after the user opens the installed app.

The architecture is intentionally split:

- `MacAlarm.app` registers a visible per-user background recorder.
- `MacAlarm.app` reads the ledger and controls install/start/stop.

The app does not need to stay open for recording to continue.

## Package

From a source checkout:

```sh
./scripts/package-release.sh
```

This creates:

```text
dist/MacAlarm.app
dist/INSTALLER.md
dist/MacAlarm-0.1.0.zip
dist/MacAlarm-0.1.0.zip.sha256
```

The zip is intentionally app-only. `dist/INSTALLER.md` is written beside the
archive for maintainers, not bundled inside the user-facing archive.

To create a drag-to-Applications DMG:

```sh
./scripts/package-dmg.sh
```

The default packager tries to apply the polished Finder window layout. Use
`MACALARM_DMG_FINDER_LAYOUT=required ./scripts/package-dmg.sh` when validating
the visual install experience locally, or `MACALARM_DMG_FINDER_LAYOUT=skip`
for headless CI packaging.

This creates:

```text
dist/MacAlarm-0.1.0.dmg
dist/MacAlarm-0.1.0.dmg.sha256
```

The DMG contents are intentionally limited to:

```text
MacAlarm.app
Applications
```

The default DMG is ad-hoc signed for local testing. Public distribution should use a Developer ID identity and notarization:

```sh
MACALARM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MACALARM_NOTARIZE=1 \
MACALARM_NOTARY_PROFILE=MacAlarmNotary \
  ./scripts/package-dmg.sh
```

## Install

1. Open `dist/MacAlarm-0.1.0.dmg`.
2. Drag `MacAlarm.app` to `Applications`.
3. Open `MacAlarm.app` from Applications.
4. Use the in-app setup banner or choose `Recorder > Install Recorder at Login...`.
5. Confirm the visible app prompt.
6. If macOS requires Background Items approval, choose `Open System Settings` from the MacAlarm prompt and enable MacAlarm in Login Items & Extensions.

If you open MacAlarm directly from the DMG, Downloads, or another temporary location, recorder setup will stop and ask you to move the app to Applications first. This keeps macOS Background Items attached to a stable installed app.

Do not add installer command files, shell scripts, or setup documents to the
DMG root. Those make the install flow feel less native and less trustworthy.

The installer:

- uses bundled release binaries when installing from `dist`
- registers the bundled `Contents/Library/LoginItems/MacAlarm Recorder.app` with `SMAppService` when available
- falls back to the bundled `Contents/Library/LaunchAgents/dev.jc.macalarm.agent.plist` when the Login Item helper is unavailable
- keeps an installed helper fallback at `~/Library/Application Support/MacAlarm/MacAlarm.app`
- installs `macalarmctl` into `~/Library/Application Support/MacAlarm/bin`
- creates `~/Library/Application Support/MacAlarm/config.json` if needed
- creates a random ledger HMAC key in `~/Library/Application Support/MacAlarm/secrets` if the configured account is missing
- disables the development fallback key in config once a real installed key exists
- preserves existing config and active production ledger files
- archives an older development-fallback ledger into `~/Library/Application Support/MacAlarm/archives` before starting the production ledger
- writes `~/Library/LaunchAgents/dev.jc.macalarm.agent.plist` only when the app-bundled ServiceManagement path is unavailable
- starts the recorder immediately
- enables it to start again at login
- writes stdout/stderr logs to `~/Library/Logs/MacAlarm` for both native and fallback launches

## Verify

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" status
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" health
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" doctor
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" agent-status
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" export-proof \
  --config "$HOME/Library/Application Support/MacAlarm/config.json" \
  --output /tmp/MacAlarm-Proof
launchctl print "gui/$(id -u)/dev.jc.macalarm.agent"
tail -f "$HOME/Library/Logs/MacAlarm/agent.out.log"
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" verify-ledger \
  --config "$HOME/Library/Application Support/MacAlarm/config.json"
```

`macalarmctl status` reads the cheap runtime snapshot at `~/Library/Application Support/MacAlarm/runtime/status.json`.

`macalarmctl health` prints a one-screen human summary from that same runtime snapshot.

`macalarmctl doctor --json` emits the same health report as structured JSON for bug reports, local automation, or future machine checks.

`macalarmctl export-proof` writes a protected proof directory with the copied ledger, verification JSON, human summary, and latest hash. This is the easiest way to preserve evidence before sharing logs or debugging an incident.

`macalarmctl agent-status`, `agent-start`, `agent-stop`, `agent-restart`, `agent-install`, and `agent-uninstall` expose the legacy LaunchAgent control layer from Swift for diagnostics and automation. Normal users should install and remove the recorder from inside `MacAlarm.app`.

macOS may cache the old Login Items display name/icon after an upgrade from earlier development builds. If System Settings still shows `macalarm-agent`, log out and back in or remove the old Background Items row and reinstall. New packaged builds include a `MacAlarm Recorder.app` login item helper with the MacAlarm display name and icon.

## Stop

Choose `Recorder > Stop Recorder` in `MacAlarm.app`.

The app stops the background recorder while keeping local ledger/config/log files. For the native app-bundled background item, this removes the active `SMAppService` registration because Apple does not expose a separate "stop but stay registered" API for this service type. Use the in-app `Start Recorder` banner or choose `Recorder > Start or Restart Recorder` to start it again.

## Uninstall

Choose `Recorder > Uninstall Recorder...` in `MacAlarm.app`.

The app stops the background recorder, removes its registration, and removes the legacy fallback plist when present. It intentionally keeps local ledger/config/log files.

To remove all local data later:

```sh
rm -rf "$HOME/Library/Application Support/MacAlarm" "$HOME/Library/Logs/MacAlarm"
```

For a complete path-by-path cleanup and verification checklist, see [Uninstall And Local Data](UNINSTALL.md).

## Current Limits

- This installs a per-user background item, not a privileged LaunchDaemon.
- It starts at user login.
- It records while the user session is active.
- It cannot record before login or while the Mac is fully asleep.
- It does not hide itself.
