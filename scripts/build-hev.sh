#!/usr/bin/env bash
# hev-socks5-tunnel (heiher) → статическая библиотека для iOS-устройства (arm64).
# Повторяет срез build-apple.sh только для iphoneos-arm64, без tvos/macos срезов.
#   HEV_DIR=/path/to/hev-socks5-tunnel scripts/build-hev.sh
# (клон: git clone --recursive https://github.com/heiher/hev-socks5-tunnel)
set -euo pipefail

HEV_DIR="${HEV_DIR:?укажи HEV_DIR — клон github.com/heiher/hev-socks5-tunnel (с submodule)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/lib"
INC="$ROOT/build/include"
mkdir -p "$OUT" "$INC"

cd "$HEV_DIR"
# Тот же вызов, что в build-apple.sh → buildStatic iphoneos arm64 15.0
make PP="xcrun --sdk iphoneos --toolchain iphoneos clang" \
     CC="xcrun --sdk iphoneos --toolchain iphoneos clang" \
     CFLAGS="-arch arm64 -miphoneos-version-min=15.0" \
     LFLAGS="-arch arm64 -miphoneos-version-min=15.0 -Wl,-Bsymbolic-functions" \
     static

# Makefile собирает hev без third-part'ов — мержим, как в build-apple.sh
libtool -static -o "$OUT/libhev-socks5-tunnel.a" \
  bin/libhev-socks5-tunnel.a \
  third-part/lwip/bin/liblwip.a \
  third-part/yaml/bin/libyaml.a \
  third-part/hev-task-system/bin/libhev-task-system.a

# Публичный API-заголовок (hev_socks5_tunnel_main_from_str / quit)
cp src/hev-main.h "$INC/hev-main.h"
echo "OK: $OUT/libhev-socks5-tunnel.a"
