#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${MACALARM_VERSION:-0.1.0}"
BUNDLE_ID="${MACALARM_BUNDLE_ID:-com.jc-tec.macalarm}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacAlarm.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
LAUNCH_AGENTS_DIR="$CONTENTS_DIR/Library/LaunchAgents"
LOGIN_ITEMS_DIR="$CONTENTS_DIR/Library/LoginItems"
LOGIN_ITEM_APP_DIR="$LOGIN_ITEMS_DIR/MacAlarm Recorder.app"
LOGIN_ITEM_CONTENTS_DIR="$LOGIN_ITEM_APP_DIR/Contents"
LOGIN_ITEM_MACOS_DIR="$LOGIN_ITEM_CONTENTS_DIR/MacOS"
LOGIN_ITEM_RESOURCES_DIR="$LOGIN_ITEM_CONTENTS_DIR/Resources"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_RESOURCES_DIR="$RESOURCES_DIR/bin"
APP_ICON_PATH="$ROOT_DIR/DesignAssets/AppIcon/MacAlarm.icns"
AGENT_LABEL="com.jc-tec.macalarm.agent"
LOGIN_ITEM_BUNDLE_ID="${MACALARM_LOGIN_ITEM_BUNDLE_ID:-com.jc-tec.macalarm.recorder}"

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
require_tool plutil

section "Cleaning release build products"
swift package clean

section "Building release products"
for product in MacAlarmApp macalarm-agent macalarmctl; do
  swift build -c release --disable-build-manifest-caching --product "$product"
done
BIN_PATH="$(swift build -c release --show-bin-path)"

for executable in MacAlarmApp macalarm-agent macalarmctl; do
  if [[ ! -x "$BIN_PATH/$executable" ]]; then
    echo "Missing release executable: $BIN_PATH/$executable" >&2
    exit 1
  fi
done

section "Creating app bundle"
rm -rf "$APP_DIR"
rm -f \
  "$DIST_DIR/Install MacAlarm.command" \
  "$DIST_DIR/Uninstall MacAlarm.command" \
  "$DIST_DIR/INSTALLER.md"
mkdir -p "$MACOS_DIR" "$BIN_RESOURCES_DIR" "$LAUNCH_AGENTS_DIR" "$LOGIN_ITEM_MACOS_DIR" "$LOGIN_ITEM_RESOURCES_DIR"

install -m 755 "$BIN_PATH/MacAlarmApp" "$MACOS_DIR/MacAlarmApp"
install -m 755 "$BIN_PATH/macalarm-agent" "$BIN_RESOURCES_DIR/macalarm-agent"
install -m 755 "$BIN_PATH/macalarmctl" "$BIN_RESOURCES_DIR/macalarmctl"
install -m 755 "$BIN_PATH/macalarm-agent" "$LOGIN_ITEM_MACOS_DIR/MacAlarm"

if [[ -f "$APP_ICON_PATH" ]]; then
  install -m 644 "$APP_ICON_PATH" "$RESOURCES_DIR/MacAlarm.icns"
  install -m 644 "$APP_ICON_PATH" "$LOGIN_ITEM_RESOURCES_DIR/MacAlarm.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
  <string>MacAlarmApp</string>
  <key>CFBundleIconFile</key>
  <string>MacAlarm</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>MacAlarm</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS_DIR/Info.plist"

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
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST

plutil -lint "$LOGIN_ITEM_CONTENTS_DIR/Info.plist"

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
    <string>$BUNDLE_ID</string>
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

plutil -lint "$LAUNCH_AGENTS_DIR/$AGENT_LABEL.plist"

section "Adding release documentation"
cp "$ROOT_DIR/docs/INSTALLER.md" "$DIST_DIR/INSTALLER.md"

section "Code signing"
if command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY="${MACALARM_SIGN_IDENTITY:--}"
  APP_ENTITLEMENTS="$ROOT_DIR/Xcode/MacAlarm.entitlements"
  HELPER_ENTITLEMENTS="$ROOT_DIR/Xcode/MacAlarmHelper.entitlements"
  CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
  if [[ "$SIGN_IDENTITY" != "-" ]]; then
    CODESIGN_ARGS+=(--options runtime --timestamp)
    echo "Signing app with identity: $SIGN_IDENTITY"
  else
    echo "Signing app ad-hoc for local development."
  fi
  # Sign nested helpers first (inside-out), each with sandbox entitlements.
  for helper in macalarm-agent macalarmctl; do
    codesign "${CODESIGN_ARGS[@]}" --entitlements "$HELPER_ENTITLEMENTS" \
      "$BIN_RESOURCES_DIR/$helper"
  done
  if [[ -x "$LOGIN_ITEM_MACOS_DIR/MacAlarm" ]]; then
    codesign "${CODESIGN_ARGS[@]}" --entitlements "$HELPER_ENTITLEMENTS" \
      "$LOGIN_ITEM_APP_DIR"
  fi
  # Then the outer app bundle with its own entitlements.
  codesign "${CODESIGN_ARGS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
else
  echo "codesign not found; skipping signing"
fi

section "Creating zip artifact"
rm -f "$DIST_DIR/MacAlarm-$VERSION.zip" "$DIST_DIR/MacAlarm-$VERSION.zip.sha256"
(
  cd "$DIST_DIR"
  ditto -c -k --sequesterRsrc --keepParent "MacAlarm.app" "MacAlarm-$VERSION.zip"
  shasum -a 256 "MacAlarm-$VERSION.zip" > "MacAlarm-$VERSION.zip.sha256"
)

section "Packaged"
echo "App: $APP_DIR"
echo "Zip: $DIST_DIR/MacAlarm-$VERSION.zip"
echo "Checksum: $DIST_DIR/MacAlarm-$VERSION.zip.sha256"
