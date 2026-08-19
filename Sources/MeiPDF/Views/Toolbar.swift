import SwiftUI
import PDFKit

struct BrowserToolbar: ToolbarContent {
    let appState: AppState
    @Binding var showSidebar: Bool
    @Binding var sidebarTab: SidebarTab
    @Binding var showPrint: Bool

    /// Resolve the *currently visible* document at use-time. This is the core fix for
    /// the "toolbar loses PDF context" bug: previously the toolbar captured a `doc`
    /// reference at build time, so after switching tabs its commands hit a torn-down
    /// (nil) `pdfView`. Resolving fresh from `appState` guarantees we always target
    /// the live, on-screen document.
    private var doc: DocumentState? { appState.selectedDocument(id: appState.selectedID) }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showSidebar.toggle()
                if showSidebar { sidebarTab = .thumbnails }
            } label: { Image(systemName: "sidebar.left") }
                .help("侧栏")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { doc?.previousPage() } label: { Image(systemName: "chevron.left") }.help("上一页")
            if let d = doc { PageJumpField(doc: d) }
            Text("/ \(doc?.pageCount ?? 0)").foregroundStyle(.secondary)
            Button { doc?.nextPage() } label: { Image(systemName: "chevron.right") }.help("下一页")
            Button {
                if let d = doc { d.toggleBookmark(d.currentPage) }
            } label: {
                Image(systemName: (doc?.isBookmarked(doc?.currentPage ?? 0) ?? false) ? "bookmark.fill" : "bookmark")
            }
            .help("书签当前页")
        }

        ToolbarItemGroup(placement: .automatic) {
            Button { doc?.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
            Text(String(format: "%.0f%%", (doc?.scaleFactor ?? 1) * 100)).foregroundStyle(.secondary).frame(minWidth: 44)
            Button { doc?.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
            Menu {
                Button("适应宽度") { doc?.fitWidth() }
                Button("适应页面") { doc?.fitPage() }
                Button("适应高度") { doc?.fitHeight() }
                Button("实际大小") { doc?.actualSize() }
                Divider()
                Menu("缩放比例") {
                    ForEach([50, 75, 100, 125, 150, 200, 300, 400], id: \.self) { pct in
                        Button("\(pct)%") { doc?.setScale(CGFloat(pct) / 100) }
                    }
                }
            } label: { Image(systemName: "magnifyingglass") }
                .help("缩放模式")
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach([PDFDisplayMode.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous], id: \.self) { mode in
                    Button {
                        doc?.displayMode = mode
                    } label: {
                        Text(labelFor(mode))
                        if doc?.displayMode == mode { Image(systemName: "checkmark") }
                    }
                }
            } label: { Image(systemName: "rectangle.stack") }
                .help("版式")
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Button { doc?.rotate(-90) } label: { Label("向左旋转", systemImage: "rotate.left") }
                Button { doc?.rotate(90) } label: { Label("向右旋转", systemImage: "rotate.right") }
            } label: { Image(systemName: "rotate.right") }
                .help("旋转")
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(Theme.allCases) { t in
                    Button {
                        doc?.theme = t
                    } label: {
                        Text(t.label)
                        if doc?.theme == t { Image(systemName: "checkmark") }
                    }
                }
            } label: { Image(systemName: doc?.theme == .dark ? "moon.fill" : "sun.max.fill") }
                .help("主题")
        }

        ToolbarItemGroup(placement: .automatic) {
            Button {
                doc?.saveAsDefault()
                appState.showToast("已保存为默认设置")
            } label: { Image(systemName: "checkmark.seal") }
                .help("将当前设置存为默认")
            ConfigStatusButton(appState: appState)
        }

        ToolbarItem(placement: .automatic) {
            SearchBar(appState: appState)
        }

        ToolbarItem(placement: .automatic) {
            AnnotationMenu(appState: appState)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button {
                showPrint = true
            } label: { Image(systemName: "printer") }
                .help("打印")
        }
    }

    private func labelFor(_ mode: PDFDisplayMode) -> String {
        switch mode {
        case .singlePage: "单页"
        case .singlePageContinuous: "连续"
        case .twoUp: "双页"
        case .twoUpContinuous: "双页连续"
        default: "\(mode.rawValue)"
        }
    }
}

// MARK: - Page jump (two-way synced)

/// Page-number box that reflects the currently rendered page and jumps when edited.
/// `doc` is `@Bindable` so SwiftUI actually observes `currentPage` — without it the
/// field would not refresh when the page changes via scrolling / arrows / thumbnails.
struct PageJumpField: View {
    @Bindable var doc: DocumentState
    @State private var text: String = ""

    var body: some View {
        TextField("页", text: $text)
            .frame(width: 46)
            .multilineTextAlignment(.center)
            .onSubmit { commit() }
            .onChange(of: doc.currentPage) { _, _ in syncFromDoc() }
            .onChange(of: doc.id) { _, _ in syncFromDoc() }
            .onAppear { syncFromDoc() }
    }

    private func syncFromDoc() {
        let str = String(doc.currentPage + 1)
        if text != str { text = str }
    }

    private func commit() {
        guard let n = Int(text), n >= 1, n <= doc.pageCount else {
            syncFromDoc()
            return
        }
        doc.goToPage(n - 1)
    }
}

// MARK: - Search

/// Native macOS search field (NSSearchField) so the magnifier lives inside the box.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: () -> Void

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            if let sf = obj.object as? NSSearchField {
                parent.text = sf.stringValue
                parent.onTextChange()
            }
        }
    }

    func makeNSView(context: Context) -> NSSearchField {
        let sf = NSSearchField()
        sf.delegate = context.coordinator
        sf.placeholderString = "搜索"
        sf.bezelStyle = .roundedBezel
        sf.sendsWholeSearchString = false
        sf.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return sf
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
}

struct SearchBar: View {
    let appState: AppState
    /// Resolve the active document live (see BrowserToolbar for why this matters).
    private var doc: DocumentState? { appState.selectedDocument(id: appState.selectedID) }
    @State private var text: String = ""
    @State private var caseSensitive = false
    @State private var wholeWord = false
    @State private var resultIndex = 0

    var body: some View {
        HStack(spacing: 8) {
            SearchField(text: $text, onTextChange: run)
                .frame(width: 170)
            Menu {
                Toggle("区分大小写", isOn: $caseSensitive)
                    .onChange(of: caseSensitive) { _, _ in run() }
                Toggle("全词匹配", isOn: $wholeWord)
                    .onChange(of: wholeWord) { _, _ in run() }
            } label: { Image(systemName: "chevron.down.circle") }
                .help("搜索选项")
            if !(doc?.searchMatches.isEmpty ?? true) {
                Button { step(-1) } label: { Image(systemName: "chevron.up") }
                    .help("上一个")
                Button { step(1) } label: { Image(systemName: "chevron.down") }
                    .help("下一个")
                Text("\(doc?.searchMatches.isEmpty ?? true ? 0 : resultIndex + 1)/\(doc?.searchMatches.count ?? 0)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        doc?.search(text, caseSensitive: caseSensitive, wholeWord: wholeWord)
        resultIndex = 0
        if !(doc?.searchMatches.isEmpty ?? true) { doc?.goToSearchResult(0) }
    }

    private func step(_ dir: Int) {
        guard let matches = doc?.searchMatches, !matches.isEmpty else { return }
        resultIndex = (resultIndex + dir + matches.count) % matches.count
        doc?.goToSearchResult(resultIndex)
    }
}

// MARK: - Annotation tools

struct AnnotationMenu: View {
    let appState: AppState
    @State private var showPopover = false
    /// Resolve the active document live (see BrowserToolbar for why this matters).
    private var doc: DocumentState? { appState.selectedDocument(id: appState.selectedID) }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: (doc?.activeTool).map { icon(for: $0) } ?? "highlighter")
        }
        .help("标注工具")
        .popover(isPresented: $showPopover) {
            if let d = doc {
                AnnotationPopover(doc: d, onSignature: { appState.showSignatureCapture = true })
                    .frame(width: 236)
                    .padding(14)
            }
        }
    }

    private func icon(for t: AnnotationType) -> String {
        switch t {
        case .square: "square"
        case .circle: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.right"
        case .ink: "pencil.tip"
        case .freeText: "text.cursor"
        case .signature: "signature"
        default: "highlighter"
        }
    }
}

/// Style + tool panel shown in a popover. `ColorPicker` does not work reliably inside
/// a `Menu`, but works perfectly in a popover — that is why the controls live here.
struct AnnotationPopover: View {
    @Bindable var doc: DocumentState
    /// Opens the signature-capture sheet (set by the toolbar menu).
    var onSignature: () -> Void = {}

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(doc.activeColor) }, set: { doc.activeColor = NSColor($0) })
    }
    private var widthBinding: Binding<Double> {
        Binding(get: { doc.activeLineWidth }, set: { doc.activeLineWidth = $0 })
    }
    private var styleBinding: Binding<LineStyle> {
        Binding(get: { doc.activeLineStyle }, set: { doc.activeLineStyle = $0 })
    }
    private var fillBinding: Binding<Bool> {
        Binding(get: { doc.activeFill }, set: { doc.activeFill = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("文字标注（选中文字后点击）").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                toolButton(.highlight, "highlighter", "高亮")
                toolButton(.underline, "underline", "下划线")
                toolButton(.strikeOut, "strikethrough", "删除线")
                toolButton(.note, "note.text", "笔记")
            }
            Divider()
            Text("形状工具（点击后在页面拖拽）").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                toolButton(.square, "square", "矩形")
                toolButton(.circle, "circle", "椭圆")
                toolButton(.line, "line.diagonal", "直线")
            }
            HStack(spacing: 8) {
                toolButton(.arrow, "arrow.right", "箭头")
                toolButton(.ink, "pencil.tip", "手绘")
                toolButton(.freeText, "text.cursor", "文本框")
            }
            HStack(spacing: 8) {
                Button {
                    onSignature()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "signature")
                        Text("签名").font(.caption)
                    }
                    .frame(width: 46, height: 40)
                }
                .buttonStyle(.plain)
                .help("签名")
            }
            Divider()
            Text("样式").font(.subheadline).foregroundStyle(.secondary)
            ColorPicker("颜色", selection: colorBinding)
            Picker("粗细", selection: widthBinding) {
                Text("细").tag(1.0)
                Text("中").tag(2.0)
                Text("粗").tag(4.0)
                Text("特粗").tag(8.0)
            }
            .pickerStyle(.segmented)
            Picker("线型", selection: styleBinding) {
                ForEach(LineStyle.allCases) { Text($0.label).tag($0) }
            }
            Toggle("填充（矩形 / 椭圆）", isOn: fillBinding)
        }
    }

    private func toolButton(_ t: AnnotationType, _ icon: String, _ label: String) -> some View {
        Button {
            if t == .note || t == .highlight || t == .underline || t == .strikeOut {
                doc.addTextMark(type: t, color: doc.activeColor)
            } else {
                doc.activeTool = t
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                Text(label).font(.caption)
            }
            .frame(width: 46, height: 40)
            .background(doc.activeTool == t ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(doc.activeTool == t ? Color.accentColor : Color.gray.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Config / Status inspector

/// Button beside "存为默认" that opens a popover listing every level's current
/// configuration (影响功能 / 渲染、可持久化) and status (运行时实时变化).
struct ConfigStatusButton: View {
    let appState: AppState
    @State private var show = false
    /// Resolve the active document live (see BrowserToolbar for why this matters).
    private var doc: DocumentState? { appState.selectedDocument(id: appState.selectedID) }

    var body: some View {
        Button {
            show.toggle()
        } label: { Image(systemName: "slider.horizontal.3") }
            .help("查看配置与状态")
            .popover(isPresented: $show) {
                if let d = doc {
                    ConfigStatusPopover(doc: d, preferences: appState.preferences)
                        .frame(width: 440, height: 560)
                        .padding(16)
                }
            }
    }
}

/// 配置与状态总览弹层：分级（默认 / 文件 / 页面）展示「配置」与「状态」两组。
///  - 配置：影响功能与渲染、可持久化的变量（缩放倍数、版式、书签选中态、颜色等）。
///  - 状态：运行时实时变化的变量（当前页、搜索命中数等）。
struct ConfigStatusPopover: View {
    let doc: DocumentState
    let preferences: Preferences

    private func modeLabel(_ m: PDFDisplayMode) -> String {
        switch m {
        case .singlePage: "单页"
        case .singlePageContinuous: "连续"
        case .twoUp: "双页"
        case .twoUpContinuous: "双页连续"
        default: "\(m.rawValue)"
        }
    }
    private func dirLabel(_ d: PDFDisplayDirection) -> String {
        d == .vertical ? "纵向滚动" : "横向滚动"
    }
    private func swatch(_ c: NSColor) -> some View {
        RoundedRectangle(cornerRadius: 4).fill(Color(c))
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4)))
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
    private func colorRow(_ label: String, _ c: NSColor) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            swatch(c)
        }
    }
    private func levelCard(title: String, subtitle: String, color: NSColor? = nil,
                           config: [(String, String)], status: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if !config.isEmpty || color != nil {
                Text("配置（影响功能 / 渲染）").font(.caption2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    if let c = color { colorRow("标注颜色", c) }
                    ForEach(Array(config.enumerated()), id: \.offset) { _, item in row(item.0, item.1) }
                }
            }
            if !status.isEmpty {
                Text("状态（运行时实时）").font(.caption2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(status.enumerated()), id: \.offset) { _, item in row(item.0, item.1) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.2)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置与状态总览").font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    levelCard(
                        title: "默认（应用级）",
                        subtitle: "全局默认配置，新文档继承",
                        color: preferences.defaultColor.nsColor,
                        config: [
                            ("主题", preferences.defaultTheme.label),
                            ("版式", modeLabel(preferences.defaultDisplayMode)),
                            ("滚动方向", dirLabel(preferences.defaultDisplayDirection)),
                            ("线宽", String(format: "%.0f", preferences.defaultLineWidth)),
                            ("线型", preferences.defaultLineStyle.label),
                            ("填充", preferences.defaultFill ? "开" : "关"),
                            ("记住阅读位置", preferences.rememberLastPosition ? "开" : "关")
                        ],
                        status: []
                    )

                    levelCard(
                        title: "文件（文档级）",
                        subtitle: doc.fileName,
                        color: doc.activeColor,
                        config: [
                            ("主题", doc.theme.label),
                            ("版式", modeLabel(doc.displayMode)),
                            ("滚动方向", dirLabel(doc.displayDirection)),
                            ("旋转", "\(doc.rotation)°"),
                            ("线宽", String(format: "%.0f", doc.activeLineWidth)),
                            ("线型", doc.activeLineStyle.label),
                            ("填充", doc.activeFill ? "开" : "关"),
                            ("书签数", "\(doc.bookmarks.count)"),
                            ("标注数", "\(doc.annotations.count)")
                        ],
                        status: [
                            ("缩放锁定", doc.zoomLocked ? "是" : "否"),
                            ("搜索命中", "\(doc.searchMatches.count)")
                        ]
                    )

                    levelCard(
                        title: "页面（运行时）",
                        subtitle: "当前文档实时状态",
                        config: [
                            ("缩放倍数", String(format: "%.0f%%", doc.scaleFactor * 100)),
                            ("版式模式", modeLabel(doc.displayMode)),
                            ("书签选中态", doc.isBookmarked(doc.currentPage) ? (doc.bookmarks[doc.currentPage] ?? "已书签") : "未书签")
                        ],
                        status: [
                            ("当前页", "\(doc.currentPage + 1) / \(doc.pageCount)"),
                            ("搜索结果数", "\(doc.searchMatches.count)")
                        ]
                    )
                }
            }
        }
    }
}
