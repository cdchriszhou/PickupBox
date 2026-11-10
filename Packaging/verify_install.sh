#!/bin/bash
# Clean previous installs / leftover relocate targets, then hint next steps
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

sudo pkgutil --forget com.kkfiles.PickupBox 2>/dev/null || true
sudo pkgutil --forget com.kkfiles.SonyFHKAOK 2>/dev/null || true
sudo rm -rf "/Applications/拾音盒子.app" "/Applications/SONY FH-KAOK.app" \
  /Applications/SonyFHKAOK.app /Applications/PickupBox.app 2>/dev/null || true

if [[ -d "$ROOT/build/PickupBox.app" ]]; then
  sudo rm -rf "$ROOT/build/PickupBox.app"
  echo "已删除 $ROOT/build/PickupBox.app"
fi
if [[ -d "$ROOT/build/SonyFHKAOK.app" ]]; then
  sudo rm -rf "$ROOT/build/SonyFHKAOK.app"
  echo "已删除 $ROOT/build/SonyFHKAOK.app"
fi

echo "请双击安装："
echo "  $ROOT/dist/拾音盒子 Install.app"
echo "或："
echo "  $ROOT/dist/PickupBox-1.0.0.pkg"
echo "安装完成后，在「应用程序」中查找：拾音盒子"
