# Release Checklist

This checklist is for maintainers preparing MacAlarm for a public release.

## Repository Readiness

- [x] Add a public `LICENSE` file (MIT).
- [ ] Confirm `README.md` describes the product, limits, install path, data locations, and safety boundaries.
- [ ] Confirm `SECURITY.md` has a private reporting path or a clear fallback process.
- [ ] Confirm issue templates and pull request template do not invite private logs or secrets.
- [ ] Confirm screenshots and generated assets do not reveal private machine data.
- [ ] Remove local exports, proof bundles, debug logs, and `.pyc` files that should not be public.

## Build Gate

```sh
./scripts/check-repository-metadata.sh
./scripts/check-format.sh
./scripts/check-swiftui-appkit-boundaries.sh
./scripts/check-swiftui-background-tasks.sh
./scripts/check-swiftui-main-thread-io.sh
./scripts/check-swiftui-store-boundaries.sh
./scripts/verify-release.sh
MACALARM_SKIP_RELEASE_BUILD=1 MACALARM_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh
./scripts/audit-distribution.sh
```

Expected artifacts:

```text
dist/MacAlarm.app
dist/MacAlarm-0.1.0.zip
dist/MacAlarm-0.1.0.zip.sha256
dist/MacAlarm-0.1.0.dmg
dist/MacAlarm-0.1.0.dmg.sha256
dist/INSTALLER.md
```

## Local Install QA

Use a clean user account or remove previous development installs first.

- [ ] Open the DMG.
- [ ] Confirm the DMG contains only `MacAlarm.app` and `Applications`.
- [ ] Drag `MacAlarm.app` to Applications.
- [ ] Open the app from Applications.
- [ ] Confirm the app asks to install/start the recorder from inside the app.
- [ ] Install the recorder.
- [ ] Approve Background Items if macOS asks.
- [ ] Confirm System Settings shows a friendly MacAlarm name and icon where macOS allows it.
- [ ] Confirm the live timeline opens with the last 24 hours.
- [ ] Lock and unlock the Mac, then confirm events appear.
- [ ] Send a test notification from the app menu.
- [ ] Run `macalarmctl health`.
- [ ] Run `macalarmctl doctor`.
- [ ] Export a proof bundle from the app.
- [ ] Stop and restart the recorder from the app menu.
- [ ] Uninstall the recorder from the app menu.

## Distribution Readiness

Local test builds may be ad-hoc signed. Public builds should use Developer ID signing and notarization:

```sh
MACALARM_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MACALARM_NOTARIZE=1 \
MACALARM_NOTARY_PROFILE=MacAlarmNotary \
  ./scripts/package-dmg.sh
```

Before publishing:

- [ ] Verify `codesign --verify --deep --strict dist/MacAlarm.app`.
- [ ] Verify notarization status.
- [ ] Verify `shasum -a 256 -c` for zip and DMG checksums.
- [ ] Download the uploaded artifact on another Mac and repeat install QA.

## Privacy And Safety Review

- [ ] No keylogging.
- [ ] No screenshots.
- [ ] No private-content capture.
- [ ] No hidden persistence.
- [ ] No privilege escalation without explicit user consent.
- [ ] No bypassing macOS privacy prompts.
- [ ] New event sources are documented in `ALARM_HOOKS.md`.
- [ ] New custom integrations are documented in `docs/CUSTOM_EVENTS.md`.

## Cleanup Review

After uninstalling a release candidate, verify there are no unexpected leftovers:

```sh
pgrep -afil 'MacAlarm|macalarm' || true
find "$HOME/Library/Application Support" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents" "$HOME/Library/Preferences" \
  -maxdepth 4 \( -iname '*macalarm*' -o -iname '*com.jc-tec.macalarm*' \) -print 2>/dev/null
```

Expected retained data depends on the uninstall mode:

- Recorder uninstall keeps ledger/config/logs.
- Full local-data cleanup removes known MacAlarm paths.
- macOS may retain Apple-managed Background Items metadata until logout or restart.
