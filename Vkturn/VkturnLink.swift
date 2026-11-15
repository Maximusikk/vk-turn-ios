import Foundation

struct BundleServer: Identifiable {
    let api: String        // host:port API ноды
    let pin: String        // SPKI-пин hex64 (валидация при активации)
    let key: String        // ключ активации сервера
    let name: String
    let country: String

    var id: String { api + key }
    var displayName: String { name.isEmpty ? api : name }
}

struct BundleSubscription {
    let name: String
    let servers: [BundleServer]
    let limitBytes: Int64?
    let masterURL: String
}

enum VkturnLinkError: Error, LocalizedError {
    case notBundle, badBase64, badJSON, badVersion, emptyName, noServers
    case notV1Config, badConfigJSON

    var errorDescription: String? {
        switch self {
        case .notBundle:    return "Ожидается vkturn://bundle/… ссылка"
        case .badBase64:    return "Ошибка декодирования ссылки"
        case .badJSON:      return "Невалидный JSON внутри ссылки"
        case .badVersion:   return "Неизвестная версия ссылки (нужна v=1)"
        case .emptyName:    return "Пустое имя подписки"
        case .noServers:    return "В bundle нет серверов"
        case .notV1Config:  return "Ожидается vkturn://v1/… конфиг от сервера"
        case .badConfigJSON: return "Ошибка парсинга конфига"
        }
    }
}

/// Разбор ссылок — зеркально ServerLink.kt + BundleLink.kt Android-версии.
enum VkturnLink {
    static let bundlePrefix = "vkturn://bundle/"
    static let v1Prefix = "vkturn://v1/"

    /// Вытаскивает первую vkturn://-ссылку из произвольного текста (как ServerLink.extractLink).
    static func extractLink(from text: String) -> String? {
        guard let range = text.range(of: "vkturn://") else { return nil }
        let rest = String(text[range.lowerBound...])
        return rest.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    /// vkturn://bundle/<b64url JSON>: {"v":1,"n":"…","s":[{"api","pin","key","name","country"}],"limit":…}
    static func parseBundle(_ raw: String) throws -> BundleSubscription {
        guard let link = extractLink(from: raw), link.hasPrefix(bundlePrefix) else { throw VkturnLinkError.notBundle }
        guard let payload = base64UrlDecode(String(link.dropFirst(bundlePrefix.count))) else { throw VkturnLinkError.badBase64 }
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw VkturnLinkError.badJSON }
        guard (obj["v"] as? Int) == 1 else { throw VkturnLinkError.badVersion }
        guard let name = obj["n"] as? String, !name.isEmpty else { throw VkturnLinkError.emptyName }
        guard let arr = obj["s"] as? [[String: Any]], !arr.isEmpty else { throw VkturnLinkError.noServers }

        let servers = arr.map { s in
            BundleServer(api: s["api"] as? String ?? "",
                         pin: s["pin"] as? String ?? "",
                         key: s["key"] as? String ?? "",
                         name: s["name"] as? String ?? "",
                         country: s["country"] as? String ?? "")
        }
        let limit = (obj["limit"] as? NSNumber)?.int64Value
        let master = obj["m"] as? String ?? ""
        return BundleSubscription(name: name, servers: servers, limitBytes: limit, masterURL: master)
    }

    /// vkturn://v1/<b64url JSON>: {"n","peer","vk","pwd","listen","profile","pin"} — ответ /activate.
    static func parseConfig(_ raw: String) throws -> TunnelConfig {
        guard let link = extractLink(from: raw), link.hasPrefix(v1Prefix) else { throw VkturnLinkError.notV1Config }
        guard let payload = base64UrlDecode(String(link.dropFirst(v1Prefix.count))) else { throw VkturnLinkError.badBase64 }
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw VkturnLinkError.badConfigJSON }

        let listen = obj["listen"] as? String ?? "127.0.0.1:9000"
        let port = Int(listen.split(separator: ":").last ?? "") ?? 9000
        return TunnelConfig(
            name: obj["n"] as? String ?? "",
            peer: obj["peer"] as? String ?? "",
            vkLink: obj["vk"] as? String ?? "",
            password: obj["pwd"] as? String ?? "",
            listenPort: port,
            tlsPin: obj["pin"] as? String ?? ""
        )
    }

    /// Android декодирует URL_SAFE|NO_PADDING — дополняем паддинг при необходимости.
    private static func base64UrlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}
