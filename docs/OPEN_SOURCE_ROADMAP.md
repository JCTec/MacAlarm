# Open-Source Roadmap

For the implementation-level version of this roadmap, see [Technical Plan](TECHNICAL_PLAN.md).

## Phase 0: Research Package

Status: current.

- Pure SwiftPM package.
- Swift 6 language mode.
- Native probe executable.
- Custom Swift test runner for minimal Command Line Tools environments.
- HMAC ledger, rule engine, session/file/log hooks, notifier interfaces.

## Phase 1: Developer Preview

- Add config file schema.
- Keep private file-backed ledger secrets as the default LaunchAgent install path.
- Add LaunchAgent plist generator.
- Add install/uninstall commands.
- Add heartbeat event source.
- Keep remote hash checkpoint adapter outbox-only until local notifications are stable.
- Add structured JSON logging for the agent itself.
- Add bundled app target so `UserNotifications` can become the primary production notification path.

## Phase 2: Stable Local Agent

- Signed release builds.
- Hardened runtime.
- Notarization pipeline.
- Homebrew formula.
- Telegram/webhook adapters after local notification behavior is stable.
- Manual QA checklist for supported macOS versions.
- CI on current and previous macOS major releases.
- Documentation for lock/unlock verification per macOS version.
- Evaluate migrating the custom test runner to Swift Testing once contributor toolchains make it the lower-friction option; the custom runner remains intentional for minimal Command Line Tools environments.

## Phase 3: Advanced Security

- Optional root LaunchDaemon for protected storage.
- Optional OpenBSM/auditd integration.
- Optional Endpoint Security helper after entitlement feasibility is confirmed.
- Remote append-only storage adapter.
- Rule pack format and signed rule bundles.

## Contribution Standards

- Keep collectors small and auditable.
- Normalize native framework details into `AlarmEvent`.
- Add tests for rule/ledger behavior before adding more hooks.
- Do not add hidden surveillance functionality.
- Do not add credential material to examples.
- Prefer Apple system frameworks over third-party dependencies.
