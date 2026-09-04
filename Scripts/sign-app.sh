#!/usr/bin/env bash
# Sign a staged RightKit.app inside-out.
#
#   ./Scripts/sign-app.sh <path-to-RightKit.app> [identity]
#
# Why sign after the build instead of letting Xcode do it: signing during the build
# needs a provisioning profile for the App Group entitlement, which in turn needs an
# Apple account signed into Xcode. Signing the staged bundle with explicit entitlements
# needs neither — just the certificate in the keychain — and produces exactly the same
# result (real TeamIdentifier, hardened runtime).
#
# Order matters: nested code first (framework → appex), outer app last. Signing the app
# first invalidates its seal the moment anything inside it is re-signed.
#
# TIMESTAMP=0 skips the secure timestamp (faster, local only — notarization needs it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
IDENTITY="${2:-}"

[[ -d "$APP" ]] || { echo "usage: $0 <path-to-RightKit.app> [identity]" >&2; exit 1; }

if [[ -z "$IDENTITY" ]]; then
  # Prefer a distribution certificate; fall back to the development one.
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
  [[ -n "$IDENTITY" ]] || IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: no codesigning identity in the keychain (need Apple Development or Developer ID Application)" >&2
  exit 1
fi
echo "==> Signing with: $IDENTITY"

FLAGS=(--force --options runtime --sign "$IDENTITY")
[[ "${TIMESTAMP:-1}" == "0" ]] || FLAGS+=(--timestamp)

FRAMEWORK="$APP/Contents/Frameworks/RightKitShared.framework"
APPEX="$APP/Contents/PlugIns/RightKitFinderSync.appex"

[[ -d "$APPEX" ]] || { echo "error: $APPEX missing — the extension was not embedded" >&2; exit 1; }

if [[ -d "$FRAMEWORK" ]]; then
  codesign "${FLAGS[@]}" "$FRAMEWORK"
fi
codesign "${FLAGS[@]}" \
  --entitlements "$ROOT/Extensions/RightKitFinderSync/RightKitFinderSync.entitlements" \
  "$APPEX"
codesign "${FLAGS[@]}" \
  --entitlements "$ROOT/Apps/RightKit/Resources/RightKit.entitlements" \
  "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
DETAILS="$(codesign -dv --verbose=2 "$APP" 2>&1)"
TEAM="$(printf '%s\n' "$DETAILS" | awk -F= '/^TeamIdentifier=/ {print $2}')"
if [[ -z "$TEAM" || "$TEAM" == "not set" ]]; then
  echo "error: no TeamIdentifier (ad-hoc signature) — pluginkit refuses to register the extension" >&2
  exit 1
fi
echo "    TeamIdentifier=$TEAM"
printf '%s\n' "$DETAILS" | awk -F= '/^Authority=/ {print "    "$0; exit}'
