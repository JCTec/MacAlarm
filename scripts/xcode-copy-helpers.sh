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
xcrun swift build -c "$SWIFT_CONFIG" --product macalarm-agent --product macalarmctl
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
