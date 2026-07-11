# Security Policy

MacAlarm is a consent-first macOS alarm project. Please do not publish exploit details, private ledger records, hostnames, paths, tokens, or secrets in public issues or pull requests.

## Reporting

If the repository has GitHub private vulnerability reporting enabled, use that path first.

If no private advisory path is available, use the `Security contact request` issue template to ask for a private contact path. Include only the affected component and impact category. Do not include proof-of-concept code, private logs, secrets, or detailed exploit steps in the public issue.

## Scope

Security-sensitive areas include:

- ledger tamper evidence, hash-chain verification, or HMAC handling
- local secret storage and config file permissions
- LaunchAgent installation, persistence, or update behavior
- notification delivery paths
- custom event ingestion and parsing
- future remote checkpoint or server delivery code

## Project Boundaries

MacAlarm should not add:

- keylogging
- screenshots
- private-content capture
- hidden persistence
- stealth monitoring
- privilege escalation without explicit user consent
- bypasses for macOS privacy controls

Reports or pull requests proposing those behaviors will be closed unless they are defensive documentation or tests that help prevent them.
