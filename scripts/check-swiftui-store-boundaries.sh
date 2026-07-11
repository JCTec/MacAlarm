#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_SUPPORT_DIR="Sources/MacAlarmAppSupport"
ALLOWED_FILE="$APP_SUPPORT_DIR/Timeline/TimelineScreen.swift"

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing required tool: rg" >&2
  exit 1
fi

matches="$(rg -n '@EnvironmentObject' "$APP_SUPPORT_DIR" || true)"
violations="$(awk -F: -v allowed="$ALLOWED_FILE" '$1 != allowed { print }' <<<"$matches")"

if [[ -n "$violations" ]]; then
  echo "@EnvironmentObject is limited to root/container views in $ALLOWED_FILE." >&2
  echo "Pass values, bindings, and callbacks into reusable SwiftUI leaves instead." >&2
  echo "$violations" >&2
  exit 1
fi

echo "SwiftUI store boundary checks passed."
