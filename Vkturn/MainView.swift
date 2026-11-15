import SwiftUI
import NetworkExtension

struct MainView: View {
    @ObservedObject private var tm = TunnelManager.shared
    @State private var showActivation = false
    @State private var pendingLink: String?
    @State private var logText = ""

    private var statusText: String {
        switch tm.status {
        case .connected: return "Подключено ✓"
        case .connecting: return "Подключение…"
        case .disconnecting: return "Отключение…"
        case .disconnected: return "Отключено"
        case .invalid: return SharedConfig.load() == nil ? "Активируй подписку" : "Готов к запуску"
        default: return "—"
        }
    }

    private var circleColor: Color {
        switch tm.status {
        case .connected: return .green
        case .connecting, .disconnecting: return .orange
        default: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("VKTurn").font(.title2).bold()

            ZStack {
                Circle()
                    .fill(circleColor.opacity(0.25))
                    .frame(width: 150, height: 150)
                Circle()
                    .stroke(circleColor, lineWidth: 4)
                    .frame(width: 150, height: 150)
                Image(systemName: tm.status == .connected ? "bolt.fill" : "bolt.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(circleColor)
            }
            .onTapGesture { toggle() }

            Text(statusText).font(.headline)

            ScrollView {
                Text(logText.isEmpty ? "Лог пуст" : logText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .padding()
        .sheet(isPresented: $showActivation) {
            ActivationView(initialLink: pendingLink)
        }
        .onAppear { readLog() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            readLog()
        }
        .onOpenURL { url in
            // vkturn://bundle/… из Telegram/Safari
            pendingLink = url.absoluteString
            showActivation = true
        }
    }

    private func toggle() {
        if tm.status == .connected {
            Task { await TunnelManager.shared.stop() }
        } else if let cfg = SharedConfig.load() {
            Task { try? await TunnelManager.shared.start(with: cfg) }
        } else {
            showActivation = true
        }
    }

    private func readLog() {
        guard let url = SharedConfig.logFileURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        // Хвост последних 4 КБ — как на Android: лог можно выделить и скопировать
        let tail = data.count > 4096 ? data.suffix(4096) : data
        logText = String(data: tail, encoding: .utf8) ?? ""
    }
}
