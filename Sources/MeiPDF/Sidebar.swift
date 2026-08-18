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

// MARK: Bookmarks

struct BookmarksPanel: View {
    @Bindable var doc: DocumentState
    var body: some View {
        if doc.bookmarks.isEmpty {
            CenteredMessage(text: "还没有书签。使用工具栏书签按钮添加。")
        } else {
            List {
                ForEach(Array(doc.bookmarks.sorted()), id: \.self) { page in
                    HStack {
                        Button { doc.goToPage(page) } label: {
                            Label("第 \(page + 1) 页", systemImage: "doc.text")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button {
                            doc.toggleBookmark(page)
                        } label: { Image(systemName: "bookmark.slash") }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: Annotations

struct AnnotationsPanel: View {
    @Bindable var doc: DocumentState
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(doc.annotations.count) 条标注").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("导出") { export() }
                    .disabled(doc.annotations.isEmpty)
            }
            .padding(8)
            Divider()
            if doc.annotations.isEmpty {
                CenteredMessage(text: "还没有标注。")
            } else {
                List {
                    ForEach(doc.annotations) { a in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("第 \(a.pageIndex + 1) 页 · \(a.type.label)").font(.subheadline)
                                if let c = a.contents, !c.isEmpty {
                                    Text(c).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            Button { doc.removeAnnotation(id: a.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { doc.goToPage(a.pageIndex) }
                    }
                }
                .listStyle(.sidebar)
            }
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
