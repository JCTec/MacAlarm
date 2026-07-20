# MacAlarm Wiki

MacAlarm is a consent-first macOS alarm recorder and timeline viewer written in
pure Swift. It records meaningful local security and system events into a
tamper-evident HMAC hash-chain ledger and renders them in a live SwiftUI
timeline.

> This wiki is generated automatically from the [`docs/`](https://github.com/JCTec/MacAlarm/tree/main/docs)
> directory on every push to `main`. Edit the files under `docs/` in the
> repository — direct wiki edits are overwritten by the next sync.

## Start here

- **[Architecture](Architecture)** — package layout, hash-chain ledger, event
  spool transport, WatchService, and the module boundaries.
- **[Security Model](Security-Model)** — threat model, the HMAC hash chain, and
  off-device iCloud hash anchoring.
- **[Sandbox Behavior](Sandbox-Behavior)** — the full per-feature matrix of
  sandboxed vs unsandboxed behavior, with exact attributed-failure wording.

## Using MacAlarm

- **[Installer](Installer)** — how the recorder installs as a login item.
- **[Uninstall](Uninstall)** — removing MacAlarm and its local data.
- **[Custom Events](Custom-Events)** — emit structured events from scripts and
  tools with `macalarmctl emit-log`.
- **[Notifications](Notifications)** and **[Telegram](Telegram)** — delivery
  channels.

## Building & contributing

- **[Contributing](Contributing)** — build, test, and the branch/tag release
  flow.
- **[Releasing](Releasing)** — how tagged releases are built, signed, and
  published.
- **[Verification](Verification)** — the local gate suite.

The remaining pages (Technical Plan, SwiftUI Viewer, Logging Plan, Production
Readiness, and more) are listed in the sidebar.
