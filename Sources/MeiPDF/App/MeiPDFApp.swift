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
            // Cmd+W closes the active *tab* (not the window) — this is a multi-tab
            // single-window app, so the default window-close binding is undesirable.
            CommandGroup(after: .windowArrangement) {
                Button("关闭标签页") { closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(after: .printItem) {
                Button("打印…") { NotificationCenter.default.post(name: .meiPDFRequestPrint, object: nil) }
                    .keyboardShortcut("p", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { UpdaterHost.shared.checkForUpdates() }
                    .keyboardShortcut("u", modifiers: .command)
            }
            CommandMenu("阅读") {
                Button("上一页") { activeDoc()?.previousPage() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("下一页") { activeDoc()?.nextPage() }
                    .keyboardShortcut("]", modifiers: .command)
                Divider()
                Button("放大") { activeDoc()?.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("缩小") { activeDoc()?.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("实际大小") { activeDoc()?.actualSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("书签当前页") { if let d = activeDoc() { d.toggleBookmark(d.currentPage) } }
                    .keyboardShortcut("d", modifiers: .command)
                Divider()
                Button("高亮") { mark(.highlight) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("下划线") { mark(.underline) }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("删除线") { mark(.strikeOut) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("笔记") { mark(.note) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("矩形工具") { activeDoc()?.activeTool = .square }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("椭圆工具") { activeDoc()?.activeTool = .circle }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("直线工具") { activeDoc()?.activeTool = .line }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        Settings {
            PreferencesView()
                .environment(appState)
                .frame(width: 480, height: 420)
        }
    }

    // MARK: Helpers (act on the currently visible document)

    private func activeDoc() -> DocumentState? {
        appState.selectedDocument(id: appState.selectedID)
    }
    private func closeActiveTab() {
        if let d = activeDoc() { appState.close(d) }
    }
    private func mark(_ type: AnnotationType) {
        guard let d = activeDoc() else { return }
        switch type {
        case .highlight, .underline, .strikeOut:
            d.addTextMark(type: type, color: d.activeColor)
        case .note:
            d.addNote(text: "", color: d.activeColor)
        default:
            d.activeTool = type
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
