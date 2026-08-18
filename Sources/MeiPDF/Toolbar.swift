import SwiftUI
import PDFKit

struct BrowserToolbar: ToolbarContent {
    let doc: DocumentState
    @Binding var showSidebar: Bool
    @Binding var sidebarTab: SidebarTab
    @Binding var showPrint: Bool

    @State private var jumpText: String = ""

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                showSidebar.toggle()
                if showSidebar { sidebarTab = .thumbnails }
            } label: { Image(systemName: "sidebar.left") }
                .help("侧栏")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { doc.previousPage() } label: { Image(systemName: "chevron.left") }.help("上一页")
            TextField("页", text: $jumpText) {
                if let n = Int(jumpText), n >= 1, n <= doc.pageCount { doc.goToPage(n - 1) }
            }
            .frame(width: 46)
            .multilineTextAlignment(.center)
            Text("/ \(doc.pageCount)").foregroundStyle(.secondary)
            Button { doc.nextPage() } label: { Image(systemName: "chevron.right") }.help("下一页")
        }

        ToolbarItemGroup(placement: .automatic) {
            Button { doc.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
            Text(String(format: "%.0f%%", doc.scaleFactor * 100)).foregroundStyle(.secondary).frame(minWidth: 44)
            Button { doc.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
            Menu {
                Button("适应宽度") { doc.fitWidth() }
                Button("适应页面") { doc.fitPage() }
                Button("实际大小") { doc.actualSize() }
            } label: { Image(systemName: "magnifyingglass") }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach([PDFDisplayMode.singlePage, .singlePageContinuous, .twoUp, .twoUpContinuous], id: \.self) { mode in
                    Button {
                        doc.displayMode = mode
                    } label: {
                        Text(labelFor(mode))
                        if doc.displayMode == mode { Image(systemName: "checkmark") }
                    }
                }
            } label: { Image(systemName: "rectangle.stack") }
                .help("版式")
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Button { doc.rotate(-90) } label: { Label("向左旋转", systemImage: "rotate.left") }
                Button { doc.rotate(90) } label: { Label("向右旋转", systemImage: "rotate.right") }
            } label: { Image(systemName: "rotate.right") }
                .help("旋转")
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(Theme.allCases) { t in
                    Button {
                        doc.theme = t
                    } label: {
                        Text(t.label)
                        if doc.theme == t { Image(systemName: "checkmark") }
                    }
                }
            } label: { Image(systemName: doc.theme == .dark ? "moon.fill" : "sun.max.fill") }
                .help("主题")
        }

        ToolbarItem(placement: .automatic) {
            SearchBar(doc: doc)
        }

        ToolbarItem(placement: .automatic) {
            AnnotationMenu(doc: doc)
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

// MARK: - Search

struct SearchBar: View {
    let doc: DocumentState
    @State private var text: String = ""
    @State private var caseSensitive = false
    @State private var wholeWord = false
    @State private var resultIndex = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
            TextField("搜索", text: $text)
                .frame(width: 150)
                .onChange(of: text) { _, newValue in run() }
            Toggle("区分大小写", isOn: $caseSensitive).toggleStyle(.checkbox).labelsHidden()
                .help("区分大小写").onChange(of: caseSensitive) { _, _ in run() }
            Toggle("全词", isOn: $wholeWord).toggleStyle(.checkbox).labelsHidden()
                .help("全词匹配").onChange(of: wholeWord) { _, _ in run() }
            if !doc.searchMatches.isEmpty {
                Button { step(-1) } label: { Image(systemName: "chevron.up") }
                Button { step(1) } label: { Image(systemName: "chevron.down") }
                Text("\(doc.searchMatches.isEmpty ? 0 : resultIndex + 1)/\(doc.searchMatches.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        doc.search(text, caseSensitive: caseSensitive, wholeWord: wholeWord)
        resultIndex = 0
        if !doc.searchMatches.isEmpty { doc.goToSearchResult(0) }
    }

    private func step(_ dir: Int) {
        guard !doc.searchMatches.isEmpty else { return }
        resultIndex = (resultIndex + dir + doc.searchMatches.count) % doc.searchMatches.count
        doc.goToSearchResult(resultIndex)
    }
}

// MARK: - Annotation tools

struct AnnotationMenu: View {
    let doc: DocumentState
    var body: some View {
        Menu {
            Button { doc.addTextMark(type: .highlight, color: doc.activeColor) }
                label: { Label("高亮", systemImage: "highlighter") }
            Button { doc.addTextMark(type: .underline, color: doc.activeColor) }
                label: { Label("下划线", systemImage: "underline") }
            Button { doc.addTextMark(type: .strikeOut, color: doc.activeColor) }
                label: { Label("删除线", systemImage: "strikethrough") }
            Button { doc.addNote(text: "", color: doc.activeColor) }
                label: { Label("笔记", systemImage: "note.text") }
            Divider()
            Button { doc.activeTool = .square } label: { Label("矩形", systemImage: "square") }
            Button { doc.activeTool = .circle } label: { Label("椭圆", systemImage: "circle") }
            Button { doc.activeTool = .line } label: { Label("直线", systemImage: "line.diagonal") }
            Divider()
            let binding = Binding<Color>(
                get: { Color(doc.activeColor) },
                set: { doc.activeColor = NSColor($0) }
            )
            ColorPicker("颜色", selection: binding)
        } label: { Image(systemName: "highlighter") }
            .help("标注工具")
    }
}
