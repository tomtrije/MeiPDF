import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedID: DocumentState.ID?
    @State private var showSidebar = true
    @State private var sidebarTab: SidebarTab = .thumbnails
    @State private var showPrint = false
    @State private var showPassword = false
    @State private var passwordInput = ""
    @State private var showPreferences = false

    private var doc: DocumentState? { appState.selectedDocument(id: selectedID) }

    var body: some View {
        VStack(spacing: 0) {
            if let doc {
                TopTabBar(selectedID: $selectedID, showSidebar: $showSidebar)
                Divider()
                HStack(spacing: 0) {
                    if showSidebar {
                        Sidebar(doc: doc, tab: $sidebarTab)
                            .frame(width: 260)
                        Divider()
                    }
                    PDFViewWrapper(doc: doc)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                WelcomeView(showSidebar: $showSidebar)
            }
        }
        .toolbar {
            if let doc {
                BrowserToolbar(doc: doc, showSidebar: $showSidebar, sidebarTab: $sidebarTab,
                               showPrint: $showPrint)
            }
        }
        .sheet(isPresented: $showPrint) {
            if let doc { PrintSheet(doc: doc) }
        }
        .sheet(isPresented: $showPassword) {
            PasswordSheet(url: appState.pendingPasswordURL,
                          onUnlock: { url, pw in
                              _ = appState.openUnlocked(url, password: pw)
                              showPassword = false
                          })
        }
        .onReceive(NotificationCenter.default.publisher(for: .meiPDFRequestPrint)) { _ in
            if doc != nil { showPrint = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meiPDFRequestPassword)) { _ in
            showPassword = true
        }
        .onChange(of: appState.pendingPasswordURL) { _, new in
            if new != nil { showPassword = true }
        }
    }
}

// MARK: - Top tab bar

struct TopTabBar: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedID: DocumentState.ID?
    @Binding var showSidebar: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.documents) { d in
                    TabItem(doc: d, selectedID: $selectedID)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TabItem: View {
    @Environment(AppState.self) private var appState
    @Bindable var doc: DocumentState
    @Binding var selectedID: DocumentState.ID?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
            Text(doc.fileName)
                .lineLimit(1)
                .frame(maxWidth: 160)
            Button {
                appState.close(doc)
                if selectedID == doc.id { selectedID = appState.documents.last?.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selectedID == doc.id ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { selectedID = doc.id }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Binding var showSidebar: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("MeiPDF").font(.largeTitle.bold())
            Text("专注浏览与打印的原生 PDF 阅读器").foregroundStyle(.secondary)
            Button("打开 PDF…") { openDocument() }
                .controlSize(.large)
            if !appState.recentFiles.isEmpty {
                Divider().frame(width: 280)
                Text("最近打开").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.recentFiles) { rf in
                            Button {
                                _ = appState.open(URL(fileURLWithPath: rf.path))
                            } label: {
                                Label(rf.name, systemImage: "clock")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: 280)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { _ = appState.open(url) }
        }
    }
}

extension Notification.Name {
    static let meiPDFRequestPassword = Notification.Name("meiPDFRequestPassword")
}
