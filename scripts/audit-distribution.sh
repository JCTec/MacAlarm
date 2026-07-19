#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${MACALARM_VERSION:-0.1.0}"
LOGIN_ITEM_BUNDLE_ID="${MACALARM_LOGIN_ITEM_BUNDLE_ID:-com.jc-tec.macalarm.recorder}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacAlarm.app"
DMG_PATH="$DIST_DIR/MacAlarm-$VERSION.dmg"
DMG_CHECKSUM="$DMG_PATH.sha256"
ZIP_PATH="$DIST_DIR/MacAlarm-$VERSION.zip"
AGENT_PLIST_NAME="com.jc-tec.macalarm.agent.plist"
LOGIN_ITEM_RELATIVE_PATH="Contents/Library/LoginItems/MacAlarm Recorder.app"
LOGIN_ITEM_INFO="$APP_DIR/$LOGIN_ITEM_RELATIVE_PATH/Contents/Info.plist"
LOGIN_ITEM_EXECUTABLE="$APP_DIR/$LOGIN_ITEM_RELATIVE_PATH/Contents/MacOS/MacAlarm"
LOGIN_ITEM_ICON="$APP_DIR/$LOGIN_ITEM_RELATIVE_PATH/Contents/Resources/MacAlarm.icns"

WARNINGS=0

section() {
  echo
  echo "==> $1"
}

pass() {
  echo "[OK] $1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "[WARN] $1"
}

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required tool: $1"
  fi
}

require_file() {
  if [[ ! -e "$1" ]]; then
    fail "Missing required artifact: $1"
  fi
}

signature_authority() {
  local target="$1"
  codesign -dv --verbose=4 "$target" 2>&1 | awk -F= '/^Authority=/{print $2; exit}'
}

signature_flags() {
  local target="$1"
  codesign -dv --verbose=4 "$target" 2>&1 | awk -F= '/^CodeDirectory/{print $0; exit}'
}

assess_gatekeeper() {
  local type="$1"
  local target="$2"
  if spctl --assess --type "$type" -vv "$target" >/tmp/macal-spctl.out 2>&1; then
    pass "Gatekeeper assessment accepted $target"
  else
    warn "Gatekeeper assessment did not accept $target: $(tr '\n' ' ' </tmp/macal-spctl.out)"
  fi
  rm -f /tmp/macal-spctl.out
}

detach_if_needed() {
  if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap detach_if_needed EXIT

require_tool codesign
require_tool hdiutil
require_tool plutil
require_tool shasum
require_tool spctl
require_tool unzip
require_tool xcrun

section "Checking artifacts"
require_file "$APP_DIR"
require_file "$APP_DIR/Contents/Info.plist"
require_file "$APP_DIR/Contents/Resources/MacAlarm.icns"
require_file "$APP_DIR/Contents/Resources/bin/macalarm-agent"
require_file "$APP_DIR/Contents/Resources/bin/macalarmctl"
require_file "$APP_DIR/Contents/Library/LaunchAgents/$AGENT_PLIST_NAME"
require_file "$APP_DIR/$LOGIN_ITEM_RELATIVE_PATH"
require_file "$LOGIN_ITEM_INFO"
require_file "$LOGIN_ITEM_EXECUTABLE"
require_file "$LOGIN_ITEM_ICON"
require_file "$DMG_PATH"
require_file "$DMG_CHECKSUM"
pass "Required app, helper, bundled LaunchAgent, DMG, and checksum artifacts exist"

section "Checking app bundle metadata"
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$APP_DIR/Contents/Info.plist")"
display_name="$(plutil -extract CFBundleDisplayName raw -o - "$APP_DIR/Contents/Info.plist")"
executable="$(plutil -extract CFBundleExecutable raw -o - "$APP_DIR/Contents/Info.plist")"
[[ "$bundle_id" == "com.jc-tec.macalarm" ]] || fail "Unexpected bundle id: $bundle_id"
[[ "$display_name" == "MacAlarm" ]] || fail "Unexpected display name: $display_name"
[[ "$executable" == "MacAlarmApp" ]] || fail "Unexpected executable: $executable"
pass "App bundle metadata is coherent"

section "Checking bundled ServiceManagement LaunchAgent"
agent_plist="$APP_DIR/Contents/Library/LaunchAgents/$AGENT_PLIST_NAME"
plutil -lint "$agent_plist" >/dev/null
agent_label="$(plutil -extract Label raw -o - "$agent_plist")"
agent_program="$(plutil -extract BundleProgram raw -o - "$agent_plist")"
[[ "$agent_label" == "com.jc-tec.macalarm.agent" ]] || fail "Unexpected agent label: $agent_label"
[[ "$agent_program" == "Contents/Resources/bin/macalarm-agent" ]] || fail "Unexpected BundleProgram: $agent_program"
pass "Bundled LaunchAgent uses ServiceManagement BundleProgram"

section "Checking bundled Login Item helper"
plutil -lint "$LOGIN_ITEM_INFO" >/dev/null
login_item_id="$(plutil -extract CFBundleIdentifier raw -o - "$LOGIN_ITEM_INFO")"
login_item_name="$(plutil -extract CFBundleDisplayName raw -o - "$LOGIN_ITEM_INFO")"
login_item_executable="$(plutil -extract CFBundleExecutable raw -o - "$LOGIN_ITEM_INFO")"
login_item_background="$(plutil -extract LSBackgroundOnly raw -o - "$LOGIN_ITEM_INFO")"
[[ "$login_item_id" == "$LOGIN_ITEM_BUNDLE_ID" ]] || fail "Unexpected Login Item bundle id: $login_item_id"
[[ "$login_item_name" == "MacAlarm" ]] || fail "Unexpected Login Item display name: $login_item_name"
[[ "$login_item_executable" == "MacAlarm" ]] || fail "Unexpected Login Item executable: $login_item_executable"
[[ "$login_item_background" == "true" ]] || fail "Login Item helper must be background-only"
[[ -x "$LOGIN_ITEM_EXECUTABLE" ]] || fail "Login Item helper executable is not executable"
pass "Bundled Login Item helper has MacAlarm name, icon, executable, and background identity"

section "Checking app signature"
codesign --verify --deep --strict "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR/$LOGIN_ITEM_RELATIVE_PATH"
app_authority="$(signature_authority "$APP_DIR" || true)"
app_flags="$(signature_flags "$APP_DIR" || true)"
if [[ -z "$app_authority" ]]; then
  warn "App is ad-hoc signed. This is fine for local testing, not public distribution."
else
  pass "App signature authority: $app_authority"
fi
if [[ "$app_flags" == *"runtime"* ]]; then
  pass "App signature includes hardened runtime"
else
  warn "App signature does not show hardened runtime; Developer ID notarization should use --options runtime."
fi
assess_gatekeeper execute "$APP_DIR"

section "Checking DMG checksum and format"
(
  cd "$DIST_DIR"
  shasum -a 256 -c "$(basename "$DMG_CHECKSUM")"
)
format="$(hdiutil imageinfo "$DMG_PATH" | awk -F': ' '/^Format:/{print $2; exit}')"
[[ "$format" == "UDZO" ]] || fail "Unexpected DMG format: $format"
pass "DMG checksum and compressed read-only format are valid"

section "Checking DMG signature and notarization state"
if codesign --verify --strict "$DMG_PATH" >/tmp/macal-dmg-codesign.out 2>&1; then
  dmg_authority="$(signature_authority "$DMG_PATH" || true)"
  if [[ -n "$dmg_authority" ]]; then
    pass "DMG signature authority: $dmg_authority"
  else
    warn "DMG is ad-hoc signed or unsigned from a Developer ID perspective."
  fi
else
  warn "DMG is not code signed: $(tr '\n' ' ' </tmp/macal-dmg-codesign.out)"
fi
rm -f /tmp/macal-dmg-codesign.out

if xcrun stapler validate "$DMG_PATH" >/tmp/macal-stapler.out 2>&1; then
  pass "DMG has a valid stapled notarization ticket"
else
  warn "DMG is not stapled/notarized: $(tr '\n' ' ' </tmp/macal-stapler.out)"
fi
rm -f /tmp/macal-stapler.out
assess_gatekeeper open "$DMG_PATH"

section "Checking mounted DMG contents"
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/macalarm-distribution-audit.XXXXXX")"
hdiutil attach -readonly -noautoopen -noverify -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
require_file "$MOUNT_POINT/MacAlarm.app"
require_file "$MOUNT_POINT/Applications"
require_file "$MOUNT_POINT/.background/MacAlarm-DMG-Background.png"
require_file "$MOUNT_POINT/.VolumeIcon.icns"
require_file "$MOUNT_POINT/MacAlarm.app/Contents/Library/LaunchAgents/$AGENT_PLIST_NAME"
require_file "$MOUNT_POINT/MacAlarm.app/$LOGIN_ITEM_RELATIVE_PATH/Contents/Info.plist"
require_file "$MOUNT_POINT/MacAlarm.app/$LOGIN_ITEM_RELATIVE_PATH/Contents/MacOS/MacAlarm"
require_file "$MOUNT_POINT/MacAlarm.app/$LOGIN_ITEM_RELATIVE_PATH/Contents/Resources/MacAlarm.icns"
if find "$MOUNT_POINT" -maxdepth 1 -name "*.command" -print -quit | grep -q .; then
  fail "DMG must stay drag-and-drop only; found a .command installer at the DMG root"
fi
unexpected_entries=()
while IFS= read -r entry; do
  name="$(basename "$entry")"
  case "$name" in
    MacAlarm.app|Applications|.background|.VolumeIcon.icns|.DS_Store|.fseventsd|.Trashes)
      ;;
    *)
      unexpected_entries+=("$name")
      ;;
  esac
done < <(find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -print)
if [[ "${#unexpected_entries[@]}" -gt 0 ]]; then
  fail "DMG must stay drag-and-drop only; unexpected root entries: ${unexpected_entries[*]}"
fi
codesign --verify --deep --strict "$MOUNT_POINT/MacAlarm.app"
pass "Mounted DMG is drag-only: app, Applications alias, Finder background, volume icon, and signed app"
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""

section "Checking zip artifact"
if [[ -f "$ZIP_PATH" ]]; then
  if unzip -l "$ZIP_PATH" | grep -E "\.command($|[[:space:]])" >/dev/null; then
    fail "Release zip must not expose command installers; recorder setup belongs inside MacAlarm.app"
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
    fail "Release zip must be app-only; setup docs and installer controls belong outside the user-facing archive"
  fi
  pass "Release zip is app-only and does not expose command installers"
else
  warn "Zip artifact is missing: $ZIP_PATH"
fi

section "Distribution audit summary"
if [[ "$WARNINGS" -eq 0 ]]; then
  echo "Public distribution readiness: PASS"
else
  echo "Local distribution readiness: PASS"
  echo "Public distribution readiness: WARNINGS ($WARNINGS)"
  echo "Use Developer ID signing and MACALARM_NOTARIZE=1 for a public DMG."
fi
