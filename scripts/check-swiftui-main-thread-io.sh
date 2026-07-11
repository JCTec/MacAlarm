#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_SUPPORT_DIR="Sources/MacAlarmAppSupport"

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing required tool: rg" >&2
  exit 1
fi

violations="$(
  rg -n 'Data\s*\(\s*contentsOf:|String\s*\(\s*contentsOf:|FileHandle\s*\(\s*forReadingFrom:|FileHandle\s*\(\s*forWritingTo:|\bProcess\s*\(|\.waitUntilExit\s*\(' "$APP_SUPPORT_DIR" || true
)"

if [[ -n "$violations" ]]; then
  echo "Potentially blocking file-content reads or process waits are not allowed directly in MacAlarmAppSupport." >&2
  echo "Move the work into MacAlarmCore services or wrap app-side work with MacAlarmBackgroundTask." >&2
  echo "$violations" >&2
  exit 1
fi

echo "SwiftUI main-thread IO checks passed."
