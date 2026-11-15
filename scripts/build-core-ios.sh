#!/usr/bin/env bash
# Ядро vk-turn-proxy → статическая библиотека для iOS (arm64, c-archive).
# Запускается на macOS с Xcode. Аналог build_kernel.sh, но GOOS=ios и в библиотеку.
#
#   CORE_DIR=/path/to/vk-turn-proxy scripts/build-core-ios.sh
#   SIM=1 CORE_DIR=… scripts/build-core-ios.sh   # симулятор вместо устройства
set -euo pipefail

CORE_DIR="${CORE_DIR:?укажи CORE_DIR — корень модуля vk-turn-proxy}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/lib"
INC="$ROOT/build/include"
mkdir -p "$OUT" "$INC"

if [ "${SIM:-0}" = "1" ]; then
  SDK="iphonesimulator"
else
  SDK="iphoneos"
fi
export GOOS=ios GOARCH=arm64 CGO_ENABLED=1
export CC="$(xcrun -sdk "$SDK" -find clang) -isysroot $(xcrun -sdk "$SDK" --show-sdk-path) -arch arm64"

cd "$CORE_DIR"
go build -buildmode=c-archive -ldflags "-s -w -checklinkname=0" -trimpath -o "$OUT/libvkturn.a" ./client

# c-archive кладёт заголовок рядом с .a
if [ -f "$OUT/libvkturn.h" ]; then
  cp "$OUT/libvkturn.h" "$INC/libvkturn.h"
fi
echo "OK: $OUT/libvkturn.a"
