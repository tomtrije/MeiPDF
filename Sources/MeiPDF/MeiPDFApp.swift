import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@main
struct MeiPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建窗口") { openWindow(id: "main") }
                Divider()
                Button("打开…") { openDocument() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .printItem) {
                Button("打印…") { NotificationCenter.default.post(name: .meiPDFRequestPrint, object: nil) }
                    .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { UpdaterHost.shared.checkForUpdates() }
                    .keyboardShortcut("u", modifiers: .command)
            }
        }
        Settings {
            PreferencesView()
                .environment(appState)
                .frame(width: 460, height: 380)
        }
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = appState.open(url)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls { _ = appState.open(u) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension Notification.Name {
    static let meiPDFRequestPrint = Notification.Name("meiPDFRequestPrint")
}
