#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_SUPPORT_DIR="Sources/MacAlarmAppSupport"
ALLOWED_FILE="$APP_SUPPORT_DIR/App/MacAlarmBackgroundTask.swift"

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing required tool: rg" >&2
  exit 1
fi

violations="$(
  rg -n 'Task\.detached' "$APP_SUPPORT_DIR" \
    | awk -F: -v allowed="$ALLOWED_FILE" '$1 != allowed { print }'
)"

if [[ -n "$violations" ]]; then
  echo "Raw Task.detached calls are not allowed in MacAlarmAppSupport." >&2
  echo "Use MacAlarmBackgroundTask so cancellation behavior stays consistent." >&2
  echo "$violations" >&2
  exit 1
fi

echo "SwiftUI background task checks passed."
