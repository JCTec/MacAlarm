#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${MACALARM_VERSION:-0.1.0}"
VOLUME_NAME="${MACALARM_DMG_VOLUME_NAME:-MacAlarm}"
SIGN_IDENTITY="${MACALARM_SIGN_IDENTITY:--}"
NOTARIZE="${MACALARM_NOTARIZE:-0}"
NOTARY_PROFILE="${MACALARM_NOTARY_PROFILE:-}"
NOTARY_KEYCHAIN="${MACALARM_NOTARY_KEYCHAIN:-}"
NOTARY_TIMEOUT="${MACALARM_NOTARY_TIMEOUT:-30m}"
FINDER_LAYOUT_MODE="${MACALARM_DMG_FINDER_LAYOUT:-auto}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacAlarm.app"
APP_ICON_ICNS="$ROOT_DIR/DesignAssets/AppIcon/MacAlarm.icns"
APP_ICON_PNG="$ROOT_DIR/DesignAssets/AppIcon/MacAlarm-AppIcon-1024.png"
WORK_DIR="$DIST_DIR/dmg-work"
STAGING_DIR="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/MacAlarm-rw.dmg"
FINAL_DMG="$DIST_DIR/MacAlarm-$VERSION.dmg"
CHECKSUM_FILE="$FINAL_DMG.sha256"
BACKGROUND_SCRIPT="$WORK_DIR/make-dmg-background.swift"
BACKGROUND_FILE="$STAGING_DIR/.background/MacAlarm-DMG-Background.png"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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

detach_if_needed() {
  if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap detach_if_needed EXIT

detach_existing_volume_mounts() {
  local mount
  while IFS= read -r mount; do
    hdiutil detach "$mount" >/dev/null 2>&1 || true
  done < <(
    find /Volumes -maxdepth 1 -type d \( -name "$VOLUME_NAME" -o -name "$VOLUME_NAME *" \) -print 2>/dev/null
  )
}

require_tool hdiutil
require_tool swift
require_tool ditto
require_tool shasum
require_tool codesign

if [[ "$FINDER_LAYOUT_MODE" != "auto" && "$FINDER_LAYOUT_MODE" != "required" && "$FINDER_LAYOUT_MODE" != "skip" ]]; then
  echo "MACALARM_DMG_FINDER_LAYOUT must be auto, required, or skip." >&2
  exit 1
fi

if [[ "${MACALARM_SKIP_RELEASE_BUILD:-0}" == "1" && -d "$APP_DIR" ]]; then
  section "Using existing release app"
else
  section "Building release app"
  "$ROOT_DIR/scripts/package-release.sh"
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing app bundle: $APP_DIR" >&2
  exit 1
fi

section "Preparing DMG staging"
rm -rf "$WORK_DIR" "$FINAL_DMG" "$CHECKSUM_FILE"
mkdir -p "$STAGING_DIR/.background"
ditto "$APP_DIR" "$STAGING_DIR/MacAlarm.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$BACKGROUND_SCRIPT" <<'SWIFT'
import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
let size = NSSize(width: 640, height: 420)
let image = NSImage(size: size)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    let rect = NSRect(x: point.x, y: point.y, width: 640 - point.x * 2, height: size + 10)
    text.draw(in: rect, withAttributes: attributes)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

image.lockFocus()

let canvas = NSRect(origin: .zero, size: size)
NSGradient(colors: [
    color(17, 24, 29),
    color(26, 34, 36),
    color(18, 23, 26),
])?.draw(in: canvas, angle: -28)

for x in stride(from: 0, through: 640, by: 40) {
    color(255, 255, 255, 0.035).setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: 0))
    path.line(to: NSPoint(x: x, y: 420))
    path.lineWidth = 1
    path.stroke()
}

for y in stride(from: 0, through: 420, by: 40) {
    color(255, 255, 255, 0.025).setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 0, y: y))
    path.line(to: NSPoint(x: 640, y: y))
    path.lineWidth = 1
    path.stroke()
}

drawRoundedRect(
    NSRect(x: 52, y: 44, width: 536, height: 314),
    radius: 24,
    fill: color(255, 255, 255, 0.055),
    stroke: color(255, 255, 255, 0.09)
)

if let icon = NSImage(contentsOf: iconURL) {
    icon.draw(
        in: NSRect(x: 258, y: 250, width: 124, height: 124),
        from: .zero,
        operation: .sourceOver,
        fraction: 0.18
    )
}

let accent = color(52, 199, 89)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 244, y: 196))
arrow.line(to: NSPoint(x: 396, y: 196))
arrow.lineCapStyle = .round
arrow.lineWidth = 5
accent.withAlphaComponent(0.9).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: 396, y: 196))
head.line(to: NSPoint(x: 378, y: 212))
head.move(to: NSPoint(x: 396, y: 196))
head.line(to: NSPoint(x: 378, y: 180))
head.lineCapStyle = .round
head.lineWidth = 5
accent.withAlphaComponent(0.9).setStroke()
head.stroke()

drawText("MacAlarm", at: NSPoint(x: 40, y: 332), size: 34, weight: .bold, color: color(240, 244, 246))
drawText("Drag to Applications", at: NSPoint(x: 40, y: 296), size: 17, weight: .semibold, color: color(174, 185, 190))

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not encode DMG background")
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outputURL)
SWIFT

section "Rendering DMG background"
swift "$BACKGROUND_SCRIPT" "$BACKGROUND_FILE" "$APP_ICON_PNG"

section "Creating writable DMG"
detach_existing_volume_mounts
hdiutil create \
  -size 160m \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  -ov \
  "$RW_DMG" >/dev/null

MOUNT_POINT="$(
  hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | awk -F '\t' '/\/Volumes\// {print $NF; exit}'
)"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Could not mount writable DMG." >&2
  exit 1
fi

section "Copying files into DMG"
ditto "$STAGING_DIR" "$MOUNT_POINT"

if [[ -f "$APP_ICON_ICNS" ]]; then
  cp "$APP_ICON_ICNS" "$MOUNT_POINT/.VolumeIcon.icns"
fi

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$MOUNT_POINT/.background" || true
  SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns" || true
  SetFile -a C "$MOUNT_POINT" || true
fi

layout_finder_window() {
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 760, 540}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:MacAlarm-DMG-Background.png"
    set position of item "MacAlarm.app" of container window to {178, 214}
    set position of item "Applications" of container window to {462, 214}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
}

case "$FINDER_LAYOUT_MODE" in
  skip)
    section "Skipping Finder window layout"
    echo "Finder layout skipped by MACALARM_DMG_FINDER_LAYOUT=skip."
    ;;
  auto|required)
    if ! command -v osascript >/dev/null 2>&1; then
      if [[ "$FINDER_LAYOUT_MODE" == "required" ]]; then
        echo "Missing required tool: osascript" >&2
        exit 1
      fi
      section "Skipping Finder window layout"
      echo "osascript is unavailable; continuing with drag-only DMG contents."
    else
      section "Laying out Finder window"
      if ! layout_finder_window; then
        if [[ "$FINDER_LAYOUT_MODE" == "required" ]]; then
          echo "Finder layout failed and MACALARM_DMG_FINDER_LAYOUT=required." >&2
          exit 1
        fi
        echo "Finder layout failed; continuing with drag-only DMG contents." >&2
      fi
    fi
    ;;
esac

if [[ -f "$APP_ICON_ICNS" ]]; then
  cp "$APP_ICON_ICNS" "$MOUNT_POINT/.VolumeIcon.icns"
fi

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns" || true
  SetFile -a C "$MOUNT_POINT" || true
fi

sync
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""

section "Compressing DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$FINAL_DMG" >/dev/null
rm -rf "$WORK_DIR"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  section "Signing DMG"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$FINAL_DMG"
  codesign --verify --strict "$FINAL_DMG"
elif [[ "$NOTARIZE" == "1" ]]; then
  echo "MACALARM_NOTARIZE=1 requires MACALARM_SIGN_IDENTITY to be a Developer ID identity." >&2
  exit 1
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "MACALARM_NOTARIZE=1 requires MACALARM_NOTARY_PROFILE." >&2
    echo "Create one with: xcrun notarytool store-credentials MacAlarmNotary --apple-id YOU@example.com --team-id TEAMID" >&2
    exit 1
  fi

  require_tool xcrun

  section "Submitting DMG for notarization"
  NOTARY_ARGS=(notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout "$NOTARY_TIMEOUT")
  if [[ -n "$NOTARY_KEYCHAIN" ]]; then
    NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
  fi
  xcrun "${NOTARY_ARGS[@]}"

  section "Stapling notarization ticket"
  xcrun stapler staple "$FINAL_DMG"
  xcrun stapler validate "$FINAL_DMG"
fi

shasum -a 256 "$FINAL_DMG" > "$CHECKSUM_FILE"

section "DMG packaged"
echo "DMG: $FINAL_DMG"
echo "Checksum: $CHECKSUM_FILE"
if [[ "$NOTARIZE" == "1" ]]; then
  echo "Notarization: stapled"
else
  echo "Notarization: skipped"
fi
