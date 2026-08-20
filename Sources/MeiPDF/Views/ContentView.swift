import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showPrint = false
    @State private var showPassword = false
    @State private var passwordInput = ""
    @State private var showPreferences = false

    private var doc: DocumentState? { appState.selectedDocument(id: appState.selectedID) }

    /// Bridges `appState.inspectorDoc` (computed from `inspectorDocID`) into the
    /// `Binding<DocumentState?>` that `.sheet(item:)` requires.
    private var inspectorBinding: Binding<DocumentState?> {
        Binding(
            get: { appState.inspectorDoc },
            set: { appState.inspectorDocID = $0?.id }
        )
    }

    /// Bridges `doc.editingNote` into the `Binding` that `.popover(item:)` needs,
    /// so clicking a note on the page opens an inline editor for its text.
    private var noteBinding: Binding<NoteEditTarget?> {
        Binding(
            get: { doc?.editingNote },
            set: { doc?.editingNote = $0 }
        )
    }

    /// Bridges `doc.editingFreeText` (double-click a text box on the page).
    private var freeTextBinding: Binding<NoteEditTarget?> {
        Binding(
            get: { doc?.editingFreeText },
            set: { doc?.editingFreeText = $0 }
        )
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            if let doc {
                TopTabBar(selectedID: $appState.selectedID, showSidebar: $appState.showSidebar)
                Divider()
                HStack(spacing: 0) {
                    if appState.showSidebar {
                        Sidebar(doc: doc, tab: $appState.sidebarTab)
                            .frame(width: 260)
                            .id(doc.id)
                        Divider()
                    }
                    PDFViewWrapper(doc: doc)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(doc.id)
                }
                .popover(item: noteBinding) { target in
                    NoteEditPopover(doc: doc, target: target)
                }
                .popover(item: freeTextBinding) { target in
                    NoteEditPopover(doc: doc, target: target)
                }
                Divider()
                StatusBar(doc: doc)
            } else {
                WelcomeView(showSidebar: $appState.showSidebar)
            }
        }
        .toolbar {
            if appState.selectedDocument(id: appState.selectedID) != nil {
                BrowserToolbar(appState: appState, showSidebar: $appState.showSidebar, sidebarTab: $appState.sidebarTab,
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
        .sheet(item: inspectorBinding) { doc in
            InspectorView(doc: doc)
        }
        .sheet(isPresented: Binding(
            get: { appState.showSignatureCapture },
            set: { appState.showSignatureCapture = $0 }
        )) {
            SignatureCaptureView()
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
        .overlay(alignment: .top) {
            if let msg = appState.toastMessage {
                ToastView(message: msg)
                    .padding(.top, 12)
            }
        }
        .background(WindowAccessor())
    }
}

/// Captures the hosting `NSWindow` and installs `MainWindowDelegate` on it so that
/// ⌘W / the red traffic-light close the active *tab* while tabs remain and only
/// close the window on the last tab. Purely a side-effect view (renders nothing).
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.install(on: window)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window, window.delegate !== context.coordinator {
            context.coordinator.install(on: window)
        }
    }
    func makeCoordinator() -> MainWindowDelegate { MainWindowDelegate() }
}

struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)).shadow(radius: 4))
            .overlay(Capsule().stroke(Color.accentColor.opacity(0.5)))
            .foregroundStyle(.primary)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.2), value: message)
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
        .contextMenu {
            Button("关闭当前") { appState.close(doc) }
            Button("关闭其他") { appState.closeOthers(keep: doc.id) }
            Button("关闭全部") { appState.closeAll() }
        }
        .onDrag { NSItemProvider(object: doc.id.uuidString as NSString) }
        .dropDestination(for: String.self) { items, _ in
            if let src = items.first, let srcID = UUID(uuidString: src) {
                appState.moveDocument(srcID, before: doc.id)
                return true
            }
            return false
        }
    }
}

// MARK: - Bottom status bar (对齐预览底部信息条)

/// Shows the current page number, page dimensions, and zoom — the small info bar
/// Preview displays at the bottom of its window.
struct StatusBar: View {
    @Bindable var doc: DocumentState

    private var pageRect: CGRect? {
        doc.pdfDocument.page(at: doc.currentPage)?.bounds(for: .mediaBox)
    }

    var body: some View {
        HStack(spacing: 18) {
            Text("第 \(doc.currentPage + 1) / \(doc.pageCount) 页")
            if let r = pageRect {
                Text(String(format: "页面 %.0f × %.0f mm",
                            r.width * 25.4 / 72, r.height * 25.4 / 72))
                Text(String(format: "%.0f%%", doc.scaleFactor * 100))
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(NSColor.windowBackgroundColor))
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

// MARK: - Note content editor (popover opened by clicking a note on the page)

/// Small popover shown when the user clicks one of our note annotations on the
/// page. Lets them type / edit the note's text directly, mirroring Preview's
/// click-to-edit note behaviour. Commits back to the (non-destructive) model.
struct NoteEditPopover: View {
    @Bindable var doc: DocumentState
    let target: NoteEditTarget
    @State private var text: String = ""
    @FocusState private var focused: Bool

    init(doc: DocumentState, target: NoteEditTarget) {
        self.doc = doc
        self.target = target
        _text = State(initialValue: doc.annotations.first(where: { $0.id == target.id })?.contents ?? "")
    }

    var body: some View {
        let ann = doc.annotations.first(where: { $0.id == target.id })
        return VStack(alignment: .leading, spacing: 8) {
            Text("第 \(target.pageIndex + 1) 页 · \(ann?.type == .freeText ? "编辑文本框" : "编辑笔记")").font(.headline)
            TextEditor(text: $text)
                .frame(minWidth: 260, minHeight: 120)
                .focused($focused)
            HStack {
                Spacer()
                Button("完成") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 300)
        .task { focused = true }
    }

    private func save() {
        doc.updateAnnotationContents(id: target.id, contents: text)
        doc.editingNote = nil
    }
}
