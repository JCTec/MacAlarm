#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_SUPPORT_DIR="Sources/MacAlarmAppSupport"
ALLOWED_DIR="$APP_SUPPORT_DIR/App"

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing required tool: rg" >&2
  exit 1
fi

matches="$(rg -n '\bNSApp\b|NSApplication\.shared' "$APP_SUPPORT_DIR" || true)"
violations="$(awk -F: -v allowed="$ALLOWED_DIR/" '$1 !~ ("^" allowed) { print }' <<<"$matches")"

if [[ -n "$violations" ]]; then
  echo "NSApplication/NSApp shell access is limited to $ALLOWED_DIR." >&2
  echo "Pass AppKit commands into SwiftUI as focused value actions instead." >&2
  echo "$violations" >&2
  exit 1
fi

echo "SwiftUI AppKit boundary checks passed."
