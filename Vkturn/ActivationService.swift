import Foundation

struct ActivateResult {
    let token: String
    let configLink: String
    let expiresAt: Int64
    let bytesLimit: Int64
}

enum ActivationError: Error, LocalizedError {
    case badURL, badResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:            return "Некорректный адрес сервера"
        case .badResponse:       return "Некорректный ответ сервера"
        case .http(let c, let m): return "Сервер: \(c) — \(m)"
        }
    }
}

/// Активация ключа — зеркало KeyApi.kt: POST https://<api>/activate.
/// TODO(ios): сверить точные поля body/ответа с сервером и добавить проверку
/// SPKI-пина (аналог PinnedTls) — MVP ходит без пин-валидации.
enum ActivationService {
    static func activate(api: String, key: String, deviceID: String) async throws -> ActivateResult {
        guard let url = URL(string: "https://\(api)/activate") else { throw ActivationError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: ["key": key, "device_id": deviceID])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ActivationError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ActivationError.http(http.statusCode, String(msg.prefix(300)))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = obj["config"] as? String else { throw ActivationError.badResponse }

        return ActivateResult(
            token: obj["token"] as? String ?? "",
            configLink: config,
            expiresAt: (obj["expires_at"] as? NSNumber)?.int64Value ?? 0,
            bytesLimit: (obj["bytes_limit"] as? NSNumber)?.int64Value ?? 0
        )
    }
}
