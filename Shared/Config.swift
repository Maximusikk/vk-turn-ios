import Foundation

/// Конфиг туннеля: app собирает → extension читает через App Group.
struct TunnelConfig: Codable {
    var name: String = ""
    var peer: String            // host:port VPS
    var vkLink: String          // ссылка VK-звонка — ядро принимает сырую (TurnProxyService.kt:78)
    var password: String        // пароль ядра (из него WRAP-ключ)
    var listenPort: Int = 9000
    var tlsPin: String = ""
    var deviceID: String = ""

    /// Аргументы запуска ядра — зеркально TurnProxyService.kt (-peer -vk -password -listen).
    /// ВАЖНО: значения не должны содержать пробелов (аргументы передаются одной строкой).
    func cliArgs() -> String {
        let listen = "127.0.0.1:\(listenPort)"
        // TODO(ios): -n (кол-во воркеров) — взять TURN_WORKERS из Android-версии
        return "-listen \(listen) -peer \(peer) -vk \(vkLink) -password \(password) -device-id \(deviceID)"
    }
}

enum SharedConfig {
    static let appGroup = "group.com.vkturn.shared"
    private static let key = "tunnelConfig"

    static var container: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ c: TunnelConfig) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        container?.set(data, forKey: key)
    }

    static func load() -> TunnelConfig? {
        guard let data = container?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TunnelConfig.self, from: data)
    }

    /// Лог ядра: extension пишет, app читает (аналог поля лога в Android-UI).
    static var logFileURL: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return base.appendingPathComponent("vkturn.log")
    }
}
