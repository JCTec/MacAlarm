#!/usr/bin/env bash
# Xcode build phase: build the macalarm-agent + macalarmctl helper executables
# with SwiftPM and drop them into the app bundle at Contents/Resources/bin, so a
# Cmd+R run mirrors the packaged app layout (see scripts/package-release.sh).
#
# Also:
#   - signs helpers with App Sandbox entitlements (Mac App Store requirement)
#   - copies helper dSYMs into DWARF_DSYM_FOLDER_PATH during Archive
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT_DIR"

HELPER_ENTITLEMENTS="$ROOT_DIR/Xcode/MacAlarmHelper.entitlements"
if [[ ! -f "$HELPER_ENTITLEMENTS" ]]; then
  echo "error: missing helper entitlements at $HELPER_ENTITLEMENTS" >&2
  exit 1
fi

# Map the Xcode configuration onto a SwiftPM build configuration.
case "${CONFIGURATION:-Debug}" in
  Release*) SWIFT_CONFIG="release" ;;
  *) SWIFT_CONFIG="debug" ;;
esac

echo "note: building helper executables ($SWIFT_CONFIG) with SwiftPM"
# Build one product per invocation (mirrors package-release.sh). A single
# multi-product `swift build` can short-circuit and skip a product when the
# shared .build tree is in a mixed/incremental state, leaving the helper
# missing; per-product builds are reliable.
for product in macalarm-agent macalarmctl; do
  xcrun swift build -c "$SWIFT_CONFIG" --product "$product"
done
BIN_PATH="$(xcrun swift build -c "$SWIFT_CONFIG" --show-bin-path)"

# The app bundle being built. TARGET_BUILD_DIR / UNLOCALIZED_RESOURCES_FOLDER_PATH
# are provided by Xcode; fall back to a sensible path for a manual invocation.
DEST_DIR="${TARGET_BUILD_DIR:-$ROOT_DIR/build}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-MacAlarm.app/Contents/Resources}/bin"
mkdir -p "$DEST_DIR"

# Prefer the expanded identity Xcode is using for this target (works for both
# Apple Development local runs and Apple Distribution archives). Fall back to
# ad-hoc only when no real identity is available.
SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
  SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
fi
if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "Sign to Run Locally" || "$SIGN_IDENTITY" == "Apple Development" || "$SIGN_IDENTITY" == "Apple Distribution" || "$SIGN_IDENTITY" == "Mac Developer" || "$SIGN_IDENTITY" == "Developer ID Application" ]]; then
  # CODE_SIGN_IDENTITY may be a certificate *type* rather than a concrete hash /
  # name. Prefer the expanded identity when present; otherwise ad-hoc for local
  # runs is acceptable and Xcode will re-sign the outer app.
  if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
    SIGN_IDENTITY="$EXPANDED_CODE_SIGN_IDENTITY"
  else
    SIGN_IDENTITY="-"
  fi
fi

sign_helper() {
  local binary="$1"
  local codesign_args=(--force --sign "$SIGN_IDENTITY" --entitlements "$HELPER_ENTITLEMENTS")
  # Hardened Runtime is required alongside sandbox for modern Mac distribution.
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign_args+=(--options runtime)
    # Avoid requiring a network timestamp during local debug builds; Archive /
    # distribution signing still stamps the outer app via Xcode.
    if [[ "${CONFIGURATION:-}" == Release* || "${ACTION:-}" == "install" ]]; then
      codesign_args+=(--timestamp)
    else
      codesign_args+=(--timestamp=none)
    fi
  fi
  codesign "${codesign_args[@]}" "$binary"
  codesign --verify --strict "$binary"
  # Confirm sandbox entitlement is embedded (App Store gate 90296).
  if ! codesign -d --entitlements - "$binary" 2>/dev/null | plutil -extract com.apple.security.app-sandbox raw -o - - 2>/dev/null | grep -q true; then
    # plutil extract on codesign XML stdout can be awkward; fall back to text check.
    if ! codesign -d --entitlements - "$binary" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
      echo "error: $binary is missing com.apple.security.app-sandbox entitlement" >&2
      codesign -d --entitlements - "$binary" 2>&1 || true
      exit 1
    fi
  fi
}

copy_helper_dsym() {
  local helper="$1"
  local dsym_src="$BIN_PATH/$helper.dSYM"
  # DWARF_DSYM_FOLDER_PATH is set by Xcode for configurations that produce
  # dSYMs (Release / Archive). Without this, App Store Connect reports missing
  # symbols for the nested helper executables.
  if [[ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
    return 0
  fi
  if [[ ! -d "$dsym_src" ]]; then
    echo "warning: no dSYM for $helper at $dsym_src (App Store symbol upload may fail)" >&2
    return 0
  fi
  mkdir -p "$DWARF_DSYM_FOLDER_PATH"
  rm -rf "$DWARF_DSYM_FOLDER_PATH/$helper.dSYM"
  cp -R "$dsym_src" "$DWARF_DSYM_FOLDER_PATH/$helper.dSYM"
  echo "note: copied $helper.dSYM -> $DWARF_DSYM_FOLDER_PATH"
}

for helper in macalarm-agent macalarmctl; do
  if [[ ! -x "$BIN_PATH/$helper" ]]; then
    echo "error: helper executable not found at $BIN_PATH/$helper" >&2
    exit 1
  fi
  install -m 755 "$BIN_PATH/$helper" "$DEST_DIR/$helper"
  echo "note: signing $helper with identity '$SIGN_IDENTITY' + sandbox entitlements"
  sign_helper "$DEST_DIR/$helper"
  copy_helper_dsym "$helper"
done

echo "note: bundled helpers into $DEST_DIR"

# ---------------------------------------------------------------------------
# Embed the SMAppService login item + LaunchAgent fallback (mirrors
# scripts/package-release.sh) so a Cmd+R / Archive build produces the exact
# App Store layout the sandboxed installer expects:
#   Contents/Library/LoginItems/MacAlarm Recorder.app   (SMAppService.loginItem)
#   Contents/Library/LaunchAgents/<AGENT_LABEL>.plist    (SMAppService.agent fallback)
# The login item is signed with the helper sandbox entitlements here, BEFORE
# Xcode signs the outer app (which happens after all build phases), giving the
# required inside-out signature order.
# ---------------------------------------------------------------------------
APP_CONTENTS_DIR="${TARGET_BUILD_DIR:-$ROOT_DIR/build}/${CONTENTS_FOLDER_PATH:-MacAlarm.app/Contents}"
LOGIN_ITEM_BUNDLE_ID="${MACALARM_LOGIN_ITEM_BUNDLE_ID:-com.jctec.macalarm.recorder}"
APP_BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.jctec.macalarm}"
AGENT_LABEL="com.jctec.macalarm.agent"
RECORDER_VERSION="${MARKETING_VERSION:-0.1.0}"
RECORDER_BUILD="${CURRENT_PROJECT_VERSION:-1}"
APP_ICON_PATH="$ROOT_DIR/DesignAssets/AppIcon/MacAlarm.icns"

LOGIN_ITEMS_DIR="$APP_CONTENTS_DIR/Library/LoginItems"
LOGIN_ITEM_APP_DIR="$LOGIN_ITEMS_DIR/MacAlarm Recorder.app"
LOGIN_ITEM_CONTENTS_DIR="$LOGIN_ITEM_APP_DIR/Contents"
LOGIN_ITEM_MACOS_DIR="$LOGIN_ITEM_CONTENTS_DIR/MacOS"
LOGIN_ITEM_RESOURCES_DIR="$LOGIN_ITEM_CONTENTS_DIR/Resources"
LAUNCH_AGENTS_DIR="$APP_CONTENTS_DIR/Library/LaunchAgents"

# Rebuild the login item from scratch so stale bundles never linger.
rm -rf "$LOGIN_ITEM_APP_DIR"
mkdir -p "$LOGIN_ITEM_MACOS_DIR" "$LOGIN_ITEM_RESOURCES_DIR" "$LAUNCH_AGENTS_DIR"

# The login item's main executable IS macalarm-agent (renamed to MacAlarm).
install -m 755 "$BIN_PATH/macalarm-agent" "$LOGIN_ITEM_MACOS_DIR/MacAlarm"
if [[ -f "$APP_ICON_PATH" ]]; then
  install -m 644 "$APP_ICON_PATH" "$LOGIN_ITEM_RESOURCES_DIR/MacAlarm.icns"
fi

cat > "$LOGIN_ITEM_CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>MacAlarm</string>
  <key>CFBundleExecutable</key>
  <string>MacAlarm</string>
  <key>CFBundleIconFile</key>
  <string>MacAlarm</string>
  <key>CFBundleIdentifier</key>
  <string>$LOGIN_ITEM_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>MacAlarm</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$RECORDER_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$RECORDER_BUILD</string>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST
plutil -lint "$LOGIN_ITEM_CONTENTS_DIR/Info.plist" >/dev/null

cat > "$LAUNCH_AGENTS_DIR/$AGENT_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AGENT_LABEL</string>
  <key>AssociatedBundleIdentifiers</key>
  <array>
    <string>$APP_BUNDLE_ID</string>
  </array>
  <key>BundleProgram</key>
  <string>Contents/Resources/bin/macalarm-agent</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST
plutil -lint "$LAUNCH_AGENTS_DIR/$AGENT_LABEL.plist" >/dev/null

# Sign the login item app bundle with the helper sandbox entitlements. Confirm
# the sandbox entitlement is embedded (App Store gate 90296) using the same
# check as the CLI helpers.
echo "note: signing login item '$LOGIN_ITEM_APP_DIR' with identity '$SIGN_IDENTITY' + sandbox entitlements"
login_item_codesign_args=(--force --sign "$SIGN_IDENTITY" --entitlements "$HELPER_ENTITLEMENTS")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  login_item_codesign_args+=(--options runtime)
  if [[ "${CONFIGURATION:-}" == Release* || "${ACTION:-}" == "install" ]]; then
    login_item_codesign_args+=(--timestamp)
  else
    login_item_codesign_args+=(--timestamp=none)
  fi
fi
codesign "${login_item_codesign_args[@]}" "$LOGIN_ITEM_APP_DIR"
codesign --verify --strict "$LOGIN_ITEM_APP_DIR"
if ! codesign -d --entitlements - "$LOGIN_ITEM_APP_DIR" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
  echo "error: login item is missing com.apple.security.app-sandbox entitlement" >&2
  codesign -d --entitlements - "$LOGIN_ITEM_APP_DIR" 2>&1 || true
  exit 1
fi

echo "note: embedded login item + LaunchAgent fallback into $APP_CONTENTS_DIR/Library"
