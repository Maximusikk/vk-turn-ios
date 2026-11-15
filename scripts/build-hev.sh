#!/usr/bin/env bash
# hev-socks5-tunnel → статическая библиотека для iOS (arm64).
#   HEV_DIR=/path/to/hev-socks5-tunnel scripts/build-hev.sh
# (клон git clone --recurse-submodules https://github.com/hev/hev-socks5-tunnel)
set -euo pipefail

HEV_DIR="${HEV_DIR:?укажи HEV_DIR — клон github.com/hev/hev-socks5-tunnel}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/lib"
INC="$ROOT/build/include"
mkdir -p "$OUT" "$INC"

CC="$(xcrun -sdk iphoneos -find clang)"
SYSROOT="$(xcrun -sdk iphoneos --show-sdk-path)"
CFLAGS="-isysroot $SYSROOT -arch arm64 -O2 -DNDEBUG"
INC_FLAGS="-I$HEV_DIR/src -I$HEV_DIR/src/misc"

# TODO(ios): сверить список исходников со структурой репо — hev-task-system
# подтягивается submodule'ом в src/misc, main.c в библиотеку не входит.
TMP="$(mktemp -d)"
find "$HEV_DIR/src" -name '*.c' ! -name 'main.c' | while read -r f; do
  base="$(basename "${f%.c}")"
  "$CC" $CFLAGS $INC_FLAGS -c "$f" -o "$TMP/${base}_$$.o"
done

libtool -static -o "$OUT/libhev-socks5-tunnel.a" "$TMP"/*.o
rm -rf "$TMP"

# Заголовок лежит в корне или в src — берём как есть
HEADER="$(find "$HEV_DIR" -name 'hev_socks5_tunnel.h' | head -1)"
if [ -n "$HEADER" ]; then
  cp "$HEADER" "$INC/hev_socks5_tunnel.h"
fi
echo "OK: $OUT/libhev-socks5-tunnel.a"
