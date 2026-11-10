#!/bin/bash
# Repair a broken previous install (relocated into the project build/ folder)
set -euo pipefail

echo "将清除错误的安装收据，并删除误装到工程目录的 root 权限 App…"
echo "需要管理员密码。"

sudo pkgutil --forget com.kkfiles.SonyFHKAOK 2>/dev/null || true
sudo rm -rf /Applications/SonyFHKAOK.app "/Applications/SONY FH-KAOK.app" 2>/dev/null || true

# Old relocate target — project build folder owned by root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -d "$ROOT/build/SonyFHKAOK.app" ]]; then
  sudo rm -rf "$ROOT/build/SonyFHKAOK.app"
  echo "已删除 $ROOT/build/SonyFHKAOK.app"
fi

echo ""
echo "请重新双击安装："
echo "  $ROOT/dist/SONY-FH-KAOK-1.0.0.pkg"
echo ""
echo "安装完成后，在「应用程序」中查找：SONY FH-KAOK"
