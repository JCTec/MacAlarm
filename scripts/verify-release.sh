#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${MACALARM_VERSION:-0.1.0}"
LOGIN_ITEM_BUNDLE_ID="${MACALARM_LOGIN_ITEM_BUNDLE_ID:-com.jc-tec.macalarm.recorder}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacAlarm.app"
CHECKSUM_FILE="$DIST_DIR/MacAlarm-$VERSION.zip.sha256"
ZIP_PATH="$DIST_DIR/MacAlarm-$VERSION.zip"
AGENT_PLIST="$APP_DIR/Contents/Library/LaunchAgents/com.jc-tec.macalarm.agent.plist"
LOGIN_ITEM_APP="$APP_DIR/Contents/Library/LoginItems/MacAlarm Recorder.app"
LOGIN_ITEM_INFO="$LOGIN_ITEM_APP/Contents/Info.plist"
LOGIN_ITEM_EXECUTABLE="$LOGIN_ITEM_APP/Contents/MacOS/MacAlarm"
LOGIN_ITEM_ICON="$LOGIN_ITEM_APP/Contents/Resources/MacAlarm.icns"

section() {
  echo
  echo "==> $1"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

require_tool swift
require_tool shasum
require_tool plutil
require_tool unzip

run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local command_pid="$!"

  (
    sleep "$seconds"
    if kill -0 "$command_pid" >/dev/null 2>&1; then
      kill -TERM "$command_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -KILL "$command_pid" >/dev/null 2>&1 || true
    fi
  ) &
  local watcher_pid="$!"

  set +e
  wait "$command_pid"
  local status="$?"
  set -e

  kill "$watcher_pid" >/dev/null 2>&1 || true
  wait "$watcher_pid" >/dev/null 2>&1 || true

  if [[ "$status" -eq 137 || "$status" -eq 143 ]]; then
    echo "Timed out after ${seconds}s: $*" >&2
    return 124
  fi

  return "$status"
}

section "Checking repository metadata"
./scripts/check-repository-metadata.sh

section "Checking Swift formatting"
./scripts/check-format.sh

section "Checking SwiftUI background task policy"
./scripts/check-swiftui-background-tasks.sh

section "Checking SwiftUI main-thread IO policy"
./scripts/check-swiftui-main-thread-io.sh

section "Checking SwiftUI AppKit boundary policy"
./scripts/check-swiftui-appkit-boundaries.sh

section "Checking SwiftUI store boundary policy"
./scripts/check-swiftui-store-boundaries.sh

section "Building debug products"
swift build -c debug

section "Running Swift tests"
swift run -c debug macalarm-tests

section "Packaging release app"
./scripts/package-release.sh

section "Verifying app signature"
if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$APP_DIR"
  codesign --verify --deep --strict "$LOGIN_ITEM_APP"
else
  echo "codesign not found; skipping signature verification"
fi

section "Verifying bundled ServiceManagement agent"
if [[ ! -d "$LOGIN_ITEM_APP" ]]; then
  echo "Missing bundled Login Item helper app: $LOGIN_ITEM_APP" >&2
  exit 1
fi
if [[ ! -x "$LOGIN_ITEM_EXECUTABLE" ]]; then
  echo "Missing executable Login Item helper: $LOGIN_ITEM_EXECUTABLE" >&2
  exit 1
fi
if [[ ! -f "$LOGIN_ITEM_ICON" ]]; then
  echo "Missing Login Item helper icon: $LOGIN_ITEM_ICON" >&2
  exit 1
fi
plutil -lint "$LOGIN_ITEM_INFO" >/dev/null
login_item_id="$(plutil -extract CFBundleIdentifier raw -o - "$LOGIN_ITEM_INFO")"
login_item_name="$(plutil -extract CFBundleDisplayName raw -o - "$LOGIN_ITEM_INFO")"
login_item_executable="$(plutil -extract CFBundleExecutable raw -o - "$LOGIN_ITEM_INFO")"
login_item_package_type="$(plutil -extract CFBundlePackageType raw -o - "$LOGIN_ITEM_INFO")"
login_item_background="$(plutil -extract LSBackgroundOnly raw -o - "$LOGIN_ITEM_INFO")"
if [[ "$login_item_id" != "$LOGIN_ITEM_BUNDLE_ID" ]]; then
  echo "Unexpected Login Item bundle id: $login_item_id" >&2
  exit 1
fi
if [[ "$login_item_name" != "MacAlarm" ]]; then
  echo "Unexpected Login Item display name: $login_item_name" >&2
  exit 1
fi
if [[ "$login_item_executable" != "MacAlarm" ]]; then
  echo "Unexpected Login Item executable: $login_item_executable" >&2
  exit 1
fi
if [[ "$login_item_package_type" != "APPL" ]]; then
  echo "Unexpected Login Item package type: $login_item_package_type" >&2
  exit 1
fi
if [[ "$login_item_background" != "true" ]]; then
  echo "Login Item helper must be background-only." >&2
  exit 1
fi

if [[ ! -f "$AGENT_PLIST" ]]; then
  echo "Missing bundled LaunchAgent plist: $AGENT_PLIST" >&2
  exit 1
fi
plutil -lint "$AGENT_PLIST" >/dev/null
agent_label="$(plutil -extract Label raw -o - "$AGENT_PLIST")"
agent_program="$(plutil -extract BundleProgram raw -o - "$AGENT_PLIST")"
if [[ "$agent_label" != "com.jc-tec.macalarm.agent" ]]; then
  echo "Unexpected bundled LaunchAgent label: $agent_label" >&2
  exit 1
fi
if [[ "$agent_program" != "Contents/Resources/bin/macalarm-agent" ]]; then
  echo "Unexpected bundled LaunchAgent BundleProgram: $agent_program" >&2
  exit 1
fi

section "Smoke testing packaged helpers"
BIN_RESOURCES_DIR="$APP_DIR/Contents/Resources/bin"
SMOKE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macalarm-release-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_DIR"' EXIT
SMOKE_CONFIG="$SMOKE_DIR/config.json"

run_with_timeout 10 "$BIN_RESOURCES_DIR/macalarmctl" default-config --output "$SMOKE_CONFIG" >/dev/null
plutil -replace storage.ledgerPath -string "$SMOKE_DIR/events.jsonl" "$SMOKE_CONFIG"
plutil -replace storage.runtimeDirectory -string "$SMOKE_DIR/runtime" "$SMOKE_CONFIG"
plutil -replace storage.outboxDirectory -string "$SMOKE_DIR/outbox" "$SMOKE_CONFIG"
plutil -replace filesystem.watchedPaths -json '[]' "$SMOKE_CONFIG"
plutil -replace heartbeat.enabled -bool NO "$SMOKE_CONFIG"
plutil -replace unifiedLog.enabled -bool NO "$SMOKE_CONFIG"

run_with_timeout 10 "$BIN_RESOURCES_DIR/macalarmctl" init-secret --config "$SMOKE_CONFIG" >/dev/null
run_with_timeout 10 "$BIN_RESOURCES_DIR/macalarm-agent" --config "$SMOKE_CONFIG" --verify-ledger >"$SMOKE_DIR/agent-verify.json"
run_with_timeout 10 "$BIN_RESOURCES_DIR/macalarmctl" verify-ledger --config "$SMOKE_CONFIG" >"$SMOKE_DIR/ctl-verify.json"

section "Verifying release checksum"
if [[ ! -f "$CHECKSUM_FILE" ]]; then
  echo "Missing checksum file: $CHECKSUM_FILE" >&2
  exit 1
fi

if unzip -l "$ZIP_PATH" | grep -E "\.command($|[[:space:]])" >/dev/null; then
  echo "Release zip must not expose command installers; recorder setup belongs inside MacAlarm.app" >&2
  exit 1
fi
unexpected_zip_roots="$(
  unzip -Z1 "$ZIP_PATH" \
    | awk -F/ '
        $1 != "" && $1 != "MacAlarm.app" && $1 != "__MACOSX" {
          roots[$1] = 1
        }
        END {
          for (root in roots) {
            print root
          }
        }
      '
)"
if [[ -n "$unexpected_zip_roots" ]]; then
  echo "Release zip must be app-only; unexpected root entries: $unexpected_zip_roots" >&2
  exit 1
fi

(
  cd "$DIST_DIR"
  shasum -a 256 -c "$(basename "$CHECKSUM_FILE")"
)

section "Release verification passed"
