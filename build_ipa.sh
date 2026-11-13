#!/usr/bin/env bash
#
# 把 make 出来的 QuickKey.app 打成 TrollStore 可安装的 .ipa
# 前提：先执行 make clean all（或 THEOS_PACKAGE_SCHEME=rootless make all）
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP=$(find .theos/obj -maxdepth 3 -type d -name 'QuickKey.app' | head -n1)
if [[ -z "${APP}" ]]; then
    echo "找不到 QuickKey.app，先跑 make all" >&2
    exit 1
fi

if ! command -v ldid >/dev/null 2>&1; then
    echo "缺 ldid（brew install ldid），TrollStore 需要它把 entitlements 写进二进制" >&2
    exit 1
fi

echo "签名 entitlements..."
ldid -M -Sentitlements/app.entitlements "${APP}/QuickKey"

rm -rf build
mkdir -p build/Payload
cp -R "${APP}" build/Payload/

echo "打包 IPA..."
(cd build && zip -qry QuickKey.ipa Payload)

echo "完成：$(pwd)/build/QuickKey.ipa"
