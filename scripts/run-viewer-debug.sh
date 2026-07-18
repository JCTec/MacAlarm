#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c debug --product MacAlarmApp

swift build -c debug --product macalarm-agent --product macalarmctl

BIN_PATH="$(swift build -c debug --show-bin-path)"
EXECUTABLE="$BIN_PATH/MacAlarmApp"
APP_DIR="$ROOT_DIR/.build/MacAlarmApp-Debug.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_RESOURCES_DIR="$RESOURCES_DIR/bin"
APP_ICON_PATH="$ROOT_DIR/DesignAssets/AppIcon/MacAlarm.icns"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "MacAlarmApp executable was not found at $EXECUTABLE" >&2
  exit 1
fi

pkill -f "$APP_DIR/Contents/MacOS/MacAlarmApp" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/com.jctec.macalarm.debug.savedState"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$BIN_RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/MacAlarmApp"
cp "$BIN_PATH/macalarm-agent" "$BIN_RESOURCES_DIR/macalarm-agent"
cp "$BIN_PATH/macalarmctl" "$BIN_RESOURCES_DIR/macalarmctl"
chmod 755 "$BIN_RESOURCES_DIR/macalarm-agent" "$BIN_RESOURCES_DIR/macalarmctl"

if [[ -f "$APP_ICON_PATH" ]]; then
  cp "$APP_ICON_PATH" "$RESOURCES_DIR/MacAlarm.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
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
  <string>com.jctec.macalarm.debug</string>
  <key>CFBundleName</key>
  <string>MacAlarm</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open -n "$APP_DIR"

echo "Launched $APP_DIR"
echo "Ledger: $HOME/Library/Application Support/MacAlarm/events.jsonl"
