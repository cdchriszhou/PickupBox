#!/bin/bash
# Build PKG + DMG for 拾音盒子 / Pickup Box v1.0.0
# Critical: BundleIsRelocatable=false so Installer never redirects into the
# developer build folder (that made /Applications look "empty" after install).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="PickupBox"
DISPLAY_NAME="拾音盒子"
VERSION="1.0.0"
IDENTIFIER="com.kkfiles.PickupBox"
DIST_DIR="$ROOT/dist"
PKG_ROOT="$DIST_DIR/pkgroot"
COMPONENT_PKG="$DIST_DIR/PickupBox-component.pkg"
PRODUCT_PKG="$DIST_DIR/PickupBox-${VERSION}.pkg"
DMG_PATH="$DIST_DIR/PickupBox-${VERSION}.dmg"
DMG_STAGE="$DIST_DIR/dmg"

# 签名身份（可选）：
#   SIGN_IDENTITY="拾音盒子 Developer" make installer
# 不设则 ad-hoc（codesign -s -），本机可跑；发给别人仍会提示「无法验证开发者」。
# PKG 另可用 INSTALLER_IDENTITY；不设则复用 SIGN_IDENTITY。
# 自签证书：钥匙串访问 → 证书助理 → 创建证书 → 身份类型「自签名根证书」→ 证书类型「代码签名」。
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$SIGN_IDENTITY}"

sign_app() {
  local target="$1"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "    codesign (named): $SIGN_IDENTITY → $target"
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$target"
  else
    codesign --force --deep --sign - "$target" 2>/dev/null || true
  fi
}

sign_pkg() {
  local src="$1"
  local dst="$2"
  if [[ -n "$INSTALLER_IDENTITY" ]]; then
    echo "    productsign: $INSTALLER_IDENTITY"
    productsign --sign "$INSTALLER_IDENTITY" "$src" "$dst"
    mv -f "$dst" "$src"
  fi
}

# Build into a writable staging tree (avoid root-owned build/ from old relocate installs)
WORK="$DIST_DIR/work"
APP_SRC="$WORK/${APP_NAME}.app"
echo "==> Building app into $APP_SRC …"
rm -rf "$WORK"
mkdir -p "$WORK"
make -j"$(sysctl -n hw.ncpu)" \
  APP_BUNDLE="$APP_SRC" \
  OBJ_DIR="$WORK/obj" \
  all
[[ -d "$APP_SRC" ]] || { echo "missing $APP_SRC" >&2; exit 1; }

mkdir -p "$APP_SRC/Contents/Resources"
cp -f Resources/AppIcon.icns "$APP_SRC/Contents/Resources/"
cp -f Resources/AppIcon.png "$APP_SRC/Contents/Resources/"
cp -f Resources/Info.plist "$APP_SRC/Contents/Info.plist"

# Clean Finder AppleDouble / quarantine that break recognition
find "$APP_SRC" -name '._*' -delete 2>/dev/null || true
xattr -cr "$APP_SRC" 2>/dev/null || true
chmod +x "$APP_SRC/Contents/MacOS/${APP_NAME}"

# Sign app (named self-sign / Developer ID，或 ad-hoc)
sign_app "$APP_SRC"

echo "==> Staging clean payload (install → /Applications/${DISPLAY_NAME}.app)…"
rm -rf "$PKG_ROOT" "$DMG_STAGE" "$COMPONENT_PKG"
mkdir -p "$PKG_ROOT" "$DMG_STAGE" "$DIST_DIR"

# Root contains ONLY the .app; install-location = /Applications
# (avoids ./Applications nesting + relocation surprises)
mkdir -p "$PKG_ROOT/${DISPLAY_NAME}.app"
rsync -a --delete \
  --exclude '._*' --exclude '.DS_Store' --exclude '.AppleDouble' \
  "$APP_SRC/" "$PKG_ROOT/${DISPLAY_NAME}.app/"
# Strip any AppleDouble / xattrs that confuse Finder & Launchpad
find "$PKG_ROOT" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true
xattr -cr "$PKG_ROOT/${DISPLAY_NAME}.app" 2>/dev/null || true
# Re-sign the staged copy (rsync can drop signature)
sign_app "$PKG_ROOT/${DISPLAY_NAME}.app"
find "$PKG_ROOT" -name '._*' -delete 2>/dev/null || true

# Staging scripts without AppleDouble (pkgbuild copies ._postinstall otherwise)
SCRIPTS_STAGE="$DIST_DIR/scripts_stage"
rm -rf "$SCRIPTS_STAGE"
mkdir -p "$SCRIPTS_STAGE"
rsync -a --exclude '._*' --exclude '.DS_Store' \
  "$ROOT/Packaging/scripts/" "$SCRIPTS_STAGE/"
find "$SCRIPTS_STAGE" \( -name '._*' -o -name '.DS_Store' \) -delete
xattr -cr "$SCRIPTS_STAGE" 2>/dev/null || true
chmod +x "$SCRIPTS_STAGE/postinstall"

# Prevent macOS from stuffing AppleDouble (._*) into the cpio payload
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

pkgbuild \
  --root "$PKG_ROOT" \
  --install-location "/Applications" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --component-plist "$ROOT/Packaging/component.plist" \
  --scripts "$SCRIPTS_STAGE" \
  "$COMPONENT_PKG"

# pkgbuild still synthesizes AppleDouble from codesign xattrs — strip & re-flatten
EXPAND="$DIST_DIR/_expand"
PAYLOAD_TMP="$DIST_DIR/_payload"
rm -rf "$EXPAND" "$PAYLOAD_TMP"
pkgutil --expand "$COMPONENT_PKG" "$EXPAND"
COMP="$EXPAND"
if [[ ! -f "$EXPAND/Payload" ]]; then
  COMP="$(find "$EXPAND" -name Payload -print -quit | xargs dirname)"
fi
# Strip junk from Scripts + Payload
find "$EXPAND" \( -name '._*' -o -name '.DS_Store' \) -delete
mkdir -p "$PAYLOAD_TMP"
( cd "$PAYLOAD_TMP" && gzip -dc "$COMP/Payload" | cpio -idmu )
find "$PAYLOAD_TMP" \( -name '._*' -o -name '.DS_Store' \) -delete
xattr -cr "$PAYLOAD_TMP" 2>/dev/null || true
sign_app "$PAYLOAD_TMP/${DISPLAY_NAME}.app"
find "$PAYLOAD_TMP" -name '._*' -delete
# Ensure Info.plist identity matches component.plist / Launchpad name
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  "$PAYLOAD_TMP/${DISPLAY_NAME}.app/Contents/Info.plist" >/dev/null
( cd "$PAYLOAD_TMP" && find . | cpio -o --format odc --owner 0:80 | gzip -c > "$COMP/Payload" )
mkbom "$PAYLOAD_TMP" "$COMP/Bom"
NFILES="$(lsbom "$COMP/Bom" | wc -l | tr -d ' ')"
KBYTES="$(du -sk "$PAYLOAD_TMP" | awk '{print $1}')"
python3 - "$COMP/PackageInfo" "$NFILES" "$KBYTES" <<'PY'
import re, sys
from pathlib import Path
p, n, k = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
t = p.read_text()
t = re.sub(r'numberOfFiles="\d+"', f'numberOfFiles="{n}"', t)
t = re.sub(r'installKBytes="\d+"', f'installKBytes="{k}"', t)
# Hard-guarantee non-relocatable in PackageInfo
t = re.sub(r'relocatable="true"', 'relocatable="false"', t)
if 'relocatable=' not in t:
    t = t.replace('<pkg-info ', '<pkg-info relocatable="false" ', 1)
p.write_text(t)
PY
# Verify relocate section is empty
if grep -q '<relocate>' "$COMP/PackageInfo" && ! grep -q '<relocate/>' "$COMP/PackageInfo"; then
  # Non-empty relocate block would reintroduce the old bug
  python3 - "$COMP/PackageInfo" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = re.sub(r'<relocate>.*?</relocate>', '<relocate/>', p.read_text(), flags=re.S)
p.write_text(t)
PY
fi
rm -f "$COMPONENT_PKG"
pkgutil --flatten "$EXPAND" "$COMPONENT_PKG"
rm -rf "$EXPAND" "$PAYLOAD_TMP" "$SCRIPTS_STAGE"

# Installer localization: ONLY .lproj (no root License/Welcome — root English
# made the license language popup show “简体中文” while body stayed English).
RES_SRC="$ROOT/Packaging/resources"
RES_STAGE="$DIST_DIR/resources_stage"
rm -rf "$RES_STAGE"
mkdir -p "$RES_STAGE"
# Copy lproj trees; drop legacy HTML/RTF at root (use .txt for language menu)
rsync -a --exclude '._*' --exclude '.DS_Store' \
  --exclude 'Welcome.html' --exclude 'Welcome.rtf' \
  --exclude 'ReadMe.rtf' --exclude 'License.rtf' --exclude 'Conclusion.html' \
  "$RES_SRC/" "$RES_STAGE/"
# Remove any unlocalized page copies that would pin English in the UI
rm -f "$RES_STAGE"/Welcome.* "$RES_STAGE"/ReadMe.* \
      "$RES_STAGE"/License.* "$RES_STAGE"/Conclusion.*
# Exactly four locales — extra aliases (zh / zh_CN / Chinese / pt-BR …) show up as
# duplicate entries in Installer’s license language menu.
rm -rf "$RES_STAGE/zh_Hans.lproj" "$RES_STAGE/zh-Hans.lproj" \
       "$RES_STAGE/zh-CN.lproj" "$RES_STAGE/zh.lproj" "$RES_STAGE/Chinese.lproj" \
       "$RES_STAGE/pt_PT.lproj" "$RES_STAGE/pt_BR.lproj" "$RES_STAGE/pt-PT.lproj" \
       "$RES_STAGE/pt-BR.lproj" "$RES_STAGE/English.lproj" "$RES_STAGE/French.lproj" \
       "$RES_STAGE/Portuguese.lproj"
# Canonical Simplified Chinese folder name for modern macOS Installer
if [[ -d "$RES_STAGE/zh_CN.lproj" ]]; then
  mv "$RES_STAGE/zh_CN.lproj" "$RES_STAGE/zh-Hans.lproj"
fi
# Drop unused HTML companions inside lproj (Distribution uses .txt only)
find "$RES_STAGE" -name '*.html' -delete
# Localizable.strings → UTF-16 (Installer legacy requirement)
for LPROJ in "$RES_STAGE"/*.lproj; do
  STR="$LPROJ/Localizable.strings"
  [[ -f "$STR" ]] || continue
  if file "$STR" | grep -qi 'UTF-16'; then
    continue
  fi
  TMP="$STR.tmp"
  iconv -f UTF-8 -t UTF-16 "$STR" > "$TMP" && mv "$TMP" "$STR"
done
find "$RES_STAGE" \( -name '._*' -o -name '.DS_Store' \) -delete
xattr -cr "$RES_STAGE" 2>/dev/null || true

productbuild \
  --distribution "$ROOT/Packaging/Distribution.xml" \
  --resources "$RES_STAGE" \
  --package-path "$DIST_DIR" \
  "$PRODUCT_PKG"

# Strip any locale aliases productbuild may have synthesized; keep one per language
PROD_EXPAND="$DIST_DIR/_prod_expand"
rm -rf "$PROD_EXPAND"
pkgutil --expand "$PRODUCT_PKG" "$PROD_EXPAND"
PRES="$PROD_EXPAND/Resources"
# Prefer zh-Hans; remove other Chinese / Portuguese duplicates
if [[ -d "$PRES/zh-Hans.lproj" ]]; then
  :
elif [[ -d "$PRES/zh_CN.lproj" ]]; then
  mv "$PRES/zh_CN.lproj" "$PRES/zh-Hans.lproj"
elif [[ -d "$PRES/zh_Hans.lproj" ]]; then
  mv "$PRES/zh_Hans.lproj" "$PRES/zh-Hans.lproj"
fi
for EXTRA in zh_CN.lproj zh-CN.lproj zh_Hans.lproj zh.lproj Chinese.lproj \
             pt_PT.lproj pt_BR.lproj pt-PT.lproj pt-BR.lproj Portuguese.lproj \
             English.lproj French.lproj; do
  rm -rf "$PRES/$EXTRA"
done
# Ensure Chinese pages are present under zh-Hans
if [[ -d "$RES_STAGE/zh-Hans.lproj" && -d "$PRES/zh-Hans.lproj" ]]; then
  cp -f "$RES_STAGE/zh-Hans.lproj/"*.txt "$PRES/zh-Hans.lproj/" 2>/dev/null || true
fi
rm -f "$PRES"/Welcome.* "$PRES"/ReadMe.* "$PRES"/License.* "$PRES"/Conclusion.*
pkgutil --flatten "$PROD_EXPAND" "$PRODUCT_PKG"
rm -rf "$PROD_EXPAND" "$RES_STAGE"

# 对最终 product PKG 做 productsign（自签 / Developer ID Installer）
if [[ -n "$INSTALLER_IDENTITY" ]]; then
  echo "==> Signing product PKG…"
  SIGNED_PKG="$DIST_DIR/PickupBox-${VERSION}-signed.pkg"
  sign_pkg "$PRODUCT_PKG" "$SIGNED_PKG"
  pkgutil --check-signature "$PRODUCT_PKG" || true
fi

# Language-first launcher (system Installer has no reliable language picker)
LAUNCHER_APP="$DIST_DIR/${DISPLAY_NAME} Install.app"
echo "==> Building language-picker launcher…"
chmod +x "$ROOT/Packaging/build_launcher_app.sh"
SIGN_IDENTITY="$SIGN_IDENTITY" \
  "$ROOT/Packaging/build_launcher_app.sh" "$PRODUCT_PKG" "$LAUNCHER_APP" "$VERSION"

echo "==> Building DMG…"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
# Primary entry: pick language → Installer wizard
ditto --norsrc --noextattr --noqtn "$LAUNCHER_APP" "$DMG_STAGE/${DISPLAY_NAME} Install.app"
# Optional: drag-install the app without wizard
ditto --norsrc --noextattr --noqtn "$APP_SRC" "$DMG_STAGE/${DISPLAY_NAME}.app"
ln -sf /Applications "$DMG_STAGE/Applications"
mkdir -p "$DMG_STAGE/Advanced"
cp -f "$PRODUCT_PKG" "$DMG_STAGE/Advanced/${DISPLAY_NAME}.pkg"
cp -f "$RES_SRC/zh_CN.lproj/ReadMe.txt" "$DMG_STAGE/使用手札.txt"
cp -f "$RES_SRC/en.lproj/ReadMe.txt" "$DMG_STAGE/ReadMe.txt"
cat > "$DMG_STAGE/关于 About.txt" <<EOF
拾音盒子 · Pickup Box
一个看得见音乐的播放器 / A player that lets you see the music
版本 / Version：V${VERSION}
作者 / Author：KK-Files
联系 / Contact：827212416（微信同号 / WeChat）

推荐安装 / Recommended：
1）双击「${DISPLAY_NAME} Install.app」
2）先选择 English / 中文 / Français / Português
3）再进入系统安装向导（欢迎 / 手札 / 许可）

也可将「${DISPLAY_NAME}.app」拖到 Applications。
高级用户可在 Advanced 文件夹使用裸 .pkg（语言跟随系统）。
EOF

rm -f "$DMG_PATH"
hdiutil create \
  -volname "拾音盒子 ${VERSION}" \
  -srcfolder "$DMG_STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -f "$COMPONENT_PKG"
rm -rf "$PKG_ROOT" "$DMG_STAGE"

echo ""
echo "✓ 已生成："
echo "  $PRODUCT_PKG"
echo "  $LAUNCHER_APP   ← 打开后先选语言"
echo "  $DMG_PATH"
ls -lh "$PRODUCT_PKG" "$DMG_PATH"
du -sh "$LAUNCHER_APP"
echo ""
echo "若旧版安装异常，请先执行："
echo "  sudo pkgutil --forget com.kkfiles.PickupBox"
echo "再双击「${DISPLAY_NAME} Install.app」安装。"
