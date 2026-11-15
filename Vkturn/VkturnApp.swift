import SwiftUI

@main
struct VkturnApp: App {
    var body: some Scene {
        WindowGroup { MainView() }
    }
}

extension Notification.Name {
    /// Входящая vkturn://-ссылка (deep link из Telegram/Safari).
    static let vkturnLink = Notification.Name("vkturnLink")
}
