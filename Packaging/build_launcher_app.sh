#!/bin/bash
# Build "拾音盒子 Install.app" that asks for language, then opens the PKG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_PKG="${1:?usage: build_launcher_app.sh <product.pkg> <out.app>}"
OUT_APP="${2:?}"
VERSION="${3:-1.0.0}"
SCRIPT="$ROOT/Packaging/InstallLauncher.applescript"
ICON="$ROOT/Resources/AppIcon.icns"

rm -rf "$OUT_APP"
osacompile -o "$OUT_APP" "$SCRIPT"

RES="$OUT_APP/Contents/Resources"
mkdir -p "$RES"
cp -f "$PRODUCT_PKG" "$RES/PickupBox.pkg"
if [[ -f "$ICON" ]]; then
  cp -f "$ICON" "$RES/applet.icns"
  cp -f "$ICON" "$RES/AppIcon.icns"
fi

PLIST="$OUT_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 拾音盒子 Install" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string '拾音盒子 Install'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 拾音盒子 Install" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string '拾音盒子 Install'" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.kkfiles.PickupBox.Install" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.kkfiles.PickupBox.Install" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.utilities" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.utilities" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :NSHumanReadableCopyright 'Copyright © 2026 KK-Files'" "$PLIST" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string 'Copyright © 2026 KK-Files'" "$PLIST"

find "$OUT_APP" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true
xattr -cr "$OUT_APP" 2>/dev/null || true
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$OUT_APP"
else
  codesign --force --deep --sign - "$OUT_APP" 2>/dev/null || true
fi

echo "Built launcher: $OUT_APP"
