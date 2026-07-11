#!/usr/bin/env bash
# Xcode build phase: build the macalarm-agent + macalarmctl helper executables
# with SwiftPM and drop them into the app bundle at Contents/Resources/bin, so a
# Cmd+R run mirrors the packaged app layout (see scripts/package-release.sh).
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT_DIR"

# Map the Xcode configuration onto a SwiftPM build configuration.
case "${CONFIGURATION:-Debug}" in
  Release*) SWIFT_CONFIG="release" ;;
  *) SWIFT_CONFIG="debug" ;;
esac

echo "note: building helper executables ($SWIFT_CONFIG) with SwiftPM"
xcrun swift build -c "$SWIFT_CONFIG" --product macalarm-agent --product macalarmctl
BIN_PATH="$(xcrun swift build -c "$SWIFT_CONFIG" --show-bin-path)"

# The app bundle being built. TARGET_BUILD_DIR / UNLOCALIZED_RESOURCES_FOLDER_PATH
# are provided by Xcode; fall back to a sensible path for a manual invocation.
DEST_DIR="${TARGET_BUILD_DIR:-$ROOT_DIR/build}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:-MacAlarm.app/Contents/Resources}/bin"
mkdir -p "$DEST_DIR"

for helper in macalarm-agent macalarmctl; do
  if [[ ! -x "$BIN_PATH/$helper" ]]; then
    echo "error: helper executable not found at $BIN_PATH/$helper" >&2
    exit 1
  fi
  install -m 755 "$BIN_PATH/$helper" "$DEST_DIR/$helper"
  # Ad-hoc sign so the nested Mach-O stays valid inside the (ad-hoc) app bundle.
  codesign --force --sign - "$DEST_DIR/$helper"
done

echo "note: bundled helpers into $DEST_DIR"
