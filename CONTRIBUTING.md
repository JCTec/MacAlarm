# Contributing

MacAlarm is intended to be a consent-first macOS alarm project.

Security-sensitive reports should follow [SECURITY.md](SECURITY.md). Do not publish exploit details, private ledger records, hostnames, paths, tokens, or secrets in public issues or pull requests.

## Development

```sh
./scripts/check-repository-metadata.sh
./scripts/check-format.sh
./scripts/check-swiftui-appkit-boundaries.sh
./scripts/check-swiftui-background-tasks.sh
./scripts/check-swiftui-main-thread-io.sh
./scripts/check-swiftui-store-boundaries.sh
swift build
swift run -c debug macalarm-tests
swift run macalarm-probe --self-test --duration 2
```

Before opening a pull request that touches app code, the app bundle, or installer flow, run the full release gate:

```sh
./scripts/verify-release.sh
MACALARM_SKIP_RELEASE_BUILD=1 MACALARM_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh
./scripts/audit-distribution.sh
```

For the maintainer-facing public release pass, use [Release Checklist](docs/RELEASE_CHECKLIST.md).

## Branches, tags, and releases

- Day-to-day work lands on `main` via pull request; CI must be green.
- Releases are stabilized on a `release/x.y` branch cut from `main`. Every push
  to `release/**` runs the full CI gate suite (no artifacts).
- A release is published by pushing an annotated tag `vX.Y.Z` from the release
  branch; the [`Release`](.github/workflows/release.yml) workflow builds, signs +
  notarizes (or produces an unsigned prerelease when signing secrets are absent),
  and attaches the DMG to a GitHub Release.
- Hotfixes land on `main` first, then are cherry-picked onto the affected
  `release/x.y` branch and tagged as a new patch. **Tags are immutable** — never
  move a published tag; cut a new patch instead.

The full flow lives in [Releasing](docs/RELEASING.md).

## Documentation and the wiki

`docs/` is the source of truth. The project [Wiki](https://github.com/JCTec/MacAlarm/wiki)
is generated from `docs/**` (and this file) by the
[`Wiki Sync`](.github/workflows/wiki-sync.yml) workflow on every push to `main` —
edit the Markdown under `docs/`, not the wiki directly (direct wiki edits are
overwritten). New docs appear automatically; add a nice sidebar title in
`.github/scripts/build-wiki.py` if the derived one needs polish.

## Code Organization

- `MacAlarmCore` contains reusable event, ledger, rule, config, and notifier logic.
- Keep LaunchAgent behavior split by responsibility: lifecycle surface in `LaunchAgentManager`, command/status models, install preparation, secret hardening, ledger migration, process execution, and status parsing in focused helper files.
- `MacAlarmCLIKit` contains testable CLI command helpers; keep the `macalarmctl` executable target focused on command dispatch.
- `MacAlarmAppSupport` contains the reusable viewer implementation.
- `MacAlarmApp` is intentionally tiny and should remain only the executable entrypoint.
- App code is organized by feature: `App`, `State`, `Timeline`, `Inspector`, `Filters`, and `SharedUI`.
- Keep AppKit shell files split by responsibility: menu construction belongs in `MainMenuController`, while menu command handlers belong in focused action files.
- Pure app logic that can be tested without rendering SwiftUI belongs in `MacAlarmAppSupport/State` or `Timeline/Canvas`.
- Keep state contracts separate from shipped defaults and derived-state engines. For example, filter definitions, default filter templates, and display-state computation live in separate files.
- Keep `SharedUI` files focused on one reusable component or a tight design-system family; keep spacing/radius tokens in `DesignTokens`, and avoid catch-all toolbar/view files.
- Editor defaults are documented in `.editorconfig`; Git line-ending and binary handling are documented in `.gitattributes`.
- Swift formatting is enforced with `swift-format` through `.swift-format` and `./scripts/check-format.sh`.
- GitHub issue templates, PR template, security policy, and script permissions are checked with `./scripts/check-repository-metadata.sh`.
- Release readiness is enforced locally and in CI through `./scripts/verify-release.sh`, `./scripts/package-dmg.sh`, and `./scripts/audit-distribution.sh`.
- `Sources/MacAlarmTests/MacAlarmTests.swift` should stay a small orchestrator. Put reusable assertions and fixtures in `TestSupport.swift`; split core coverage across `CoreLedgerTests.swift`, `CoreRuleTests.swift`, `CoreConfigSecretTests.swift`, `CoreOperationsTests.swift`, and `CoreLaunchAgentTests.swift`; put CLI doctor helper behavior in `CLIKitTests.swift`, runtime smoke coverage in `AgentRuntimeTests.swift`, app shell/helper behavior in `AppSupportTests.swift`, timeline state/export behavior in `TimelineStateTests.swift`, timeline placement behavior in `TimelineLayoutTests.swift`, and store/preference behavior in `TimelineStoreTests.swift`.

## SwiftUI Guidelines

- Keep container views responsible for app state and leaf views responsible for rendering values.
- Prefer passing value models and callbacks into leaf views instead of broad `@EnvironmentObject` access.
- Keep `@EnvironmentObject` usage inside root/container views only; `./scripts/check-swiftui-store-boundaries.sh` enforces the current boundary.
- Keep AppKit delegate, menu, window, and system-setting commands in `MacAlarmAppSupport/App`; pass them into SwiftUI through focused action structs such as `MacAlarmAppActions`. `./scripts/check-swiftui-appkit-boundaries.sh` enforces this for `NSApplication`/`NSApp` shell access.
- Keep file reads, JSON decoding, layout placement, process waits, and other expensive work off the main actor.
- In `MacAlarmAppSupport`, use `MacAlarmBackgroundTask` for detached work so cancellation behavior stays consistent.
- Keep stores focused on orchestration and publication; move pure classification, layout, filtering, and export logic into separate helpers that can run off-main and be tested without SwiftUI.
- Do not call synchronous file-content APIs or spawn/wait on processes directly from `MacAlarmAppSupport`; `./scripts/check-swiftui-main-thread-io.sh` catches the obvious cases.
- Keep loaded timeline records and their lookup index together as a `TimelineRecordSet`; do not rebuild large indexes in main-actor property observers.
- Publish derived timeline state as a single value update; do not add separate `@Published` arrays for values that must stay in sync.
- Make expensive SwiftUI tasks cancellation-aware when their inputs can change quickly, especially timeline layout, search, and filtering paths.
- Add tests for derived state, layout, filtering, persistence, and core behavior when changing those areas.
- Prefer Apple frameworks and local helpers over new dependencies.

## Rules

- Keep the project pure Swift unless there is an explicit native API reason.
- Prefer Apple frameworks over third-party dependencies.
- Keep event collectors narrow and auditable.
- Add tests for core behavior and pure app-side behavior.
- Document any hook that requires manual verification, privileges, or entitlements.
- Do not add keylogging, screenshot capture, hidden surveillance, or private-content capture.
- Do not commit local ledgers, proof exports, app logs, host-specific screenshots, `.pyc` files, or built release artifacts unless the file is intentionally part of public documentation or a tagged release process.
