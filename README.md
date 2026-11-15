# VKTurn iOS

iOS-клиент VKTurn: тот же движок, что на Android (ядро vk-turn-proxy через VK TURN
транспорт + локальный SOCKS5), но ядро живёт **внутри** NetworkExtension-процесса
(iOS запрещает отдельные процессы).

## Архитектура

```
┌─ Vkturn.app (SwiftUI) ──────────────┐
│ активация vkturn://bundle/…         │
│ POST /activate → config (peer/vk/…) │
│ App Group: group.com.vkturn.shared  │
└──────────────┬──────────────────────┘
               │ NETunnelProviderManager
┌─ Tunnel.appex (PacketTunnelProvider) ─────────────────────┐
│ 1. Go-ядро (libvkturn.a, c-archive) — SOCKS5 127.0.0.1:9000│
│    управление: stdin-пайп (STOP/PAUSE/CAPTCHA_RESULT|…)    │
│ 2. hev-socks5-tunnel — TUN(packetFlow._fileDescriptor)     │
│    → весь трафик устройства в SOCKS5 ядра                  │
└───────────────────────────────────────────────────────────┘
```

## Сборка

Нужен macOS (или CI macos runner). Скрипты:

```bash
CORE_DIR=/path/to/vk-turn-proxy \
HEV_DIR=/path/to/hev-socks5-tunnel \
  scripts/build-core-ios.sh      # Go-ядро → build/lib/libvkturn.a + libvkturn.h

HEV_DIR=/path/to/hev-socks5-tunnel \
  scripts/build-hev.sh           # hev → build/lib/libhev-socks5-tunnel.a

scripts/build.sh                 # xcodegen → xcodebuild (валидация сборки)
```

CI-сборка — `.github/workflows/build-ios.yml` (macos runner, unsigned artifact).

## Статус / TODO

- [x] Скелет проекта, entitlements (packet-tunnel-provider + app group)
- [x] Обёртка ядра: `C:\Core\client\ios_export.go` (stdin-протокол сохранён)
- [x] PacketTunnelProvider: сетевые настройки, старт ядра, hev-мост
- [x] Парсинг `vkturn://bundle/<b64url JSON>` — зеркально BundleLink.kt
- [ ] Активация: POST /activate — зеркалить KeyApi.kt (пин SPKI + токен)
- [ ] hev: сверить ключ конфига `tunnel.fd` с версией (см. PacketTunnelProvider.swift)
- [ ] packetFlow fd — приватный KVC `_fileDescriptor` (ок для ad-hoc/TestFlight,
      перед App Store заменить на легальный путь)
- [ ] Капча: режим `wv` требует WKWebView-интеракцию (фаза 2); MVP — `auto`
- [ ] Подпись ad-hoc + UDID-коллектор (после появления аккаунта)

## Правка ядра под iOS

`ios_export.go` лежит в `client/` с билд-тегом `//go:build ios` — Android-сборки
его не видят, build_kernel.sh не меняется.
