import Foundation
import PDFKit
import SwiftUI

enum DocError: Error { case cannotOpen, locked }

@MainActor
@Observable
final class DocumentState: Identifiable {
    let id = UUID()
    let fileURL: URL?
    let fileName: String
    let pdfDocument: PDFDocument
    var isLocked: Bool = false

    var currentPage: Int = 0
    var scaleFactor: CGFloat = 1.0
    var displayMode: PDFDisplayMode
    var displayDirection: PDFDisplayDirection
    var rotation: Int = 0
    var theme: Theme

    var bookmarks: Set<Int> = []
    var annotations: [Annotation] = []

    weak var pdfView: MeiPDFView?

    // annotation tool state
    var activeTool: AnnotationType? = nil
    var activeColor: NSColor = NSColor.systemYellow

    // search
    var searchMatches: [PDFSelection] = []
    var searchText: String = ""

    let preferences: Preferences

    init(url: URL, preferences: Preferences) throws {
        self.fileURL = url
        self.fileName = url.lastPathComponent
        self.preferences = preferences
        guard let doc = PDFDocument(url: url) else { throw DocError.cannotOpen }
        self.pdfDocument = doc
        self.displayMode = preferences.defaultDisplayMode
        self.displayDirection = preferences.defaultDisplayDirection
        self.theme = preferences.defaultTheme
        self.activeColor = preferences.defaultColor.nsColor
        if doc.isLocked {
            self.isLocked = true
        } else {
            loadMeta()
        }
    }

    // MARK: Meta

    private func loadMeta() {
        guard let url = fileURL, let meta = MetaStore.load(for: url) else { return }
        bookmarks = Set(meta.bookmarks)
        rotation = meta.rotation
        annotations = meta.annotations
        currentPage = meta.lastPage
        applyRotationToPages()
        rebuildAnnotationsOnPages()
    }

    func unlock(with password: String) -> Bool {
        guard pdfDocument.unlock(withPassword: password) else { return false }
        isLocked = false
        return true
    }

    func finishUnlock() {
        isLocked = false
        loadMeta()
    }

    func persist() {
        guard let url = fileURL, !isLocked else { return }
        let meta = DocumentMeta(
            bookmarks: Array(bookmarks).sorted(),
            lastPage: currentPage,
            rotation: rotation,
            annotations: annotations
        )
        MetaStore.save(meta, for: url)
    }

    // MARK: Rotation

    func applyRotationToPages() {
        guard !isLocked else { return }
        for i in 0..<pdfDocument.pageCount {
            pdfDocument.page(at: i)?.rotation = rotation
        }
    }

    func rotate(_ delta: Int) {
        rotation = (rotation + delta) % 360
        if rotation < 0 { rotation += 360 }
        applyRotationToPages()
        pdfView?.layoutDocumentView()
        persist()
    }

    // MARK: Navigation

    var pageCount: Int { pdfDocument.pageCount }

    func goToPage(_ index: Int) {
        guard index >= 0, index < pdfDocument.pageCount else { return }
        if let page = pdfDocument.page(at: index) {
            pdfView?.go(to: page)
            currentPage = index
        }
    }
    func nextPage() { pdfView?.goToNextPage(nil) }
    func previousPage() { pdfView?.goToPreviousPage(nil) }
    func firstPage() { pdfView?.goToFirstPage(nil) }
    func lastPage() { pdfView?.goToLastPage(nil) }

    // MARK: Zoom

    func zoomIn() { pdfView?.zoomIn(nil); if let s = pdfView?.scaleFactor { scaleFactor = s } }
    func zoomOut() { pdfView?.zoomOut(nil); if let s = pdfView?.scaleFactor { scaleFactor = s } }
    func setScale(_ factor: CGFloat) {
        pdfView?.scaleFactor = max(0.1, min(8, factor))
        if let s = pdfView?.scaleFactor { scaleFactor = s }
    }
    func actualSize() { setScale(1.0) }
    func fitWidth() {
        pdfView?.autoScales = true
        DispatchQueue.main.async { [weak self] in
            if let s = self?.pdfView?.scaleFactor { self?.scaleFactor = s }
        }
    }
    func fitPage() {
        guard let view = pdfView, let page = pdfDocument.page(at: currentPage) else { return }
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return }
        let sx = view.bounds.width / pageRect.width
        let sy = view.bounds.height / pageRect.height
        setScale(min(sx, sy))
    }

    // MARK: Bookmarks

    func toggleBookmark(_ page: Int) {
        if bookmarks.contains(page) { bookmarks.remove(page) }
        else { bookmarks.insert(page) }
        persist()
    }
    func isBookmarked(_ page: Int) -> Bool { bookmarks.contains(page) }

    // MARK: Annotations (non-destructive)

    private func subtype(for type: AnnotationType) -> PDFAnnotationSubtype {
        switch type {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        case .note: return .text
        case .square: return .square
        case .circle: return .circle
        case .line: return .line
        }
    }

    private func makePDFAnnotation(_ a: Annotation) -> PDFAnnotation? {
        guard pdfDocument.page(at: a.pageIndex) != nil else { return nil }
        let b = NSRect(x: a.bounds.x, y: a.bounds.y, width: a.bounds.w, height: a.bounds.h)
        let ann = PDFAnnotation(bounds: b, forType: subtype(for: a.type), withProperties: nil)
        switch a.type {
        case .highlight, .underline, .strikeOut:
            if let quads = a.quadPoints {
                ann.quadrilateralPoints = quads.map { NSValue(point: CGPoint(x: $0.x, y: $0.y)) }
            }
            ann.color = a.color.nsColor
        case .note:
            ann.contents = a.contents ?? ""
            ann.color = a.color.nsColor
            ann.iconType = .note
        case .square, .circle:
            ann.color = a.color.nsColor
        case .line:
            ann.color = a.color.nsColor
            ann.startPoint = CGPoint(x: b.minX, y: b.minY)
            ann.endPoint = CGPoint(x: b.maxX, y: b.maxY)
        }
        ann.shouldDisplay = true
        return ann
    }

    private func rebuildAnnotationsOnPages() {
        guard !isLocked else { return }
        for a in annotations {
            if let ann = makePDFAnnotation(a) {
                pdfDocument.page(at: a.pageIndex)?.addAnnotation(ann)
            }
        }
    }

    func addAnnotation(_ a: Annotation) {
        guard !isLocked else { return }
        if let ann = makePDFAnnotation(a) {
            pdfDocument.page(at: a.pageIndex)?.addAnnotation(ann)
        }
        annotations.append(a)
        persist()
    }

    func removeAnnotation(id: UUID) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        let a = annotations[idx]
        let wantType = subtype(for: a.type).rawValue
        let bx = CGFloat(a.bounds.x), by = CGFloat(a.bounds.y)
        let bw = CGFloat(a.bounds.w), bh = CGFloat(a.bounds.h)
        if let page = pdfDocument.page(at: a.pageIndex) {
            for ann in page.annotations {
                guard ann.type == wantType else { continue }
                let b = ann.bounds
                if abs(b.origin.x - bx) < 1 && abs(b.origin.y - by) < 1 &&
                   abs(b.width - bw) < 1 && abs(b.height - bh) < 1 {
                    page.removeAnnotation(ann)
                    break
                }
            }
        }
        annotations.remove(at: idx)
        persist()
    }

    /// Build a text-mark annotation (highlight/underline/strike) from current selection.
    func addTextMark(type: AnnotationType, color: NSColor) {
        guard let sel = pdfView?.currentSelection, let page = sel.pages.first else { return }
        let pageIndex = pdfDocument.index(for: page)
        var union = CGRect.zero
        var quads: [CPoint] = []
        for line in sel.selectionsByLine() {
            guard let lp = line.pages.first else { continue }
            let b = line.bounds(for: lp)
            if union == .zero { union = b } else { union = union.union(b) }
            quads.append(CPoint(x: Double(b.minX), y: Double(b.minY)))
            quads.append(CPoint(x: Double(b.maxX), y: Double(b.minY)))
            quads.append(CPoint(x: Double(b.maxX), y: Double(b.maxY)))
            quads.append(CPoint(x: Double(b.minX), y: Double(b.maxY)))
        }
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: type,
            bounds: CRect(x: Double(union.minX), y: Double(union.minY), w: Double(union.width), h: Double(union.height)),
            quadPoints: quads, color: CodableColor(color), contents: nil, createdAt: Date()
        )
        addAnnotation(ann)
    }

    /// Build a shape annotation from a drag rectangle in page coordinates.
    func addShape(type: AnnotationType, rect: CGRect, color: NSColor) {
        let pageIndex = currentPage
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: type,
            bounds: CRect(x: Double(rect.minX), y: Double(rect.minY), w: Double(rect.width), h: Double(rect.height)),
            quadPoints: nil, color: CodableColor(color), contents: nil, createdAt: Date()
        )
        addAnnotation(ann)
    }

    /// Build a note annotation from current selection bounds.
    func addNote(text: String, color: NSColor) {
        guard let sel = pdfView?.currentSelection, let page = sel.pages.first else { return }
        let pageIndex = pdfDocument.index(for: page)
        let b = sel.bounds(for: page)
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .note,
            bounds: CRect(x: Double(b.minX), y: Double(b.minY), w: max(20, Double(b.width)), h: max(20, Double(b.height))),
            quadPoints: nil, color: CodableColor(color), contents: text, createdAt: Date()
        )
        addAnnotation(ann)
    }

    func exportAnnotationsMarkdown() -> String {
        guard !annotations.isEmpty else { return "（无标注）" }
        var out = "# \(fileName) 标注导出\n\n"
        let sorted = annotations.sorted { $0.pageIndex < $1.pageIndex }
        for a in sorted {
            out += "- 第 \(a.pageIndex + 1) 页 · \(a.type.label)\n"
            if let c = a.contents, !c.isEmpty { out += "  > \(c)\n" }
        }
        return out
    }

    // MARK: Search

    func search(_ text: String, caseSensitive: Bool, wholeWord: Bool) {
        searchText = text
        searchMatches.removeAll()
        guard !text.isEmpty, !isLocked else { pdfView?.highlightedSelections = nil; return }
        if wholeWord {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: text))\\b"
            var opts: NSString.CompareOptions = [.regularExpression]
            if !caseSensitive { opts.insert(.caseInsensitive) }
            searchMatches = pdfDocument.findString(pattern, withOptions: opts)
        } else {
            var opts: NSString.CompareOptions = []
            if !caseSensitive { opts.insert(.caseInsensitive) }
            searchMatches = pdfDocument.findString(text, withOptions: opts)
        }
        pdfView?.highlightedSelections = searchMatches
    }

    func goToSearchResult(_ index: Int) {
        guard index >= 0, index < searchMatches.count else { return }
        let sel = searchMatches[index]
        pdfView?.setCurrentSelection(sel, animate: true)
        if let page = sel.pages.first { pdfView?.go(to: page) }
    }

    // MARK: Snapshot

    /// Copy the current page as a high-resolution image to the pasteboard.
    func copyPageImage() {
        guard let page = pdfDocument.page(at: currentPage) else { return }
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let img = page.thumbnail(of: size, for: .mediaBox)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }
}
