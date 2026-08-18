import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

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
            // "打开最近" — wire up the `recentFiles` already maintained by AppState.
            CommandMenu("打开最近") {
                if appState.recentFiles.isEmpty {
                    Text("（暂无最近文件）")
                } else {
                    ForEach(appState.recentFiles) { rf in
                        Button(rf.name) { _ = appState.open(URL(fileURLWithPath: rf.path)) }
                    }
                    Divider()
                    Button("清除最近文件") {
                        appState.recentFiles.removeAll()
                        appState.saveRecents()
                    }
                }
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
                Divider()
                Button("上一处标注") { activeDoc()?.goToPreviousAnnotation() }
                Button("下一处标注") { activeDoc()?.goToNextAnnotation() }
            }
            CommandMenu("视图") {
                Button("进入全屏") { toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
            }
            CommandMenu("导出") {
                Button("导出本页为 PNG…") { exportCurrentPageImage() }
                Button("导出全部页面为 PNG…") { exportAllImages() }
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

    private func toggleFullScreen() {
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
    }

    private func exportCurrentPageImage() {
        guard let d = activeDoc() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "\(d.fileName)_p\(d.currentPage + 1).png"
        if panel.runModal() == .OK, let url = panel.url {
            d.exportPagePNG(to: url, index: d.currentPage)
        }
    }

    private func exportAllImages() {
        guard let d = activeDoc() else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            d.exportAllPagesPNG(to: url)
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
