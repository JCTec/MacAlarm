# Production Readiness

MacAlarm is designed as two separate pieces:

- `MacAlarm.app` helper: the background recorder, registered as a visible per-user background item.
- `MacAlarm.app`: the viewer/control surface, which reads the ledger and can install/start/stop the recorder.

The recorder must not depend on the app window being open.

## What Is Production-Ready In This Repo

- Release app bundle packaging via `scripts/package-release.sh`.
- App bundle includes:
  - `MacAlarmApp`
  - `macalarm-agent`
  - `macalarmctl`
- App bundle includes `Contents/Library/LoginItems/MacAlarm Recorder.app`, a background-only helper app with the MacAlarm name and icon, so the packaged app can register the recorder through `SMAppService.loginItem`.
- App bundle also includes `Contents/Library/LaunchAgents/com.jc-tec.macalarm.agent.plist` as the app-bundled `SMAppService.agent` fallback path.
- Installed helper fallback layout uses `~/Library/Application Support/MacAlarm/MacAlarm.app/Contents/MacOS/MacAlarm`. The installer signs the completed helper app after writing `Info.plist` and `MacAlarm.icns`, so legacy fallback installs still bind a MacAlarm identity to the background item where macOS supports it.
- The native app-bundled launch path redirects stdout/stderr into `~/Library/Logs/MacAlarm` from inside the agent because bundled login items and app-bundled `SMAppService` plists cannot contain per-user absolute log paths at build time.
- App menu includes Agent actions:
  - install and start at login
  - stop recorder
  - uninstall recorder
  - open logs
  - reveal ledger
- User-facing install is drag-to-Applications. Recorder setup lives inside the app.
- The per-user background recorder starts at login and keeps recording while the user session is active.
- App remains viewer-only for event data; the agent writes the ledger.

## Package A Release

From the repository root:

```sh
./scripts/package-release.sh
```

Artifacts:

```text
dist/
  MacAlarm.app
  INSTALLER.md
  MacAlarm-0.1.0.zip
  MacAlarm-0.1.0.zip.sha256
```

The zip archive is app-only. `INSTALLER.md` is emitted beside the archive for
maintainers and release notes, but recorder setup remains inside `MacAlarm.app`.

CI runs the same local release gate, then builds and audits the drag-only DMG.
The uploaded workflow artifacts are for review and testing; public distribution
still requires Developer ID signing and notarization.

For real-user drag install testing:

```sh
./scripts/package-dmg.sh
```

By default the DMG packager tries to apply the pretty Finder window layout.
For strict visual QA, require that layout step:

```sh
MACALARM_DMG_FINDER_LAYOUT=required ./scripts/package-dmg.sh
```

CI uses `MACALARM_DMG_FINDER_LAYOUT=skip` so headless hosted runners still
verify the app-only/drag-only artifact shape without relying on Finder UI
automation.

Additional artifacts:

```text
dist/
  MacAlarm-0.1.0.dmg
  MacAlarm-0.1.0.dmg.sha256
```

The app is ad-hoc signed by default. For a Developer ID signed build:

```sh
MACALARM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package-release.sh
```

For a Developer ID signed DMG:

```sh
MACALARM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  ./scripts/package-dmg.sh
```

For a notarized and stapled DMG, first store Notary credentials in the Keychain:

```sh
xcrun notarytool store-credentials MacAlarmNotary \
  --apple-id YOU@example.com \
  --team-id TEAMID
```

Then package, submit, wait, staple, validate, and checksum:

```sh
MACALARM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MACALARM_NOTARIZE=1 \
MACALARM_NOTARY_PROFILE=MacAlarmNotary \
  ./scripts/package-dmg.sh
```

## Install From DMG

1. Open `dist/MacAlarm-0.1.0.dmg`.
2. Drag `MacAlarm.app` to Applications.
3. Open `MacAlarm.app` from Applications.
4. Use the in-app setup banner or choose `Recorder > Install Recorder at Login...`.
5. Confirm the prompt.
6. If macOS requires Background Items approval, use MacAlarm's `Open System Settings` prompt and enable MacAlarm in Login Items & Extensions.

Recorder setup intentionally refuses packaged apps running from a mounted DMG, Downloads, App Translocation, or other unstable paths. Move `MacAlarm.app` to Applications and reopen it before installing the recorder.

The DMG itself is intentionally only a drag-and-drop surface: `MacAlarm.app` plus the Applications alias. Installer commands, setup documents, and recorder controls are app UI or repository documentation, not files in the disk image.

## Permissions

Current install does not require administrator permission because it registers a per-user background item. In packaged builds, the preferred registration is the app-bundled ServiceManagement login item:

```text
MacAlarm.app/Contents/Library/LoginItems/MacAlarm Recorder.app
```

The app-bundled LaunchAgent remains as a fallback:

```text
MacAlarm.app/Contents/Library/LaunchAgents/com.jc-tec.macalarm.agent.plist
```

Development and CLI fallback installs may write:

```text
~/Library/LaunchAgents/com.jc-tec.macalarm.agent.plist
```

macOS may still ask normal user-facing permissions depending on notification delivery behavior. MacAlarm should always ask through visible system prompts or explicit app dialogs. It must not bypass TCC or hide persistence.

## What "Always Recording" Means Today

The recorder starts at user login and keeps running independently from the app window.

It records while the user session is active:

- screen lock/unlock
- sleep/wake notifications available to the user session
- app lifecycle events
- configured watched-path changes
- heartbeats
- notification delivery records

It does not record:

- while the Mac is fully asleep
- before any user logs in
- from another user's GUI session
- root-only/pre-login events

Those require a later privileged LaunchDaemon or helper, and that should be designed separately with explicit administrator consent.

## Release Checklist

- `./scripts/verify-release.sh`
- Confirm the release gate passed repository metadata, Swift formatting, SwiftUI policy checks, tests, packaging, signing, helper smoke tests, and checksum verification
- For DMG distribution, run `./scripts/package-dmg.sh`
- `./scripts/audit-distribution.sh`
- `plutil -lint dist/MacAlarm.app/Contents/Info.plist`
- `codesign --verify --deep --strict dist/MacAlarm.app`
- `hdiutil imageinfo dist/MacAlarm-0.1.0.dmg`
- `shasum -a 256 -c dist/MacAlarm-0.1.0.dmg.sha256`
- Confirm the release gate smoke-tested packaged helper binaries and `macalarmctl`
- Open the DMG, drag `MacAlarm.app` to Applications, then open it from Applications
- Install the recorder from the in-app setup banner or `Recorder > Install Recorder at Login...`
- Verify `launchctl print "gui/$(id -u)/com.jc-tec.macalarm.agent"`
- Lock and unlock the Mac
- Confirm event appears in timeline
- Confirm ledger verifies
- Uninstall the recorder from the app

## Notarization

For public binary distribution outside local development:

- Sign with Developer ID Application.
- Enable hardened runtime.
- Notarize with Apple.
- Staple the notarization ticket.
- Publish SHA256 checksums.

`scripts/package-release.sh` enables hardened runtime and timestamping when `MACALARM_SIGN_IDENTITY` is not ad-hoc. `scripts/package-dmg.sh` can sign the DMG and, when `MACALARM_NOTARIZE=1`, submit it with `notarytool`, staple the ticket, validate the staple, and write the checksum after stapling.
