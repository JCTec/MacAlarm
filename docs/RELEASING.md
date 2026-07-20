# Releasing

MacAlarm releases are cut from a **release branch**, published by **tagging**, and
built by the [`Release`](../.github/workflows/release.yml) workflow. `docs/` stays
the source of truth; this page documents the flow.

## Branch and tag model

1. **Stabilize on a release branch.** Branch `release/x.y` from `main` when a
   minor version is ready to harden:
   ```sh
   git switch main && git pull
   git switch -c release/1.2
   git push -u origin release/1.2
   ```
   Every push to `release/**` runs the **full CI gate suite** (metadata, format,
   the four SwiftUI checks, tests, `verify-release.sh`, DMG packaging, and the
   distribution audit) with **no uploaded artifacts** — it is a quality gate, not
   a build product.

2. **Tag from the release branch.** When the branch is green, tag the exact
   commit `vX.Y.Z` (annotated) and push the tag:
   ```sh
   git tag -a v1.2.0 -m "MacAlarm 1.2.0"
   git push origin v1.2.0
   ```
   The tag (`v*.*.*`) triggers the `Release` workflow.

3. **Hotfixes are cherry-picked.** Land the fix on `main` first, then cherry-pick
   it onto the affected `release/x.y` branch and tag a new patch (`vX.Y.Z+1`):
   ```sh
   git switch release/1.2
   git cherry-pick <sha-from-main>
   git push
   git tag -a v1.2.1 -m "MacAlarm 1.2.1" && git push origin v1.2.1
   ```

4. **Tags are immutable.** Never move or re-point a published tag. If a build is
   bad, tag a new patch version. (Re-pushing the *same* tag before a run finishes
   only cancels the stale run via the workflow's concurrency group — do not rely
   on it to replace a published release.)

## What the Release workflow does

Triggered by a `v*.*.*` tag on a `macos-14` runner:

1. **Derives the version** from the tag (`v1.2.0` → `1.2.0`) and threads it through
   `package-release.sh` / `package-dmg.sh` via the `MACALARM_VERSION` env override
   (default `0.1.0` for local runs).
2. **Runs the full gate suite** (`verify-release.sh`, `package-dmg.sh`,
   `audit-distribution.sh`).
3. **Signs and notarizes when secrets are present.** If `MACALARM_CERT_P12`,
   `MACALARM_CERT_PASSWORD`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, and
   `NOTARY_KEY_P8` are configured, it imports the Developer ID certificate into a
   throwaway keychain, signs the app + DMG with hardened runtime, notarizes the
   DMG with `notarytool` (App Store Connect API key), staples the ticket, and
   verifies with `spctl`.
4. **Falls back to an unsigned prerelease** when those secrets are absent: an
   ad-hoc build is published as a **prerelease** whose notes begin with
   `UNSIGNED BUILD — for testing only`.
5. **Publishes a GitHub Release** from the tag with auto-generated notes and
   attaches `MacAlarm-<version>.dmg` and its `.sha256`.

See [HUMAN_CHECKLIST-GITHUB.md](../HUMAN_CHECKLIST-GITHUB.md) for the one-time
setup of the signing/notary secrets and tag protection.

## Local dry run

Version threading can be exercised locally without a full build:

```sh
MACALARM_VERSION=9.9.9 MACALARM_SKIP_RELEASE_BUILD=1 \
  MACALARM_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh
# -> dist/MacAlarm-9.9.9.dmg
```
