#!/usr/bin/env bash
# Полная сборка: генерация Xcode-проекта + компиляция.
#   scripts/build.sh                  # валидация на симуляторе
#   IPA=1 scripts/build.sh            # unsigned .ipa для устройства
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

# Валидация сборки без подписи (симулятор)
xcodebuild -project Vkturn.xcodeproj -scheme Vkturn \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

if [ "${IPA:-0}" = "1" ]; then
  xcodebuild -project Vkturn.xcodeproj -scheme Vkturn \
    -sdk iphoneos -configuration Release \
    -archivePath "$ROOT/build/Vkturn.xcarchive" \
    CODE_SIGNING_ALLOWED=NO archive
  mkdir -p "$ROOT/build/Payload"
  cp -R "$ROOT/build/Vkturn.xcarchive/Products/Applications/Vkturn.app" "$ROOT/build/Payload/"
  (cd "$ROOT/build" && zip -qr Vkturn-unsigned.ipa Payload)
  echo "OK: $ROOT/build/Vkturn-unsigned.ipa"
fi
