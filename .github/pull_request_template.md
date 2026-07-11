## Summary

- 

## Verification

- [ ] `./scripts/check-format.sh`
- [ ] `./scripts/check-swiftui-appkit-boundaries.sh`
- [ ] `./scripts/check-swiftui-background-tasks.sh`
- [ ] `./scripts/check-swiftui-main-thread-io.sh`
- [ ] `./scripts/check-swiftui-store-boundaries.sh`
- [ ] `swift run -c debug macalarm-tests`
- [ ] `./scripts/verify-release.sh`
- [ ] `MACALARM_SKIP_RELEASE_BUILD=1 MACALARM_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh`
- [ ] `./scripts/audit-distribution.sh`

## Scope

- [ ] Agent / LaunchAgent
- [ ] SwiftUI viewer
- [ ] Installer / packaging
- [ ] Ledger / hash verification
- [ ] Notifications
- [ ] Custom events
- [ ] Documentation

## Safety

- [ ] This change does not add keylogging, screenshots, hidden surveillance, private-content capture, or macOS privacy bypasses.
- [ ] Any new event collection behavior is visible, documented, and consent-first.
- [ ] Public examples and logs do not include private ledger records, hostnames, paths, tokens, or secrets.

## Notes
