import NetworkExtension
import Foundation

enum TunnelError: Error, LocalizedError {
    case noConfig, coreStartFailed, socksTimeout, tunFdUnavailable

    var errorDescription: String? {
        switch self {
        case .noConfig:         return "Конфиг не найден в App Group"
        case .coreStartFailed:  return "Ядро не запустилось"
        case .socksTimeout:     return "SOCKS5 ядра не поднялся"
        case .tunFdUnavailable: return "Не удалось получить fd туннеля"
        }
    }
}

final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var stdinHandle: FileHandle?
    private var logHandle: FileHandle?

    // MARK: - Старт

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let cfg = SharedConfig.load() else {
            completionHandler(TunnelError.noConfig)
            return
        }
        appendLog("=== ЗАПУСК === \(cfg.name) (\(cfg.peer))")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: hostOnly(cfg.peer))
        settings.mtu = 1500
        let ipv4 = NEIPv4Settings(addresses: ["10.66.66.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "0.0.0.0", subnetMask: "0.0.0.0")]
        settings.ipv4Settings = ipv4
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])

        setTunnelNetworkSettings(settings) { error in
            if let error {
                self.appendLog("setTunnelNetworkSettings: \(error)")
                completionHandler(error)
                return
            }
            self.startCore(cfg) { ok in
                guard ok else {
                    completionHandler(TunnelError.socksTimeout)
                    return
                }
                // Приватный KVC-доступ к fd utun — ок для ad-hoc/TestFlight.
                // TODO(ios, перед App Store): заменить на легальный путь (sing-tun/system stack).
                guard let fd = (self.packetFlow as NSObject).value(forKey: "_fileDescriptor") as? Int32, fd >= 0 else {
                    self.appendLog("packetFlow fd недоступен")
                    completionHandler(TunnelError.tunFdUnavailable)
                    return
                }
                self.startHev(tunFd: fd, socksPort: cfg.listenPort)
                self.appendLog("Туннель поднят ✓")
                completionHandler(nil)
            }
        }
    }

    // MARK: - Стоп

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        appendLog("=== ОСТАНОВКА (причина \(reason.rawValue)) ===")
        stdinHandle?.write("STOP\n".data(using: .utf8)!)
        hev_socks5_tunnel_terminate()
        completionHandler()
    }

    // MARK: - Ядро (c-archive, stdin-протокол как на Android)

    private func startCore(_ cfg: TunnelConfig, done: @escaping (Bool) -> Void) {
        var argv = cfg.cliArgs()
        var stdinFd: Int32 = -1
        var logFd: Int32 = -1

        let rc = argv.withUTF8 { buf -> Int32 in
            var cArg = [CChar](UnsafeBufferPointer(start: buf.baseAddress?.assumingMemoryBound(to: CChar.self),
                                                   count: buf.count)) + [0]
            return VkturnStart(&cArg, &stdinFd, &logFd)
        }
        guard rc == 0, stdinFd >= 0, logFd >= 0 else {
            appendLog("VkturnStart rc=\(rc)")
            done(false)
            return
        }

        stdinHandle = FileHandle(fileDescriptor: stdinFd, closeOnDealloc: false)
        pumpCoreLog(fd: logFd)

        // Ждём подъёма SOCKS5 ядра (по аналогии с waitSocks Android-версии)
        DispatchQueue.global().async {
            let up = Self.waitForSocks(port: UInt16(cfg.listenPort), timeoutMs: 30_000)
            DispatchQueue.main.async { done(up) }
        }
    }

    private func pumpCoreLog(fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        Thread.detachNewThread {
            // Хвост 1 МБ, чтобы лог не рос бесконечно
            while true {
                let data = handle.availableData
                if data.isEmpty { Thread.sleep(forTimeInterval: 0.2); continue }
                if let line = String(data: data, encoding: .utf8) {
                    self.appendLog(line)
                }
            }
        }
    }

    static func waitForSocks(port: UInt16, timeoutMs: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            if canConnect(port: port) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    private static func canConnect(port: UInt16) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian  // 127.0.0.1

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var flags = fcntl(fd, F_GETFL, 0)
        flags |= O_NONBLOCK
        fcntl(fd, F_SETFL, flags)

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return true }
        if errno == EINPROGRESS {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let pr = poll(&pfd, 1, 300)
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            return pr > 0 && err == 0
        }
        return false
    }

    // MARK: - hev-socks5-tunnel: весь трафик TUN → SOCKS5 ядра

    private func startHev(tunFd: Int32, socksPort: Int) {
        // TODO(ios): ключ конфига для fd сверить с версией hev
        // (в Android-интеграциях встречается и `tunnel: fd:` и `tun-fd`).
        let config = """
        tunnel:
          mtu: 1500
          ipv6: false
          fd: \(tunFd)
        socks5:
          port: \(socksPort)
          address: 127.0.0.1
          udp: 'udp'
        misc:
          log-level: 'warn'
        """
        Thread.detachNewThread {
            config.withUTF8 { buf in
                var cConfig = [CChar](UnsafeBufferPointer(start: buf.baseAddress?.assumingMemoryBound(to: CChar.self),
                                                          count: buf.count)) + [0]
                _ = hev_socks5_tunnel_main(&cConfig)
            }
        }
    }

    // MARK: - Лог (в App Group — читается из app)

    private func appendLog(_ line: String) {
        let stamped = "[\(Self.timestamp())] \(line)\n"
        guard let url = SharedConfig.logFileURL else { return }
        if let handle = logHandle {
            handle.write(stamped.data(using: .utf8)!)
        } else {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            logHandle = try? FileHandle(forWritingTo: url)
            logHandle?.seekToEndOfFile()
            logHandle?.write(stamped.data(using: .utf8)!)
        }
        // Триммим лог на 512 КБ
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64, size > 512 * 1024 {
            let all = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let half = all.suffix(256 * 1024)
            try? half.write(to: url, atomically: true, encoding: .utf8)
            logHandle?.seekToEndOfFile()
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func hostOnly(_ peer: String) -> String {
        peer.split(separator: ":").first.map(String.init) ?? peer
    }
}
