import SwiftUI
import UIKit

/// Активация: вставка/переход по vkturn://bundle/… → выбор сервера → POST /activate.
struct ActivationView: View {
    let initialLink: String?

    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var bundle: BundleSubscription?
    @State private var selectedServer: BundleServer?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Ссылка подписки") {
                    TextField("vkturn://bundle/…", text: $linkText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 12, design: .monospaced))
                    Button("Разобрать ссылку") { parseLink() }
                }

                if let bundle {
                    Section("Серверы: \(bundle.name)") {
                        ForEach(bundle.servers) { server in
                            Button {
                                selectedServer = server
                                Task { await activate(server) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.displayName).foregroundStyle(.primary)
                                        Text(server.api).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedServer?.id == server.id && busy {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Активация")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .onAppear {
                if linkText.isEmpty, let initialLink { linkText = initialLink; parseLink() }
            }
        }
    }

    private func parseLink() {
        errorText = nil
        do {
            bundle = try VkturnLink.parseBundle(linkText)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func activate(_ server: BundleServer) async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? "ios-unknown"
            let result = try await ActivationService.activate(api: server.api, key: server.key, deviceID: deviceID)
            let cfg = try VkturnLink.parseConfig(result.configLink)
            var cfg = cfg
            cfg.deviceID = deviceID
            if cfg.name.isEmpty { cfg.name = bundle?.name ?? "" }
            try await TunnelManager.shared.start(with: cfg)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
