import Foundation
import NetworkExtension

/// Управление VPN-сессией из app-процесса: создаёт/стартует/останавливает
/// Tunnel extension. Конфиг передаётся через App Group (SharedConfig).
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()
    static let tunnelBundleID = "com.vkturn.ios.tunnel"

    @Published var status: NEVPNStatus = .invalid

    private var manager: NETunnelProviderManager?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let conn = note.object as? NETunnelProviderSession,
                  conn.status != self.status else { return }
            self.status = conn.status
        }
    }

    func start(with cfg: TunnelConfig) async throws {
        SharedConfig.save(cfg)
        let manager = try await loadManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = cfg.peer   // косметика для экрана VPN в Настройках
        manager.protocolConfiguration = proto
        manager.isEnabled = true
        try await saveLoad(manager)
        try manager.connection.startVPNTunnel()
    }

    func stop() async {
        let manager = try? await loadManager()
        manager?.connection.stopVPNTunnel()
    }

    // MARK: - Внутреннее

    private func loadManager() async throws -> NETunnelProviderManager {
        if let manager { return manager }
        let managers: [NETunnelProviderManager] = try await withCheckedThrowingContinuation { cont in
            NETunnelProviderManager.loadAllFromPreferences { list, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: list ?? []) }
            }
        }
        let manager = managers.first ?? NETunnelProviderManager()
        self.manager = manager
        return manager
    }

    private func saveLoad(_ manager: NETunnelProviderManager) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error { cont.resume(throwing: error); return }
                manager.loadFromPreferences { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            }
        }
    }
}
