# Notifications

Notification delivery is the current priority. Telegram and remote-server POST are intentionally not active runtime channels yet.

## Current Strategy

MacAlarm uses `ResilientLocalNotifier`:

1. Use `UserNotifications` when running from a real `.app` bundle.
2. Use AppleScript `display notification` as the fallback for SwiftPM/CLI development builds.

This split is necessary because `UNUserNotificationCenter.current()` can fail for an unbundled SwiftPM executable. The CLI detects that condition and avoids the crash.

## Commands

Check notification status:

```sh
swift run macalarmctl notification-status
```

Send a test alert:

```sh
swift run macalarmctl test-notification --message "MacAlarm local notification path is working"
```

`test-notification` records two tamper-evident ledger entries:

- `manual.notification.test`
- `notification.delivery.succeeded` or `notification.delivery.failed`

Run the real agent path briefly:

```sh
swift run macalarm-agent --duration 1
```

The default rule `agent-started` should raise an alarm. The alarm is printed to console and sent through the resilient local notifier.

## App UI

The packaged app exposes notification diagnostics through the native menu:

```text
Notifications > Notification Status
Notifications > Send Test Notification
Notifications > Open System Notification Settings
```

The diagnostics view shows authorization, alert, sound, and badge settings. Test delivery runs through the same `ResilientLocalNotifier` path as the CLI, but from the packaged `.app` context so `UserNotifications` can be the primary channel. The app delegate presents MacAlarm notifications while the app is foregrounded.

The app-side test alert uses the same core `NotificationTestRunner` as `macalarmctl test-notification`, so the test trigger and delivery result are written to the HMAC ledger.

## Verified Behavior

On this development machine, SwiftPM executables are not `.app` bundles, so `UserNotifications` is reported as:

```json
{
  "authorizationStatus": "unavailable-unbundled-executable"
}
```

The fallback path succeeded:

```json
{
  "channel": "local-notification",
  "detail": "applescript-notification: display notification executed",
  "succeeded": true
}
```

## Production Direction

For a polished macOS app release:

- continue hardening foreground/background notification presentation
- reflect disabled notification state in the top health strip
- detect Focus mode if macOS exposes a reliable supported signal
- use `SMAppService` for LoginItem/LaunchAgent registration
- keep AppleScript fallback for developer builds only

## Ledger Integration

Notification delivery results are recorded back into the ledger with source `notification` and event names:

- `delivery.succeeded`
- `delivery.failed`

That means the project can later prove not only that an event happened, but also that alert delivery was attempted.
