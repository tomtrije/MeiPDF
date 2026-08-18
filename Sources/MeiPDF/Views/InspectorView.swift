import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Document inspector (⌘I), aligned with Preview's "显示检查器" panel.
/// Shows file-level metadata and the current page's geometry — distinct from the
/// Config/Status popover, which is about *settings*, not *the file itself*.
struct InspectorView: View {
    @Bindable var doc: DocumentState
    @Environment(\.dismiss) private var dismiss

    private var pageRect: CGRect? {
        doc.pdfDocument.page(at: doc.currentPage)?.bounds(for: .mediaBox)
    }
    private var fileSizeString: String {
        guard let url = doc.fileURL,
              let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = vals.fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    private var fileDates: (created: String, modified: String) {
        guard let url = doc.fileURL,
              let vals = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) else {
            return ("—", "—")
        }
        let fmt: (Date?) -> String = { d in
            guard let d else { return "—" }
            return Self.dateFmt.string(from: d)
        }
        return (fmt(vals.creationDate), fmt(vals.contentModificationDate))
    }
    private var pdfAttributes: [(String, String)] {
        guard let attrs = doc.pdfDocument.documentAttributes as? [String: Any] else { return [] }
        let map: [(String, String)] = [
            ("Title", "标题"), ("Author", "作者"), ("Subject", "主题"),
            ("Creator", "创建程序"), ("Producer", "生成程序"), ("Keywords", "关键词")
        ]
        return map.compactMap { key, label in
            if let v = attrs[key] {
                let s = (v as? String) ?? String(describing: v)
                return s.isEmpty ? nil : (label, s)
            }
            return nil
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("检查器").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("关闭")
            }
            .padding(14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("文件") {
                        row("名称", doc.fileName)
                        row("页数", "\(doc.pageCount)")
                        row("文件大小", fileSizeString)
                        row("创建日期", fileDates.created)
                        row("修改日期", fileDates.modified)
                    }

                    section("当前页") {
                        if let r = pageRect {
                            row("页码", "\(doc.currentPage + 1) / \(doc.pageCount)")
                            row("尺寸（点）", String(format: "%.0f × %.0f pt", r.width, r.height))
                            row("尺寸（毫米）", String(format: "%.0f × %.0f mm",
                                                       r.width * 25.4 / 72, r.height * 25.4 / 72))
                            row("旋转", "\(doc.rotation)°")
                        } else {
                            Text("（无页面信息）").foregroundStyle(.secondary)
                        }
                    }

                    if !pdfAttributes.isEmpty {
                        section("PDF 信息") {
                            ForEach(pdfAttributes, id: \.0) { label, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label).font(.caption).foregroundStyle(.secondary)
                                    Text(value).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 340, height: 460)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) { content() }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer()
        }
    }
}
