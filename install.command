#!/bin/bash
# MeiPDF 自用安装脚本（无 Developer ID 证书时）
#
# 通过 GitHub 自动打包出来的 DMG，在没有「Developer ID 证书 + 公证」的情况下，
# 直接打开会被 Gatekeeper 拦截。本脚本移除隔离属性并把 app 装到 /Applications。
# 如果未来你用 Developer ID 签名并公证过，本脚本无害（xattr 无实际操作）。
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/MeiPDF.app"

if [ ! -d "$SRC" ]; then
  echo "错误：未在当前目录找到 MeiPDF.app（$SRC）"
  exit 1
fi

echo "==> 移除 Gatekeeper 隔离属性 (com.apple.quarantine)"
xattr -dr com.apple.quarantine "$SRC" 2>/dev/null || xattr -cr "$SRC" 2>/dev/null || true

DEST="/Applications/MeiPDF.app"
echo "==> 安装到 $DEST"
if cp -R "$SRC" "$DEST" 2>/dev/null; then
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  echo "已安装。正在打开 MeiPDF…"
  open "$DEST"
else
  echo "复制到 /Applications 失败（可能需要管理员权限）。改为直接打开 DMG 内的 app。"
  open "$SRC"
fi

echo "完成。"
