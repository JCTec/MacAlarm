# Human Checklist — GitHub presence & release automation

Repo settings, secrets, and one-time UI steps that only a maintainer with admin
access can do. Everything in code (workflows, README, wiki generator, release
pipeline) is already committed; these steps light it up.

## 1. Enable repository features

- **Settings → General → Features:** enable **Wikis** and **Discussions**.
- **Initialize the wiki:** open the **Wiki** tab and create any one page (e.g.
  "Home" with a word) and save. The wiki repo (`MacAlarm.wiki.git`) does not
  exist until the first page is created, and `Wiki Sync` needs it to clone.
  After that, every push to `main` touching `docs/**` regenerates the wiki.

## 2. Wiki push token (only if the default token is rejected)

`Wiki Sync` first tries the built-in `GITHUB_TOKEN`. GitHub often refuses wiki
pushes with it. If the workflow fails to push:

- Create a **fine-grained PAT** (or classic PAT with `repo` scope) that can write
  to this repository's wiki.
- Add it as **Settings → Secrets and variables → Actions → New secret** named
  `WIKI_TOKEN`. The workflow uses it automatically (`secrets.WIKI_TOKEN`).

## 3. Repository presentation

- **Description:** e.g. *"Consent-first macOS alarm recorder + live timeline with a
  tamper-evident ledger. Pure Swift, macOS 14+."*
- **Topics:** `macos`, `swift`, `swiftui`, `security`, `audit-log`, `app-sandbox`,
  `menu-bar`, `open-source`.
- **Social preview:** Settings → General → Social preview → upload
  `DesignAssets/Branding/macalarm-hero.png`.

## 4. Branch & tag protection

- **Branch protection on `main`** (Settings → Branches → Add rule):
  - Require a pull request before merging — **1 approval**.
  - Require status checks to pass — select the **CI** check
    (`Build, Test, Package`).
  - (Recommended) Require branches to be up to date; require CodeQL to pass.
- **Tag protection for `v*`** (Settings → Tags → New rule → pattern `v*`) so only
  maintainers can create/push release tags. This makes tags effectively immutable.

## 5. Signing & notarization secrets (for signed releases)

Without these, `Release` publishes an **unsigned prerelease**. To publish signed +
notarized DMGs, add all five secrets (Settings → Secrets and variables → Actions):

| Secret | What it is |
| --- | --- |
| `MACALARM_CERT_P12` | Base64 of your **Developer ID Application** certificate (`.p12`) |
| `MACALARM_CERT_PASSWORD` | The password you set when exporting the `.p12` |
| `NOTARY_KEY_ID` | App Store Connect API **Key ID** |
| `NOTARY_ISSUER_ID` | App Store Connect API **Issuer ID** |
| `NOTARY_KEY_P8` | Base64 of the API key **`.p8`** file |

**Export the Developer ID cert as base64 `.p12`:**
1. In **Keychain Access**, find *Developer ID Application: … (TEAMID)* with its
   private key, right-click → **Export** → `.p12`, set a password.
2. Encode it:
   ```sh
   base64 -i DeveloperID.p12 | pbcopy   # paste into MACALARM_CERT_P12
   ```
   Put the export password into `MACALARM_CERT_PASSWORD`.

**Create an App Store Connect API key (for notarytool):**
1. App Store Connect → **Users and Access → Integrations → App Store Connect API**
   → generate a key with the **Developer** role. Download the `.p8` (once only).
2. Copy the **Key ID** → `NOTARY_KEY_ID` and the **Issuer ID** (top of the page) →
   `NOTARY_ISSUER_ID`.
3. Encode the key:
   ```sh
   base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy   # paste into NOTARY_KEY_P8
   ```

> The signed path also requires the app's entitlements (App Sandbox, App Group,
> iCloud) to be authorized for your Developer ID / provisioning — see the app
> signing items in `HUMAN_CHECKLIST.md`.

## 6. Security features (recommended)

- **Settings → Code security:** enable **Dependabot alerts** and **Dependabot
  security updates** (the version-update config is already in
  `.github/dependabot.yml`).
- Enable **Code scanning**; the `CodeQL` workflow runs on PRs and weekly and will
  populate the Security tab once code scanning is on.
- Confirm the **Labels Sync** workflow ran (Actions tab) so the `area:*`, `type:*`,
  and workflow labels exist.

## Confirm

- Wiki tab shows generated pages with the MacAlarm sidebar.
- A test tag (e.g. `v0.0.1-test` on a throwaway) produces a GitHub Release with a
  DMG + `.sha256`; delete the test release/tag afterward.
- `main` cannot be pushed to directly; PRs require CI + review.
