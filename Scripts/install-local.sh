#!/usr/bin/env bash
# Build RightKit, install it into /Applications and launch it.
#
#   ./Scripts/install-local.sh
#   IDENTITY="Developer ID Application: …" ./Scripts/install-local.sh
#
# Why not just ⌘R in Xcode: a Finder extension run from DerivedData (or from a mounted
# disk image) registers against a path that later moves or disappears, and pluginkit
# then keeps serving that stale copy. Testing the real thing means installing it
# properly, from /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-Release}"
DERIVED="${DERIVED:-$ROOT/build/DerivedData}"
STAGE="$ROOT/build/stage"
TARGET="/Applications/RightKit.app"
LOG="$ROOT/build/xcodebuild.log"

./Scripts/generate-project.sh >/dev/null

# Built unsigned on purpose: signing during the build would demand a provisioning
# profile for the App Group entitlement. Scripts/sign-app.sh signs the staged bundle
# afterwards, which needs only the certificate.
echo "==> Building ($CONFIG, unsigned)"
mkdir -p "$(dirname "$LOG")"
if ! xcodebuild -project RightKit.xcodeproj -scheme RightKit -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO ENTITLEMENTS_REQUIRED=NO \
  build >"$LOG" 2>&1; then
  echo "error: build failed — see $LOG" >&2
  grep -E "error:" "$LOG" | head -20 >&2 || true
  exit 1
fi

BUILT="$DERIVED/Build/Products/$CONFIG/RightKit.app"
[[ -d "$BUILT" ]] || { echo "error: $BUILT not found" >&2; exit 1; }

echo "==> Staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$BUILT" "$STAGE/RightKit.app"

TIMESTAMP=0 ./Scripts/sign-app.sh "$STAGE/RightKit.app" "${IDENTITY:-}"

echo "==> Quitting any running instance"
osascript -e 'tell application id "com.rightkit.app" to quit' >/dev/null 2>&1 || true
# A user can cancel quitting to keep an unsaved draft. Never replace or force-kill
# that running copy; finish the prompt and rerun this script instead.
for _ in {1..15}; do
  pgrep -x RightKit >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -x RightKit >/dev/null 2>&1; then
  echo "error: RightKit is still running. Save or finish its open dialog, then retry installation." >&2
  exit 1
fi
# Finder keeps extension workers alive independently of the menu-bar app. Stop only
# our workers so the next right-click loads this build and its current entitlements.
pkill -x RightKitFinderSync >/dev/null 2>&1 || true
sleep 1

[[ -d "$TARGET" ]] && { echo "==> Replacing $TARGET"; rm -rf "$TARGET"; }
ditto "$STAGE/RightKit.app" "$TARGET"
xattr -cr "$TARGET" 2>/dev/null || true

echo "==> Launching"
open "$TARGET"
sleep 2

echo
echo "Installed: $TARGET"
echo "Finder extension registrations:"
REGISTRATIONS="$(pluginkit -mAvvv -p com.apple.FinderSync 2>/dev/null \
  | grep -A2 com.rightkit | grep -E "^\+|^-|^!|Path =" || true)"
if [[ -z "$REGISTRATIONS" ]]; then
  echo "  (none yet — enable it in System Settings → General → Login Items & Extensions)"
else
  printf '%s\n' "$REGISTRATIONS" | sed 's/^/  /'
  # A registration pointing anywhere else wins over the one just installed and is the
  # single most common cause of "the menu disappeared".
  if printf '%s\n' "$REGISTRATIONS" | grep -q "Path = " \
     && ! printf '%s\n' "$REGISTRATIONS" | grep -q "Path = /Applications/RightKit.app"; then
    echo
    echo "WARNING: a registration points outside /Applications (old copy or mounted DMG)."
    echo "         Delete/eject that copy, then re-tick the extension in System Settings."
  fi
fi
