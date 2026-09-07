#!/usr/bin/env bash
# Package RightKit as a DMG.
#
#   ./Scripts/release.sh              # distributable: Developer ID + notarized + stapled
#                                     #   → dist/RightKit-<version>.dmg
#   LOCAL=1 ./Scripts/release.sh      # development-signed, no notarization
#                                     #   → dist/RightKit-<version>-dev.dmg
#   IDENTITY="Developer ID Application: …" ./Scripts/release.sh
#
# Only the default mode avoids a Gatekeeper override on the recipient's Mac:
#   * Apple Development signing  → first launch needs approval in System Settings
#   * ad-hoc signing             → pluginkit refuses to register the Finder extension
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-Release}"
DIST="${DIST:-$ROOT/dist}"
DERIVED="${DERIVED:-$ROOT/build/DerivedData}"
NOTARY_PROFILE="${NOTARY_PROFILE:-rightkit-notary}"
LOCAL="${LOCAL:-0}"

command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }
xcodebuild -version >/dev/null 2>&1 || { echo "error: full Xcode required" >&2; exit 1; }

# ------------------------------------------------------------------ identity
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning \
  | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [[ -z "$IDENTITY" && "$LOCAL" == "1" ]]; then
  # Local mode: any real certificate will do, as long as it carries a team.
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
if [[ -z "$IDENTITY" ]]; then
  cat >&2 <<EOF
error: no "Developer ID Application" identity in the keychain.

A DMG other people can open REQUIRES Developer ID + notarization:
  1. Apple Developer Program membership
  2. Create a "Developer ID Application" certificate and import it
  3. xcrun notarytool store-credentials $NOTARY_PROFILE \\
       --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>

To package for this machine only, run:  LOCAL=1 ./Scripts/release.sh
EOF
  exit 1
fi

# ------------------------------------------------------------------ version
read -r VERSION BUILD <<<"$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("project.yml").read_text()
print(
    re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text).group(1),
    re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text).group(1),
)
PY
)"
echo "==> RightKit $VERSION ($BUILD)"

STAGE="$DIST/stage"
APP="$STAGE/RightKit.app"
NOTE="安装说明.txt"
if [[ "$LOCAL" == "1" ]]; then
  DMG="$DIST/RightKit-$VERSION-dev.dmg"
else
  DMG="$DIST/RightKit-$VERSION.dmg"
fi
LOG="$DIST/xcodebuild.log"

./Scripts/generate-project.sh >/dev/null
rm -rf "$DERIVED" "$STAGE"
mkdir -p "$DIST" "$STAGE"

# ------------------------------------------------------------------ build
# Unsigned, then signed by Scripts/sign-app.sh: signing during the build needs a
# provisioning profile for the App Group entitlement (and therefore an Apple account
# signed into Xcode), while signing the staged bundle needs only the certificate.
echo "==> Building ($CONFIG, universal, unsigned)"
if ! xcodebuild -project RightKit.xcodeproj -scheme RightKit -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO ENTITLEMENTS_REQUIRED=NO \
  build >"$LOG" 2>&1; then
  echo "error: build failed — see $LOG" >&2
  grep -E "error:" "$LOG" | head -20 >&2 || true
  exit 1
fi

ditto "$DERIVED/Build/Products/$CONFIG/RightKit.app" "$APP"

# Signing is not optional even for a hand-shared build: an ad-hoc signature has no
# TeamIdentifier, and pluginkit then refuses to register the Finder extension — the
# app installs and the right-click menu simply never appears.
./Scripts/sign-app.sh "$APP" "$IDENTITY"

# ------------------------------------------------------------------ notarize
if [[ "$LOCAL" == "1" ]]; then
  echo "==> Skipping notarization (LOCAL=1)"
else
  echo "==> Notarizing app (profile=$NOTARY_PROFILE)"
  ZIP="$DIST/RightKit-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
  spctl -a -t open --context context:primary-signature -v "$APP"
fi

# ------------------------------------------------------------------ install note
# Shipped inside the DMG, not just next to it: whoever opens the image is the person
# who needs to read it.
if [[ "$LOCAL" == "1" ]]; then
  cat > "$STAGE/$NOTE" <<EOF
右键助手 (RightKit) $VERSION ($BUILD)

【安装】
1. 把「RightKit」拖进「应用程序」
2. 打开「应用程序」里的 RightKit
   —— 如果系统阻止首次打开，按下面【首次打开】操作
3. 按窗口里的设置向导，启用 Finder 扩展
4. 在 Finder 里右键任意文件 / 文件夹 →「右键助手」

务必从「应用程序」里打开，不要直接在这个磁盘映像里运行：
Finder 扩展会记住启动路径，映像一推出扩展就失效了。

【首次打开】
安装包已包含应用签名，不需要你自行签名、安装 Xcode 或运行终端命令。
本版本未经过 Apple 公证，macOS 可能会阻止首次打开。
遇到提示时，打开「系统设置 → 隐私与安全性」，找到 RightKit，
点击「仍要打开」，按系统提示确认，再重新打开应用。

【卸载】
退出菜单栏里的「右键助手」，把 /Applications/RightKit.app 拖进废纸篓即可。
EOF
else
  cat > "$STAGE/$NOTE" <<EOF
右键助手 (RightKit) $VERSION ($BUILD)

1. 把「RightKit」拖进「应用程序」
   务必从「应用程序」里打开，不要直接在这个磁盘映像里运行：
   Finder 扩展会记住启动路径，映像一推出扩展就失效了。
2. 打开 RightKit，按设置向导启用 Finder 扩展
3. 在 Finder 里右键 →「右键助手」

已通过 Apple 公证，双击即可打开。
EOF
fi
cp "$STAGE/$NOTE" "$DIST/$NOTE"

# ------------------------------------------------------------------ dmg
echo "==> Creating DMG"
ln -sf /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "右键助手 $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null

if [[ "$LOCAL" != "1" ]]; then
  # The DMG needs notarizing too: stapling only the app still leaves a Gatekeeper
  # prompt when the downloaded disk image itself is opened.
  echo "==> Notarizing DMG"
  DMG_ZIP="$DIST/RightKit-dmg-notarize.zip"
  ditto -c -k --keepParent "$DMG" "$DMG_ZIP"
  xcrun notarytool submit "$DMG_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$DMG_ZIP"
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
fi

echo
echo "Done: $DMG"
ls -lh "$DMG"
if [[ "$LOCAL" == "1" ]]; then
  cat <<EOF

NOT notarized — the app is signed, but first launch may need approval in
  System Settings → Privacy & Security → "Open Anyway".
  Recipients do not need to sign the app or run terminal commands.
  The DMG contains $NOTE with installation instructions.

  For a DMG that just opens on any Mac, you need a Developer ID Application
  certificate + notarization, then run ./Scripts/release.sh without LOCAL=1.
EOF
fi
