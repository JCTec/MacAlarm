# macOS Background Process Guide

This guide documents a project-agnostic way to ship a visible, user-trustworthy macOS background process from a normal app bundle.

The goal is not stealth. The goal is a boring, native macOS install flow where System Settings shows a friendly app name and icon, users understand what is running, and developers can verify, stop, uninstall, and clean up the background item predictably.

## Desired Result

After installation:

- the main app lives in `/Applications`
- the background process starts at user login
- System Settings shows a friendly product name, not a raw executable name
- Background Items uses an app/helper icon where macOS supports it
- the main app can install, start, stop, restart, and uninstall the recorder/helper
- logs, config, state, and local data live in documented per-user locations
- uninstall removes the background registration without deleting user evidence/data unless explicitly requested

## Recommended Apple Path

Use a bundled Login Item helper app registered with `SMAppService`.

Bundle shape:

```text
YourApp.app/
  Contents/
    Info.plist
    MacOS/YourApp
    Resources/AppIcon.icns
    Library/
      LoginItems/
        YourApp Recorder.app/
          Contents/
            Info.plist
            MacOS/YourApp Recorder
            Resources/AppIcon.icns
```

The helper app is what macOS treats as the background item. This matters for user trust because macOS UI can display the helper’s bundle name, identifier, and icon instead of a scary command-line executable.

## Naming Rules

Use human-facing names:

```text
Main app display name: YourApp
Helper display name: YourApp Recorder
Helper executable name: YourApp Recorder
```

Avoid names like:

```text
yourapp-agent
com.company.yourapp.agent
background-helper
daemon
```

Those names are technically clear to developers but bad for normal users. Background Items is a trust surface; make it look intentional.

Recommended bundle identifiers:

```text
Main app:   com.example.yourapp
Helper app: com.example.yourapp.recorder
```

## Helper `Info.plist`

The helper needs its own bundle metadata:

```xml
<key>CFBundleDisplayName</key>
<string>YourApp Recorder</string>
<key>CFBundleName</key>
<string>YourApp Recorder</string>
<key>CFBundleExecutable</key>
<string>YourApp Recorder</string>
<key>CFBundleIdentifier</key>
<string>com.example.yourapp.recorder</string>
<key>CFBundleIconFile</key>
<string>AppIcon</string>
<key>LSBackgroundOnly</key>
<true/>
```

Use `LSBackgroundOnly` when the helper has no UI. The main app owns all prompts, status, diagnostics, and controls.

## Registration Flow

The main app should register the helper after the user explicitly chooses an install/start action.

Swift sketch:

```swift
import ServiceManagement

func registerRecorder() throws {
    let service = SMAppService.loginItem(identifier: "com.example.yourapp.recorder")
    try service.register()
}

func unregisterRecorder() throws {
    let service = SMAppService.loginItem(identifier: "com.example.yourapp.recorder")
    try service.unregister()
}
```

Only call this from the installed app in `/Applications` or another stable user-approved install location. Avoid registering from a mounted DMG, Downloads, App Translocation, or a development temp path.

## Install UX

The DMG should be drag-only:

```text
YourApp.app
Applications
```

Do not put shell scripts, install commands, or setup docs in the DMG root. The DMG is transport. The app owns setup.

First launch flow:

1. User opens the app from Applications.
2. App explains what the background process records/does.
3. User clicks `Install Recorder`, `Start Background Recorder`, or equivalent.
4. App calls `SMAppService.loginItem(...).register()`.
5. If macOS asks for Background Items approval, app offers `Open System Settings`.
6. App shows health status after registration.

Keep wording calm and direct:

```text
Recorder not set up
Install the recorder to capture local events while the app is closed.
```

Avoid:

```text
Daemon failed
Launch service unavailable
Missing helper registration
```

Technical details belong in an expandable diagnostics view.

## Runtime Architecture

Keep responsibilities split:

```text
Main app:
  - user interface
  - install/start/stop/uninstall controls
  - settings
  - health display
  - data viewer
  - diagnostics

Background helper:
  - collect events
  - write local state/logs
  - send heartbeat/status snapshots
  - exit cleanly when asked
```

The helper should not depend on the main app window staying open.

## Local Data Layout

Use predictable per-user paths:

```text
~/Library/Application Support/YourApp/
  config.json
  data/
  runtime/status.json
  secrets/
  bin/

~/Library/Logs/YourApp/
```

If you use a fallback LaunchAgent, keep it obvious:

```text
~/Library/LaunchAgents/com.example.yourapp.agent.plist
```

Document every path. This reduces fear and makes uninstall support much easier.

## Status And Health

The helper should write a cheap status snapshot:

```json
{
  "state": "running",
  "processID": 12345,
  "generatedAt": "2026-06-22T20:00:00Z",
  "latestHeartbeatAt": "2026-06-22T20:00:00Z",
  "heartbeatCount": 42,
  "lastErrorDescription": null
}
```

The app reads this file to show a lightweight health pill:

```text
● Recorder running  Heartbeat 30s ago
```

After a few seconds, compact healthy states:

```text
● Heartbeat 30s ago
```

Keep unhealthy states verbose:

```text
Recorder stopped
Start the recorder to resume local capture.
```

## Logs

Write helper logs to:

```text
~/Library/Logs/YourApp/
  recorder.out.log
  recorder.err.log
```

The app should expose:

```text
Recorder > Open Recorder Logs
```

If Finder cannot open the path, show a clear user-facing message. Do not fail silently.

## Stop, Restart, And Uninstall

The app should expose native menu commands or settings buttons:

```text
Recorder > Install Recorder at Login...
Recorder > Start or Restart Recorder
Recorder > Stop Recorder
Recorder > Uninstall Recorder...
Recorder > Open Recorder Logs
```

For `SMAppService` login items, Apple does not provide a perfect "stop but stay registered" control. In many apps, stopping means unregistering and starting means registering again. Document this clearly.

Uninstall should remove registration and launch plist fallbacks, but preserve user data by default:

```text
Uninstall Recorder:
  - stop helper
  - unregister login item
  - remove fallback LaunchAgent plist
  - keep data/config/logs
```

Full local data reset should be a separate explicit action:

```text
Reset Local Data:
  - delete Application Support folder
  - delete Logs folder
  - delete preferences
```

## Fallback LaunchAgent

Prefer `SMAppService` with a bundled helper app.

Use a LaunchAgent fallback only for:

- development builds
- CLI diagnostics
- older compatibility paths
- recovery when the bundled login item cannot register

Fallback plist shape:

```xml
<key>Label</key>
<string>com.example.yourapp.agent</string>
<key>ProgramArguments</key>
<array>
  <string>/Users/me/Library/Application Support/YourApp/bin/yourapp-agent</string>
  <string>--config</string>
  <string>/Users/me/Library/Application Support/YourApp/config.json</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>KeepAlive</key>
<true/>
<key>StandardOutPath</key>
<string>/Users/me/Library/Logs/YourApp/agent.out.log</string>
<key>StandardErrorPath</key>
<string>/Users/me/Library/Logs/YourApp/agent.err.log</string>
```

Fallback LaunchAgents often display worse in System Settings than bundled login item helpers. Use them carefully.

## Verification Commands

Check process state:

```sh
pgrep -afil 'YourApp|yourapp' || true
```

Check launchd service:

```sh
launchctl print "gui/$(id -u)/com.example.yourapp.agent"
```

Check disabled/enabled override cache:

```sh
launchctl print-disabled "gui/$(id -u)" | grep -i yourapp || true
```

Check installed files:

```sh
find "$HOME/Library/Application Support" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents" "$HOME/Library/Preferences" \
  -maxdepth 4 \( -iname '*yourapp*' -o -iname '*com.example.yourapp*' \) -print 2>/dev/null
```

Check bundle metadata:

```sh
plutil -p "/Applications/YourApp.app/Contents/Info.plist"
plutil -p "/Applications/YourApp.app/Contents/Library/LoginItems/YourApp Recorder.app/Contents/Info.plist"
```

Check signing:

```sh
codesign --verify --deep --strict "/Applications/YourApp.app"
spctl --assess --type execute --verbose "/Applications/YourApp.app"
```

Local ad-hoc builds may fail Gatekeeper assessment. Public builds should use Developer ID signing, hardened runtime, and notarization.

## DMG Checklist

The DMG root should contain only:

```text
YourApp.app
Applications
```

Optional hidden visual assets are fine:

```text
.background/
.VolumeIcon.icns
.DS_Store
```

Audit:

```sh
hdiutil attach -readonly -noautoopen -noverify YourApp.dmg
ls -la /Volumes/YourApp
hdiutil detach /Volumes/YourApp
```

Reject DMGs that expose:

- install shell scripts
- uninstall shell scripts
- raw helper executables
- command-line tools
- setup text files in the root

Those belong inside the app or beside the release artifact for maintainers.

## Cleanup Script For Development

Use scoped cleanup only:

```sh
uid="$(id -u)"

for label in com.example.yourapp.agent com.example.yourapp.recorder com.example.yourapp; do
  launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
done

pkill -if 'YourApp|yourapp' >/dev/null 2>&1 || true

rm -rf \
  "/Applications/YourApp.app" \
  "$HOME/Applications/YourApp.app" \
  "$HOME/Library/Application Support/YourApp" \
  "$HOME/Library/Logs/YourApp" \
  "$HOME/Library/LaunchAgents/com.example.yourapp.agent.plist"

find "$HOME/Library/Preferences" -maxdepth 1 -type f \( \
  -name 'YourApp*.plist' -o \
  -name 'yourapp*.plist' -o \
  -name 'com.example.yourapp*.plist' \
\) -delete
```

Do not delete broad LaunchServices or Background Items databases from app scripts. macOS owns those caches.

## Background Items Cache Reality

System Settings may keep stale Background Items rows after development builds are removed. This can survive until logout or restart.

That does not mean the process is running.

Trust:

```sh
pgrep
launchctl print gui/UID/LABEL
known file paths
```

before assuming the system is still active.

## Public Distribution

For public release:

- sign the main app and helper with Developer ID
- enable hardened runtime
- notarize the app/DMG
- staple the ticket
- verify on a second Mac
- verify Background Items display name and icon
- verify install from `/Applications`, not from the DMG
- verify uninstall and cleanup behavior

Signing sketch:

```sh
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  "YourApp.app"
```

Notarization depends on your Apple account/profile setup.

## Common Mistakes

- Registering the helper from a mounted DMG.
- Shipping a raw executable as the background item.
- Letting System Settings show `yourapp-agent` instead of `YourApp`.
- Forgetting the helper icon.
- Putting install shell scripts in the DMG root.
- Deleting user data during recorder uninstall.
- Showing technical errors in the primary UI.
- Running heavy install/status checks on the main thread.
- Failing silently when Finder/System Settings cannot open.
- Treating stale Background Items cache rows as proof that the helper is still installed.

## Minimal Acceptance Test

1. Clean previous install.
2. Open DMG.
3. Drag app to Applications.
4. Open app from Applications.
5. Install recorder from inside the app.
6. Confirm System Settings shows a friendly name/icon.
7. Confirm helper starts at login.
8. Confirm app shows heartbeat/status.
9. Stop recorder.
10. Restart recorder.
11. Uninstall recorder.
12. Confirm no process is running.
13. Confirm data is preserved.
14. Run full local-data cleanup.
15. Confirm no known files remain outside Apple-managed caches.

