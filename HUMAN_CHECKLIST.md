# Human Checklist — sandbox-coherence

Steps that require a person, an Apple Developer account/credentials, iCloud
sign-in, or the running app. Everything machine-verifiable is covered by the
automated gates (see docs/SANDBOX_BEHAVIOR.md and the Part F gates). Each item
below states what to do and how to confirm it.

## Signing & capabilities (Apple Developer portal + Xcode)

1. **App Groups capability** — In the Apple Developer portal, add the App Group
   `S8662L649U.com.jc-tec.macalarm.shared` to both the app
   (`com.jc-tec.macalarm`) and the recorder login item
   (`com.jc-tec.macalarm.recorder`) App IDs, then enable the App Groups
   capability for the `MacAlarm` target in Xcode (Signing & Capabilities). The
   entitlement is already present in `Xcode/MacAlarm.entitlements` and
   `Xcode/MacAlarmHelper.entitlements`; the portal must authorize it for the
   provisioning profile.
   - Confirm: `xcodebuild -scheme MacAlarm build` succeeds with automatic
     signing, and the built app runs without an app-group sandbox denial in
     Console (`log stream --predicate 'subsystem == "dev.jc.macalarm.diagnostics"'`).

2. **iCloud (ubiquity container) capability** — Enable the iCloud capability
   with the container `iCloud.com.jc-tec.macalarm` for the app AND the recorder
   login item App IDs in the portal, and turn on iCloud → iCloud Documents for
   the `MacAlarm` target. Entitlement
   `com.apple.developer.ubiquity-container-identifiers` is already in both
   entitlements files.
   - Confirm: on a device signed into iCloud, the anchor writes appear under
     `~/Library/Mobile Documents/iCloud~com~jc-tec~macalarm/Documents/MacAlarm`.
   - Note: the namespace was renamed `com.jctec` → `com.jc-tec` for portal
     availability. Until the App Groups + iCloud capabilities are enabled for the
     new `com.jc-tec.macalarm` App IDs, `xcodebuild -scheme MacAlarm build` fails
     signing with: *"Provisioning profile … doesn't match the entitlements file's
     values for the com.apple.developer.ubiquity-container-identifiers and
     com.apple.developer.icloud-container-identifiers entitlements."* The build
     compiles and assembles the correct `com.jc-tec` product
     (`CODE_SIGNING_ALLOWED=NO build` succeeds); only the signature waits on the
     portal.

3. **verify-release.sh packaged-helper smoke test needs a real signing
   identity.** On macOS 26 (Darwin 25+), an *ad-hoc*-signed binary carrying
   `com.apple.security.app-sandbox` cannot launch standalone — it either SIGTRAPs
   or hangs and is killed by the sandbox (both observed; the exact mode varies
   with the entitlement set). This is OS behavior, independent of MacAlarm code:
   unsigned and no-entitlement builds of the same binary run instantly, and the
   bounded end-to-end spool test (F4) passes on the unsigned SwiftPM binaries.
   `scripts/verify-release.sh` runs the sandboxed helpers directly, so it only
   completes with a real identity:
   ```sh
   MACALARM_SIGN_IDENTITY="Apple Development: <you>" ./scripts/verify-release.sh
   ```
   - Note: every step of `verify-release.sh` *before* "Smoke testing packaged
     helpers" passes ad-hoc today (signature, login-item structure/bundle-id,
     LaunchAgent label/program). Only the standalone launch needs real signing.

## First-run approvals (running app)

4. **Background Items approval** — On first install of the recorder via the app,
   macOS routes the SMAppService login item to System Settings → General →
   Login Items ("Allow in the Background"). Approve it.
   - Confirm: the app's recorder status shows enabled (not "requires approval").

5. **iCloud-signed-in anchor sync check** — With iCloud signed in and the anchor
   destination set to `iCloudDrive`, let the agent run past one anchor interval
   and confirm `anchor-latest.json` + `anchor-history.jsonl` appear in the
   ubiquity container and sync to another device. Then sign out of iCloud and
   confirm the agent emits exactly one `anchor.write.failed` ledger event + one
   attributed `.error` log ("unavailable under App Sandbox: ..." / iCloud
   unavailable) and that `doctor` reports the last anchor status.

6. **Folder-selection watch test (running app)** — In the running sandboxed app,
   open "Watched Folders…", select a folder via the open panel, and confirm a
   security-scoped bookmark is persisted and re-resolved on relaunch. Touch a
   file in that folder and confirm a `filesystem`/`path.changed` event with
   metadata `origin=viewer-watch` reaches the ledger through the spool while the
   app is running.
