import SwiftUI
import PDFKit
import UniformTypeIdentifiers

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails, outline, bookmarks, annotations
    var id: String { rawValue }
    var label: String {
        switch self { case .thumbnails: "缩略图"; case .outline: "目录"; case .bookmarks: "书签"; case .annotations: "标注" }
    }
    var icon: String {
        switch self { case .thumbnails: "rectangle.grid.1x2"; case .outline: "list.bullet.indent"; case .bookmarks: "bookmark"; case .annotations: "highlighter" }
    }
}

struct Sidebar: View {
    @Bindable var doc: DocumentState
    @Binding var tab: SidebarTab

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SidebarTab.allCases) { t in
                    Image(systemName: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch tab {
            case .thumbnails: ThumbnailsPanel(doc: doc)
            case .outline: OutlinePanel(doc: doc)
            case .bookmarks: BookmarksPanel(doc: doc)
            case .annotations: AnnotationsPanel(doc: doc)
            }
        }
    }
}

// MARK: Thumbnails

struct ThumbnailsPanel: View {
    @Bindable var doc: DocumentState
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(0..<doc.pageCount, id: \.self) { i in
                    ThumbnailRow(doc: doc, index: i)
                }
            }
            .padding(8)
        }
    }
}

struct ThumbnailRow: View {
    @Bindable var doc: DocumentState
    let index: Int
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 2) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .border(doc.currentPage == index ? Color.accentColor : Color.gray.opacity(0.3), width: doc.currentPage == index ? 2 : 1)
            } else {
                Rectangle().fill(Color.gray.opacity(0.15)).frame(height: 120)
            }
            Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
        }
        .onTapGesture { doc.goToPage(index) }
        .onAppear { generate() }
    }

    private func generate() {
        guard image == nil, let page = doc.pdfDocument.page(at: index) else { return }
        let size = NSSize(width: 130, height: 100000)
        image = page.thumbnail(of: size, for: .mediaBox)
    }
}

// MARK: Outline

struct OutlinePanel: View {
    @Bindable var doc: DocumentState
    var body: some View {
        if let root = doc.pdfDocument.outlineRoot, root.numberOfChildren > 0 {
            List {
                OutlineNodeView(doc: doc, outline: root)
            }
            .listStyle(.sidebar)
        } else {
            CenteredMessage(text: "该文档没有目录")
        }
    }
}

struct OutlineNodeView: View {
    @Bindable var doc: DocumentState
    let outline: PDFOutline

    var body: some View {
        ForEach(0..<outline.numberOfChildren, id: \.self) { i in
            if let child = outline.child(at: i) {
                OutlineRow(doc: doc, outline: child)
            }
        }
    }
}

struct OutlineRow: View {
    @Bindable var doc: DocumentState
    let outline: PDFOutline

    var body: some View {
        Button {
            if let dest = outline.destination, let page = dest.page,
               let idx = doc.pdfDocument.index(for: page) as Int? {
                doc.goToPage(idx)
            }
        } label: {
            HStack {
                Text(outline.label ?? "（无标题）")
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        if outline.numberOfChildren > 0 {
            OutlineNodeView(doc: doc, outline: outline)
                .padding(.leading, 14)
        }
    }
}

// MARK: Bookmarks (page-level, renameable)

struct BookmarksPanel: View {
    @Bindable var doc: DocumentState
    var body: some View {
        if doc.bookmarks.isEmpty {
            CenteredMessage(text: "还没有书签。使用工具栏书签按钮添加。")
        } else {
            List {
                ForEach(Array(doc.bookmarks.sorted(by: { $0.key < $1.key })), id: \.key) { page, _ in
                    BookmarkRow(doc: doc, page: page)
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct BookmarkRow: View {
    @Bindable var doc: DocumentState
    let page: Int
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Button { doc.goToPage(page) } label: { Image(systemName: "doc.text").frame(width: 18) }
                .buttonStyle(.plain)
                .help("定位到第 \(page + 1) 页")
            if focused {
                TextField("名称", text: $draft)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            } else {
                Text(doc.bookmarks[page] ?? "第 \(page + 1) 页")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEdit() }
            }
            Spacer()
            Button { doc.removeBookmark(page: page) } label: { Image(systemName: "bookmark.slash") }
                .buttonStyle(.plain)
                .help("删除书签")
        }
    }

    private func beginEdit() {
        draft = doc.bookmarks[page] ?? "第 \(page + 1) 页"
        focused = true
    }
    private func commit() {
        doc.renameBookmark(page: page, name: draft)
        focused = false
    }
}

// MARK: Annotations (grouped by page, renameable)

struct NativeRow: Identifiable {
    let id: ObjectIdentifier
    let pageIndex: Int
    let annotation: PDFAnnotation
}

struct AnnotationsPanel: View {
    @Bindable var doc: DocumentState

    private var grouped: [(page: Int, items: [Annotation])] {
        let sorted = doc.annotations.sorted { $0.pageIndex < $1.pageIndex }
        var dict: [Int: [Annotation]] = [:]
        for a in sorted { dict[a.pageIndex, default: []].append(a) }
        return dict.sorted { $0.key < $1.key }.map { (page: $0.key, items: $0.value) }
    }

    private var nativeRows: [NativeRow] {
        doc.nativeAnnotationItems().map { NativeRow(id: ObjectIdentifier($0.annotation), pageIndex: $0.pageIndex, annotation: $0.annotation) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("我的 \(doc.annotations.count) · 原有 \(nativeRows.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("导出") { export() }
                    .disabled(doc.annotations.isEmpty)
            }
            .padding(8)
            Divider()
            List {
                if doc.annotations.isEmpty {
                    Section("我的标注") { Text("还没有标注。").foregroundStyle(.secondary) }
                } else {
                    ForEach(grouped, id: \.page) { group in
                        Section {
                            ForEach(group.items) { a in
                                AnnotationRow(doc: doc, annotation: a)
                            }
                        } header: {
                            Button { doc.goToPage(group.page) } label: {
                                Label("第 \(group.page + 1) 页", systemImage: "doc.text")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("文档原有标注（含预览等）") {
                    if nativeRows.isEmpty {
                        Text("无。").foregroundStyle(.secondary)
                    }
                    ForEach(nativeRows) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("第 \(item.pageIndex + 1) 页 · \(typeLabel(item.annotation))").font(.subheadline)
                            }
                            Spacer()
                            Button { doc.goToPage(item.pageIndex) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.plain)
                                .help("定位")
                            Button { doc.removeNativeAnnotation(pageIndex: item.pageIndex, annotation: item.annotation) }
                                label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .help("删除")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func typeLabel(_ ann: PDFAnnotation) -> String {
        switch ann.type {
        case "Highlight": "高亮"
        case "Underline": "下划线"
        case "StrikeOut": "删除线"
        case "Square": "矩形"
        case "Circle": "椭圆"
        case "Line": "直线"
        case "Ink": "手绘"
        case "FreeText": "文本"
        case "Text": "笔记"
        default: ann.type ?? "标注"
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = (doc.fileName as NSString).deletingPathExtension + "-标注.md"
        if panel.runModal() == .OK, let url = panel.url {
            try? doc.exportAnnotationsMarkdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct AnnotationRow: View {
    @Bindable var doc: DocumentState
    let annotation: Annotation
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Button { doc.goToPage(annotation.pageIndex) } label: { Image(systemName: "magnifyingglass").frame(width: 18) }
                .buttonStyle(.plain)
                .help("定位")
            VStack(alignment: .leading, spacing: 2) {
                if focused {
                    TextField("名称", text: $draft)
                        .focused($focused)
                        .onSubmit { commit() }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                } else {
                    Text(displayName)
                        .font(.subheadline)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEdit() }
                }
                if let c = annotation.contents, !c.isEmpty {
                    Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Button { doc.removeAnnotation(id: annotation.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("删除")
        }
    }

    private var displayName: String {
        if let n = annotation.name, !n.isEmpty { return n }
        return annotation.type.label
    }
    private func beginEdit() {
        draft = displayName
        focused = true
    }
    private func commit() {
        doc.renameAnnotation(id: annotation.id, name: draft)
        focused = false
    }
}

// MARK: Helpers

struct CenteredMessage: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            Spacer()
        }
    }
}
