# Telegram

MacAlarm can optionally send selected alarms to a Telegram bot owned by the user. This is not centralized: every user creates and configures their own Telegram bot token and their own approved chat IDs.

Telegram is disabled by default.

## Design

MacAlarm uses Telegram in two narrow ways:

- outbound alarm delivery with `sendMessage`
- optional command polling with `getUpdates`

The agent does not use webhooks in v1. Long polling is easier for a local Mac app because it does not require a public server, open inbound port, TLS endpoint, or centralized MacAlarm relay.

Incoming messages are command-only. Free-form chat is rejected with a short explanation.

## What Is Stored

The bot token is stored as a private file secret, not in `config.json`:

```text
~/Library/Application Support/MacAlarm/secrets/telegram-bot-token
```

The config stores non-secret Telegram settings:

```json
{
  "telegram": {
    "enabled": false,
    "botTokenAccount": "telegram-bot-token",
    "approvedChatIDs": [],
    "deniedChatIDs": [],
    "minimumSeverity": "warning",
    "includedRuleIDs": [],
    "includedEventSources": [],
    "commandsEnabled": true,
    "pollingEnabled": false,
    "pollingIntervalSeconds": 10,
    "updateLimit": 25
  }
}
```

## Setup

1. Create a bot with Telegram `@BotFather`.
2. Copy the token.
3. Store the token:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" telegram-set-token \
  --config "$HOME/Library/Application Support/MacAlarm/config.json" \
  --token "123456:ABC..."
```

For shell history hygiene:

```sh
printf '%s' "123456:ABC..." | \
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" telegram-set-token \
  --config "$HOME/Library/Application Support/MacAlarm/config.json" \
  --token-stdin
```

4. Enable Telegram in config:

```json
"telegram": {
  "enabled": true,
  "approvedChatIDs": [],
  "minimumSeverity": "warning",
  "commandsEnabled": true,
  "pollingEnabled": true
}
```

Keep the rest of the generated config fields intact.

5. Start a chat with your bot and send `/start`.
6. List pending chats:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" telegram-pending \
  --config "$HOME/Library/Application Support/MacAlarm/config.json"
```

7. Approve your chat:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" telegram-approve \
  --config "$HOME/Library/Application Support/MacAlarm/config.json" \
  --chat-id 123456789
```

8. Restart the recorder:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" agent-restart
```

9. Send a test message:

```sh
"$HOME/Library/Application Support/MacAlarm/bin/macalarmctl" telegram-test \
  --config "$HOME/Library/Application Support/MacAlarm/config.json" \
  --message "MacAlarm Telegram test"
```

## Approve And Deny

Unknown chats that message the bot are not allowed to run commands. MacAlarm records them as pending and replies:

```text
This MacAlarm bot only accepts commands from approved chats. Your chat was recorded as pending for the Mac owner.
```

List pending:

```sh
macalarmctl telegram-pending --config ~/Library/Application\ Support/MacAlarm/config.json
```

Approve:

```sh
macalarmctl telegram-approve --config ~/Library/Application\ Support/MacAlarm/config.json --chat-id 123456789
```

Deny:

```sh
macalarmctl telegram-deny --config ~/Library/Application\ Support/MacAlarm/config.json --chat-id 123456789
```

Approval and denial edit `config.json`. Restart the recorder after changing approved/denied chat IDs.

## Alarm Filters

By default, Telegram only reports alarms at `warning` or above.

Minimum severity:

```json
"minimumSeverity": "warning"
```

Only selected rule IDs:

```json
"includedRuleIDs": ["screen-unlocked", "canary-changed"]
```

Only selected event sources:

```json
"includedEventSources": ["session", "filesystem", "custom"]
```

Empty `includedRuleIDs` or `includedEventSources` means "do not filter by that field".

## Commands

Supported commands:

```text
/help
/status
/latest [type] [count]
/search YYYY-MM-DD YYYY-MM-DD [type]
```

Examples:

```text
/latest
/latest session 5
/latest screen.unlocked 3
/search 2026-06-01 2026-06-25 session
/status
```

`type` matches event source, event name, or `source.name`.

MacAlarm intentionally does not use an LLM for Telegram commands. Responses are deterministic command parsing over the local ledger.

## Current Limits

- Telegram is hidden/optional and configured through CLI/config in this version.
- The SwiftUI settings screen is not exposed yet.
- Incoming commands use long polling, not webhooks.
- The bot token is local to the Mac.
- Approved chat changes require recorder restart.
- Telegram messages are best-effort delivery and depend on Telegram availability.

## Security Notes

- Treat the bot token like a password.
- Approve only chats you control.
- Use a dedicated bot for MacAlarm.
- Do not share proof bundles, raw logs, hostnames, or paths in public Telegram groups.
- If the bot token is exposed, rotate it in `@BotFather`, then run `telegram-set-token` again.

## Official API References

- [Telegram Bot API](https://core.telegram.org/bots/api)
- `sendMessage`
- `getUpdates`

