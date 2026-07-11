# SwiftUI Viewer

`MacAlarmApp` is the first real viewer-only macOS UI for MacAlarm.

The executable uses a small AppKit application shell with one explicit `NSWindow` hosting the SwiftUI timeline. That avoids SwiftPM/debug-bundle scene restoration edge cases while keeping the UI implementation in SwiftUI.

## Run

```sh
./scripts/run-viewer-debug.sh
```

`swift run MacAlarmApp` is still useful as a compile smoke test, but the debug launcher wraps the SwiftPM executable in a disposable `.app` bundle under `.build/` and opens it through Launch Services. That gives macOS normal window activation behavior.

## Current Behavior

- Reads the real JSONL ledger at `~/Library/Application Support/MacAlarm/events.jsonl`.
- Watches the ledger file for changes and reloads live.
- Shows the last 24 hours by default.
- Displays a horizontal left-to-right time spine.
- Oldest events are on the left, newest events on the right.
- Events branch above/below the central time spine.
- The right end cap is the live indicator.
- Event color and icon come from the first matching enabled timeline filter; the outer ring/stem emphasis represents severity.
- Timeline filter buttons cycle `normal -> spotlight -> hidden -> normal`.
- The filter settings sheet can enable/disable built-in button templates and create custom filters by source, event name, and metadata.
- The built-in `Other` button is intentionally absent; unmatched events stay out of the normal filtered timeline and can still be found through search.
- Search scans all events and marks hidden-filter results as hidden by filter.
- The right inspector opens on event selection.
- The inspector contains a vertical version of the visible timeline plus human summary, hash proof, and metadata.
- Ledger integrity is available from the health popover, ledger status badge, and `View > Show Ledger Integrity`.
- The top ledger badge reports live previous-hash continuity only; it intentionally does not claim HMAC verification.
- The integrity view performs full HMAC-backed verification in a background task.
- Proof bundle export is available from `File > Export Proof Bundle...` and runs ledger copy/verification off the main actor.
- Notification status, local test alerts, and System Settings access are available from the native `Notifications` menu.
- CSV copy is available from native macOS commands:
  - Copy selected event as CSV
  - Copy visible events as CSV

## Intentional v1 Limits

- Raw JSON is intentionally not prominent.
- Timeline renderer is SwiftUI view-based. Move to `Canvas` only if density/performance requires it.
- Filter settings are app-local viewer preferences, not agent-side recording rules.
- Long-running agent management should move through LaunchAgent installation, not hidden UI-side process spawning.

## Implementation Notes

- `TimelineStore` is the only broad timeline state container used by the root screen; reusable views receive values, bindings, and callbacks.
- `TimelineDerivedState` computes filtering/search output off-main and publishes one coherent display value.
- `TimelineLayoutEngine` computes placement off-main; `TimelineLayout`, `TimelineLayoutRequest`, and signatures live in separate value-model files.
- `MacAlarmBackgroundTask` is the app-side wrapper for detached work so cancellation behavior stays consistent.
- `MacAlarmAppActions` passes AppKit/menu commands into SwiftUI instead of letting rendering code reach into `NSApplication.shared.delegate`.
- Release gates enforce the main SwiftUI boundaries: background-task usage, main-thread IO avoidance, AppKit shell access, and store access.

## UX Decisions Locked In

- Horizontal historical timeline.
- Top timeline filter controls.
- Filter state cycle: normal, spotlight, hidden.
- Hidden means truly hidden, including critical events.
- Search can still find hidden events and marks them.
- Right inspector can be hidden and reopens when selecting an event.
- Inspector uses a vertical timeline to mirror the selected event context.
- Severity colors are muted and professional.
- Icons use SF Symbols.
