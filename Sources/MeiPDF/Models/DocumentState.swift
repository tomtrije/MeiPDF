import Foundation
import PDFKit
import SwiftUI
import AppKit
import AVFoundation

/// Identifies a note annotation whose contents are being edited via the popover.
/// `id` is the stable annotation id; `pageIndex` lets the popover jump to the page.
struct NoteEditTarget: Identifiable {
    let id: UUID
    let pageIndex: Int
}

enum DocError: Error { case cannotOpen, locked }

@MainActor
@Observable
final class DocumentState: Identifiable {
    let id = UUID()
    let fileURL: URL?
    let fileName: String
    let pdfDocument: PDFDocument
    var isLocked: Bool = false

    // MARK: 状态（运行时实时变化，如当前页 / 缩放；关闭文档即重置）
    // ---- page-level STATUS (per document, reset when closed) ----
    var currentPage: Int = 0          // 当前页（状态）
    var scaleFactor: CGFloat = 1.0    // 缩放倍数（状态）
    /// When `true`, the zoom factor is locked to `scaleFactor` (manually set / fit /
    /// actual). When `false`, the view fits automatically. Survives tab switches.
    var zoomLocked: Bool = false      // 缩放锁定（状态）
    /// Ensures the app's default-zoom preference is applied exactly once (on the
    /// first `updateNSView`, when the view's bounds are known).
    var defaultZoomApplied: Bool = false

    /// Back/forward navigation history of explicitly-jumped pages (see `goToPage`).
    private var navHistory: [Int] = []
    private var navPos: Int = -1

    // MARK: 配置（影响功能 / 渲染、可持久化；重新打开文档时恢复）
    // ---- file-level viewing CONFIG (restored on reopen) ----
    var displayMode: PDFDisplayMode
    var displayDirection: PDFDisplayDirection
    var rotation: Int = 0
    var theme: Theme

    // ---- file-level annotation style CONFIG (restored on reopen) ----
    var activeTool: AnnotationType? = nil
    var activeColor: NSColor = NSColor.systemYellow
    var activeLineWidth: Double = 2
    var activeLineStyle: LineStyle = .solid
    var activeFill: Bool = false

    // Image captured by the signature sheet, awaiting a click on the page to stamp.
    var pendingSignature: NSImage? = nil

    /// When set, the ContentView shows a popover to edit this note annotation's
    /// text (clicked directly on the page). `nil` dismisses the popover.
    var editingNote: NoteEditTarget? = nil

    // ---- page-level bookmark CONFIG: page index -> display name ----
    var bookmarks: [Int: String] = [:]

    // ---- user's own (non-destructive) annotations (CONFIG) ----
    var annotations: [Annotation] = []

    /// When `false`, markup annotations (highlight/underline/strike/note/shapes/…)
    /// are hidden — mirrors Preview's "显示高亮与备注" toggle (view-only, non-destructive).
    var showAnnotations: Bool = true

    weak var pdfView: MeiPDFView?

    // search
    var searchMatches: [PDFSelection] = []
    var searchText: String = ""
    /// Index into `searchMatches` of the currently shown result (shared with the
    /// toolbar search field and the Edit-menu find commands).
    var searchResultIndex: Int = 0

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
        self.activeLineWidth = preferences.defaultLineWidth
        self.activeLineStyle = preferences.defaultLineStyle
        self.activeFill = preferences.defaultFill
        if doc.isLocked {
            self.isLocked = true
        } else {
            loadMeta()
            applyStartPage()
        }
        // Seed the back/forward history with the page we opened on.
        navHistory = [currentPage]
        navPos = 0
    }

    /// Honour the "start page" preference (cover / last-read / first bookmark).
    private func applyStartPage() {
        switch preferences.startPageMode {
        case .cover:
            currentPage = 0
        case .last:
            break // keep `lastPage` from meta (or 0 on first open)
        case .firstBookmark:
            if let first = bookmarks.keys.sorted().first { currentPage = first }
        }
    }

    // MARK: Meta

    private func loadMeta() {
        guard let url = fileURL, let meta = MetaStore.load(for: url) else { return }
        bookmarks = meta.bookmarks
        rotation = meta.rotation
        annotations = meta.annotations
        currentPage = meta.lastPage
        // Restore file-level viewing settings (overridden by global defaults until
        // the user changes them in this session).
        if let th = Theme(rawValue: meta.theme) { theme = th }
        displayMode = PDFDisplayMode(rawValue: meta.displayMode) ?? preferences.defaultDisplayMode
        displayDirection = PDFDisplayDirection(rawValue: meta.displayDirection) ?? preferences.defaultDisplayDirection
        if meta.activeColor.count == 4 {
            activeColor = NSColor(srgbRed: meta.activeColor[0], green: meta.activeColor[1],
                                  blue: meta.activeColor[2], alpha: meta.activeColor[3])
        }
        activeLineWidth = meta.lineWidth
        if let ls = LineStyle(rawValue: meta.lineStyle) { activeLineStyle = ls }
        activeFill = meta.hasFill
        removedNativeKeys = meta.removedNativeKeys ?? []
        applyRotationToPages()
        rebuildAnnotationsOnPages()
        applyRemovedNativeAnnotations()
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
        let c = activeColor.usingColorSpace(.sRGB) ?? activeColor
        let meta = DocumentMeta(
            bookmarks: bookmarks,
            lastPage: currentPage,
            rotation: rotation,
            annotations: annotations,
            theme: theme.rawValue,
            displayMode: displayMode.rawValue,
            displayDirection: displayDirection.rawValue,
            activeColor: [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent],
            lineWidth: activeLineWidth,
            lineStyle: activeLineStyle.rawValue,
            hasFill: activeFill,
            removedNativeKeys: removedNativeKeys
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

    func goToPage(_ index: Int, record: Bool = true) {
        guard index >= 0, index < pdfDocument.pageCount else { return }
        guard let page = pdfDocument.page(at: index) else { return }
        pdfView?.go(to: page)
        currentPage = index
        if record {
            // Drop any "forward" branch, then append the new page if it differs.
            if navPos < navHistory.count - 1 {
                navHistory.removeSubrange((navPos + 1)...)
            }
            if navHistory.last != index {
                navHistory.append(index)
                navPos = navHistory.count - 1
            }
        }
    }

    // MARK: Back / Forward (前往 > 后退 / 前进)

    var canGoBack: Bool { navPos > 0 }
    var canGoForward: Bool { navPos < navHistory.count - 1 }

    func goBack() {
        guard canGoBack else { return }
        navPos -= 1
        goToPage(navHistory[navPos], record: false)
    }
    func goForward() {
        guard canGoForward else { return }
        navPos += 1
        goToPage(navHistory[navPos], record: false)
    }
    func nextPage() { pdfView?.goToNextPage(nil) }
    func previousPage() { pdfView?.goToPreviousPage(nil) }
    func firstPage() { pdfView?.goToFirstPage(nil) }
    func lastPage() { pdfView?.goToLastPage(nil) }

    // MARK: Zoom

    func zoomIn() {
        guard let view = pdfView else { return }
        view.autoScales = false
        view.zoomIn(nil)
        scaleFactor = view.scaleFactor
        zoomLocked = true
    }
    func zoomOut() {
        guard let view = pdfView else { return }
        view.autoScales = false
        view.zoomOut(nil)
        scaleFactor = view.scaleFactor
        zoomLocked = true
    }
    func setScale(_ factor: CGFloat) {
        guard let view = pdfView else { return }
        view.scaleFactor = max(0.1, min(8, factor))
        scaleFactor = view.scaleFactor
        zoomLocked = true
    }
    func actualSize() {
        guard let view = pdfView else { return }
        view.autoScales = false
        view.scaleFactor = 1.0
        scaleFactor = 1.0
        zoomLocked = true
    }
    func fitWidth() {
        guard let view = pdfView, let page = pdfDocument.page(at: currentPage) else { return }
        view.autoScales = false
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0 else { return }
        setScale(view.bounds.width / pageRect.width)
    }
    func fitPage() {
        guard let view = pdfView, let page = pdfDocument.page(at: currentPage) else { return }
        view.autoScales = false
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return }
        let sx = view.bounds.width / pageRect.width
        let sy = view.bounds.height / pageRect.height
        setScale(min(sx, sy))
    }
    /// Fit the page height to the viewport (Preview's "适应高度" — only the vertical
    /// extent fills the window; width may overflow and scroll horizontally).
    func fitHeight() {
        guard let view = pdfView, let page = pdfDocument.page(at: currentPage) else { return }
        view.autoScales = false
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.height > 0 else { return }
        setScale(view.bounds.height / pageRect.height)
    }

    // MARK: Bookmarks (page-level)

    func toggleBookmark(_ page: Int) {
        if bookmarks[page] != nil { bookmarks.removeValue(forKey: page) }
        else { bookmarks[page] = "第 \(page + 1) 页" }
        persist()
    }
    func isBookmarked(_ page: Int) -> Bool { bookmarks[page] != nil }
    func renameBookmark(page: Int, name: String) {
        bookmarks[page] = name.isEmpty ? "第 \(page + 1) 页" : name
        persist()
    }
    func removeBookmark(page: Int) {
        bookmarks.removeValue(forKey: page)
        persist()
    }

    // MARK: Defaults (app-level)

    /// Promote the current document's viewing + annotation-style settings to the
    /// global app defaults, so that documents opened afterwards start with them.
    func saveAsDefault() {
        preferences.defaultTheme = theme
        preferences.defaultDisplayMode = displayMode
        preferences.defaultDisplayDirection = displayDirection
        preferences.defaultColor = CodableColor(activeColor)
        preferences.defaultLineWidth = activeLineWidth
        preferences.defaultLineStyle = activeLineStyle
        preferences.defaultFill = activeFill
        preferences.save()
    }

    // MARK: Annotations (non-destructive, user's own)

    private func subtype(for type: AnnotationType) -> PDFAnnotationSubtype {
        switch type {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        case .note: return .text
        case .square: return .square
        case .circle: return .circle
        case .line, .arrow: return .line
        case .ink: return .ink
        case .freeText: return .freeText
        case .signature: return .stamp
        }
    }

    private func makePDFAnnotation(_ a: Annotation) -> PDFAnnotation? {
        guard let page = pdfDocument.page(at: a.pageIndex) else { return nil }
        let b = NSRect(x: a.bounds.x, y: a.bounds.y, width: a.bounds.w, height: a.bounds.h)
        // Signature: a stamp annotation that draws our captured image (non-destructive).
        if a.type == .signature {
            if let data = a.imageData, let img = NSImage(data: data) {
                let ann = ImageStampAnnotation(bounds: b, image: img,
                                               userName: "MeiPDF:" + a.id.uuidString)
                ann.shouldDisplay = showAnnotations
                return ann
            }
            return nil
        }
        let ann = PDFAnnotation(bounds: b, forType: subtype(for: a.type), withProperties: nil)
        // Tag ours so the sidebar can tell them apart from annotations authored by
        // Preview / other editors, and so dragging / deletion can find them back.
        // Encode the stable id in `userName` ("MeiPDF:<uuid>") — this SDK has no
        // `name` property on PDFAnnotation, but `userName` is reliably present.
        ann.userName = "MeiPDF:" + a.id.uuidString
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
            configureBorder(ann, width: a.lineWidth, style: a.lineStyle)
            if a.hasFill {
                ann.interiorColor = a.color.nsColor.withAlphaComponent(0.22)
            }
        case .line, .arrow:
            ann.color = a.color.nsColor
            configureBorder(ann, width: a.lineWidth, style: a.lineStyle)
            // `startPoint`/`endPoint` are specified RELATIVE to the annotation's
            // bounds (same convention as quadrilateralPoints and ink paths in this
            // SDK). The previous absolute page coordinates landed outside the
            // bounds, so the line was clipped away and rendered invisible.
            // Rebuild the box from the endpoints with padding so perfectly
            // horizontal / vertical lines never get a degenerate (zero-height or
            // zero-width) bounds.
            let s = a.lineStart.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: b.minX, y: b.minY)
            let e = a.lineEnd.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: b.maxX, y: b.maxY)
            let pad: CGFloat = 2
            let box = CGRect(x: min(s.x, e.x) - pad, y: min(s.y, e.y) - pad,
                             width: abs(e.x - s.x) + 2 * pad, height: abs(e.y - s.y) + 2 * pad)
            ann.bounds = box
            ann.startPoint = CGPoint(x: s.x - box.minX, y: s.y - box.minY)
            ann.endPoint = CGPoint(x: e.x - box.minX, y: e.y - box.minY)
            if a.type == .arrow { ann.endLineStyle = .closedArrow }
        case .ink:
            ann.color = a.color.nsColor
            configureBorder(ann, width: a.lineWidth, style: a.lineStyle)
            if let strokes = a.inkPoints {
                // Ink paths are specified relative to the annotation's bounds
                // (origin at bottom-left, Y up) — same convention as quadrilaterals.
                for stroke in strokes {
                    let path = NSBezierPath()
                    for (i, pt) in stroke.enumerated() {
                        let rx = CGFloat(pt.x) - b.minX
                        let ry = CGFloat(pt.y) - b.minY
                        if i == 0 { path.move(to: CGPoint(x: rx, y: ry)) }
                        else { path.line(to: CGPoint(x: rx, y: ry)) }
                    }
                    ann.add(path)
                }
            }
        case .freeText:
            ann.contents = a.contents ?? "文本"
            ann.color = a.color.nsColor
            ann.font = NSFont.systemFont(ofSize: max(11, a.lineWidth * 6))
            ann.alignment = NSTextAlignment.left
        case .signature:
            break // handled earlier (returns an ImageStampAnnotation before this switch)
        }
        ann.shouldDisplay = showAnnotations
        _ = page
        return ann
    }

    private func configureBorder(_ ann: PDFAnnotation, width: Double, style: LineStyle) {
        let border = PDFBorder()
        border.lineWidth = width
        if let pattern = style.dashPattern { border.dashPattern = pattern }
        ann.border = border
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
        if let page = pdfDocument.page(at: a.pageIndex) {
            // Match by the stable id we stamped into `userName` — robust against any
            // floating-point drift in bounds. Remove EVERY match (duplicates from
            // older live-draw sessions must not linger on the page).
            let key = "MeiPDF:" + id.uuidString
            for ann in page.annotations where ann.userName == key {
                page.removeAnnotation(ann)
            }
        }
        annotations.remove(at: idx)
        persist()
    }

    /// Called after an in-page drag of one of our own annotations: persist the new
    /// geometry (bounds, and for lines the endpoints).
    func updateAnnotation(id: UUID, bounds: CGRect, start: CGPoint?, end: CGPoint?) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        var a = annotations[idx]
        a.bounds = CRect(x: Double(bounds.origin.x), y: Double(bounds.origin.y),
                         w: Double(bounds.width), h: Double(bounds.height))
        if let s = start { a.lineStart = CPoint(x: Double(s.x), y: Double(s.y)) }
        if let e = end { a.lineEnd = CPoint(x: Double(e.x), y: Double(e.y)) }
        annotations[idx] = a
        persist()
    }

    func renameAnnotation(id: UUID, name: String) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].name = name.isEmpty ? nil : name
        persist()
    }

    /// Update the text contents of one of our annotations (used by the note editor
    /// popover; the live PDFAnnotation's `contents` is updated by the caller).
    func updateAnnotationContents(id: UUID, contents: String) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[idx].contents = contents
        persist()
    }

    // MARK: Native (foreign) annotations

    /// Bumped whenever in-memory PDF state that views derive from changes (e.g. a
    /// foreign annotation is removed) — gives observing views a tracking handle.
    var nativeAnnotationsRevision: Int = 0
    /// Fingerprints of foreign (Preview-authored) annotations the user deleted.
    /// Persisted in the sidecar so deletions survive reopening the document
    /// (the source file itself is never modified).
    var removedNativeKeys: [String] = []

    func nativeAnnotationItems() -> [(pageIndex: Int, annotation: PDFAnnotation)] {
        guard !isLocked else { return [] }
        // Touch the revision counter so SwiftUI observes it: deleting a foreign
        // annotation bumps `nativeAnnotationsRevision`, and without reading it here
        // the sidebar list would not refresh (the page mutation alone is invisible
        // to observation).
        let _ = nativeAnnotationsRevision
        var items: [(Int, PDFAnnotation)] = []
        for i in 0..<pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            for ann in page.annotations where ann.userName?.hasPrefix("MeiPDF") == false {
                items.append((i, ann))
            }
        }
        return items
    }

    private func nativeFingerprint(_ ann: PDFAnnotation, pageIndex: Int) -> String {
        let b = ann.bounds
        return "\(pageIndex)|\(ann.type ?? "?")|\(Int(b.origin.x))|\(Int(b.origin.y))|\(Int(b.width))|\(Int(b.height))|\(ann.contents ?? "")"
    }

    func removeNativeAnnotation(pageIndex: Int, annotation: PDFAnnotation) {
        guard !isLocked else { return }
        let key = nativeFingerprint(annotation, pageIndex: pageIndex)
        if !removedNativeKeys.contains(key) { removedNativeKeys.append(key) }
        pdfDocument.page(at: pageIndex)?.removeAnnotation(annotation)
        // Mutate an @Observable property so the sidebar re-renders immediately
        // (page-annotation removal alone is invisible to SwiftUI observation).
        nativeAnnotationsRevision += 1
        persist()
    }

    /// Re-apply persisted foreign-annotation deletions after (re)loading a document.
    private func applyRemovedNativeAnnotations() {
        guard !removedNativeKeys.isEmpty else { return }
        for i in 0..<pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            for ann in page.annotations {
                if ann.userName?.hasPrefix("MeiPDF") == true { continue }
                if removedNativeKeys.contains(nativeFingerprint(ann, pageIndex: i)) {
                    page.removeAnnotation(ann)
                }
            }
        }
    }

    // MARK: Annotation visibility (view-only)

    /// Show or hide all markup annotations (highlight / underline / strike / note /
    /// shapes / ink / text / stamp). Mirrors Preview's "显示高亮与备注". Links, outlines
    /// and widgets are left alone. Non-destructive — never written back to the file.
    func setAnnotationsVisible(_ visible: Bool) {
        showAnnotations = visible
        for i in 0..<pageCount {
            guard let page = pdfDocument.page(at: i) else { continue }
            for ann in page.annotations where isMarkupAnnotation(ann) {
                ann.shouldDisplay = visible
            }
        }
        pdfView?.layoutDocumentView()
    }
    func toggleAnnotationsVisible() { setAnnotationsVisible(!showAnnotations) }

    private func isMarkupAnnotation(_ ann: PDFAnnotation) -> Bool {
        guard let t = ann.type else { return false }
        return ["Highlight", "Underline", "StrikeOut", "Square", "Circle",
                "Line", "Ink", "FreeText", "Text", "Stamp"].contains(t)
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
            // Quadrilateral points are specified **relative to the annotation's
            // bounding box** (PDF spec 12.5.6.14), origin at the box's bottom-left,
            // with the Y axis pointing up. Using absolute page coordinates is what
            // previously made highlights/underlines/strike-outs never render.
            let ox = union.origin.x, oy = union.origin.y
            quads.append(CPoint(x: Double(b.minX - ox), y: Double(b.minY - oy))) // BL
            quads.append(CPoint(x: Double(b.maxX - ox), y: Double(b.minY - oy))) // BR
            quads.append(CPoint(x: Double(b.maxX - ox), y: Double(b.maxY - oy))) // TR
            quads.append(CPoint(x: Double(b.minX - ox), y: Double(b.maxY - oy))) // TL
        }
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: type,
            bounds: CRect(x: Double(union.minX), y: Double(union.minY), w: Double(union.width), h: Double(union.height)),
            quadPoints: quads, color: CodableColor(color), contents: nil,
            name: type.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill
        )
        addAnnotation(ann)
    }

    /// Build a shape annotation from a drag rectangle. `pageIndex` is the page the
    /// user actually drew on (not `currentPage`, which can be stale during a drag).
    func addShape(type: AnnotationType, rect: CGRect, color: NSColor, pageIndex: Int) {
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: type,
            bounds: CRect(x: Double(rect.minX), y: Double(rect.minY), w: Double(rect.width), h: Double(rect.height)),
            quadPoints: nil, color: CodableColor(color), contents: nil,
            name: type.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill
        )
        addAnnotation(ann)
    }

    /// Build a line annotation from explicit start/end points.
    func addLine(start: CGPoint, end: CGPoint, color: NSColor, pageIndex: Int) {
        let bx = min(start.x, end.x), by = min(start.y, end.y)
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .line,
            bounds: CRect(x: Double(bx), y: Double(by), w: Double(abs(end.x - start.x)), h: Double(abs(end.y - start.y))),
            quadPoints: nil, color: CodableColor(color), contents: nil,
            name: AnnotationType.line.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill,
            lineStart: CPoint(x: Double(start.x), y: Double(start.y)),
            lineEnd: CPoint(x: Double(end.x), y: Double(end.y))
        )
        addAnnotation(ann)
    }

    /// Build a note annotation. The icon is placed at the top-left of the selection
    /// as a small fixed-size marker so it does not cover the selected text.
    func addNote(text: String, color: NSColor) {
        guard let sel = pdfView?.currentSelection, let page = sel.pages.first else { return }
        let pageIndex = pdfDocument.index(for: page)
        let b = sel.bounds(for: page)
        let size: CGFloat = 22
        let nb = CGRect(x: b.minX, y: b.maxY - size, width: size, height: size)
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .note,
            bounds: CRect(x: Double(nb.minX), y: Double(nb.minY), w: Double(nb.width), h: Double(nb.height)),
            quadPoints: nil, color: CodableColor(color), contents: text,
            name: "笔记",
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill
        )
        addAnnotation(ann)
    }

    /// Build an arrow annotation (a line with a closed arrowhead at the end).
    func addArrow(start: CGPoint, end: CGPoint, color: NSColor, pageIndex: Int) {
        let bx = min(start.x, end.x), by = min(start.y, end.y)
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .arrow,
            bounds: CRect(x: Double(bx), y: Double(by), w: Double(abs(end.x - start.x)), h: Double(abs(end.y - start.y))),
            quadPoints: nil, color: CodableColor(color), contents: nil,
            name: AnnotationType.arrow.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill,
            lineStart: CPoint(x: Double(start.x), y: Double(start.y)),
            lineEnd: CPoint(x: Double(end.x), y: Double(end.y))
        )
        addAnnotation(ann)
    }

    /// Build a freehand (ink) annotation from a captured stroke (page coordinates).
    func addInk(points: [CGPoint], color: NSColor, pageIndex: Int) {
        guard points.count > 1 else { return }
        var minX = points[0].x, minY = points[0].y, maxX = points[0].x, maxY = points[0].y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let pad: CGFloat = 4
        let b = CGRect(x: minX - pad, y: minY - pad,
                       width: (maxX - minX) + 2 * pad, height: (maxY - minY) + 2 * pad)
        let strokes: [[CPoint]] = [points.map { CPoint(x: Double($0.x), y: Double($0.y)) }]
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .ink,
            bounds: CRect(x: Double(b.minX), y: Double(b.minY), w: Double(b.width), h: Double(b.height)),
            quadPoints: nil, color: CodableColor(color), contents: nil,
            name: AnnotationType.ink.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill,
            inkPoints: strokes
        )
        addAnnotation(ann)
    }

    /// Build a free-text (text box) annotation placed at an explicit bounds.
    func addFreeText(bounds: CGRect, color: NSColor, pageIndex: Int) {
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .freeText,
            bounds: CRect(x: Double(bounds.minX), y: Double(bounds.minY), w: Double(bounds.width), h: Double(bounds.height)),
            quadPoints: nil, color: CodableColor(color), contents: "文本",
            name: AnnotationType.freeText.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill
        )
        addAnnotation(ann)
    }

    /// Build a signature (stamp) annotation from captured image data (PNG).
    func addSignature(bounds: CGRect, imageData: Data, color: NSColor, pageIndex: Int) {
        let ann = Annotation(
            id: UUID(), pageIndex: pageIndex, type: .signature,
            bounds: CRect(x: Double(bounds.minX), y: Double(bounds.minY), w: Double(bounds.width), h: Double(bounds.height)),
            quadPoints: nil, color: CodableColor(color), contents: nil,
            name: AnnotationType.signature.label,
            createdAt: Date(),
            lineWidth: activeLineWidth, lineStyle: activeLineStyle, hasFill: activeFill,
            imageData: imageData
        )
        addAnnotation(ann)
    }

    func exportAnnotationsMarkdown() -> String {
        guard !annotations.isEmpty else { return "（无标注）" }
        var out = "# \(fileName) 标注导出\n\n"
        let sorted = annotations.sorted { $0.pageIndex < $1.pageIndex }
        for a in sorted {
            let label = a.name ?? a.type.label
            out += "- 第 \(a.pageIndex + 1) 页 · \(label)\n"
            if let c = a.contents, !c.isEmpty { out += "  > \(c)\n" }
        }
        return out
    }

    // MARK: Search

    func search(_ text: String, caseSensitive: Bool, wholeWord: Bool) {
        searchText = text
        searchMatches.removeAll()
        searchResultIndex = 0
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

    /// Advance / rewind the active search result (used by the toolbar arrows and the
    /// Edit-menu 查找下一个 / 查找上一个, ⌘G / ⌘⇧G). Wraps around.
    func searchNext() {
        guard !searchMatches.isEmpty else { return }
        searchResultIndex = (searchResultIndex + 1) % searchMatches.count
        goToSearchResult(searchResultIndex)
    }
    func searchPrevious() {
        guard !searchMatches.isEmpty else { return }
        searchResultIndex = (searchResultIndex - 1 + searchMatches.count) % searchMatches.count
        goToSearchResult(searchResultIndex)
    }

    // MARK: Snapshot

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

    // MARK: Annotation navigation (ours + foreign/Preview ones)

    /// Combined, sorted list of every annotation in the document: ours (by stored
    /// geometry) and the foreign ones authored by Preview / other tools. Ordered by
    /// page, then top-to-bottom within a page (Y up, so larger origin wins).
    func annotationNavItems() -> [(pageIndex: Int, order: CGFloat)] {
        var items: [(Int, CGFloat)] = []
        for a in annotations { items.append((a.pageIndex, CGFloat(a.bounds.y))) }
        for (i, ann) in nativeAnnotationItems() {
            items.append((i, CGFloat(ann.bounds.origin.y)))
        }
        items.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }
        return items
    }

    func goToNextAnnotation() {
        let items = annotationNavItems()
        guard !items.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.pageIndex == currentPage }),
           idx + 1 < items.count {
            goToPage(items[idx + 1].pageIndex)
        } else if let n = items.first(where: { $0.pageIndex > currentPage }) {
            goToPage(n.pageIndex)
        } else {
            goToPage(items[0].pageIndex)
        }
    }

    func goToPreviousAnnotation() {
        let items = annotationNavItems()
        guard !items.isEmpty else { return }
        if let idx = items.lastIndex(where: { $0.pageIndex == currentPage }), idx > 0 {
            goToPage(items[idx - 1].pageIndex)
        } else if let n = items.last(where: { $0.pageIndex < currentPage }) {
            goToPage(n.pageIndex)
        } else {
            goToPage(items[items.count - 1].pageIndex)
        }
    }

    // MARK: Bookmark navigation

    func goToNextBookmark() {
        let pages = bookmarks.keys.sorted()
        guard !pages.isEmpty else { return }
        if let n = pages.first(where: { $0 > currentPage }) {
            goToPage(n)
        } else {
            goToPage(pages[0])
        }
    }

    func goToPreviousBookmark() {
        let pages = bookmarks.keys.sorted()
        guard !pages.isEmpty else { return }
        if let n = pages.last(where: { $0 < currentPage }) {
            goToPage(n)
        } else {
            goToPage(pages[pages.count - 1])
        }
    }

    // MARK: Default zoom on open

    /// Apply the app's "default zoom" preference to a freshly created view. Called
    /// from the PDFView wrapper once the view's bounds are known.
    func applyDefaultZoom(in view: PDFView) {
        guard preferences.defaultZoom != .none else { return }
        guard let page = pdfDocument.page(at: currentPage) else { return }
        let pr = page.bounds(for: .mediaBox)
        view.autoScales = false
        switch preferences.defaultZoom {
        case .fitWidth:
            guard pr.width > 0 else { return }
            view.scaleFactor = view.bounds.width / pr.width
        case .fitPage:
            guard pr.width > 0, pr.height > 0 else { return }
            view.scaleFactor = min(view.bounds.width / pr.width, view.bounds.height / pr.height)
        case .fitHeight:
            guard pr.height > 0 else { return }
            view.scaleFactor = view.bounds.height / pr.height
        case .actual:
            view.scaleFactor = 1.0
        case .none:
            break
        }
        scaleFactor = view.scaleFactor
        zoomLocked = true
    }

    // MARK: Export pages as PNG

    /// Render a single page to a PNG file at 2× scale (matches Preview's default export).
    func exportPagePNG(to url: URL, index: Int) {
        guard let page = pdfDocument.page(at: index) else { return }
        let rect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let img = page.thumbnail(of: NSSize(width: rect.width * scale, height: rect.height * scale), for: .mediaBox)
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// Export every page as `<name>_pN.png` into the chosen folder.
    func exportAllPagesPNG(to folder: URL) {
        let base = (fileName as NSString).deletingPathExtension
        for i in 0..<pageCount {
            let name = "\(base)_p\(i + 1).png"
            exportPagePNG(to: folder.appendingPathComponent(name), index: i)
        }
    }

    // MARK: Export plain text

    /// Concatenate the extracted text of every page into a UTF-8 text file.
    func exportText(to url: URL) {
        var out = ""
        for i in 0..<pageCount {
            if let page = pdfDocument.page(at: i), let text = page.string {
                out += text
                if !text.hasSuffix("\n") { out += "\n" }
            }
        }
        try? out.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Export flattened PDF

    /// Write the current document (including all in-memory annotations we added to
    /// its pages) to a NEW file. Original is never touched — this is an export, not
    /// an edit, consistent with MeiPDF's "viewing-only" scope.
    @discardableResult
    func exportPDF(to url: URL) -> Bool {
        guard !isLocked else { return false }
        // When annotations are excluded, copy the original file verbatim (our marks
        // live only in memory and are never written back to the source).
        if !preferences.exportWithAnnotations, let u = fileURL, let data = try? Data(contentsOf: u) {
            try? data.write(to: url)
            return true
        }
        return pdfDocument.write(to: url)
    }

    // MARK: Page image (for slideshow / inspector)

    /// Render a page to a bitmap image scaled to fit within `maxSize` (capped at 4×).
    func pageImage(at index: Int, maxSize: CGSize) -> NSImage? {
        guard let page = pdfDocument.page(at: index) else { return nil }
        let rect = page.bounds(for: .mediaBox)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scale = min(maxSize.width / rect.width, maxSize.height / rect.height, 4)
        guard scale > 0 else { return nil }
        let size = NSSize(width: rect.width * scale, height: rect.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    // MARK: Speech (朗读 — 对齐预览的朗读功能)

    private var speechSynthesizer: AVSpeechSynthesizer?

    /// Speak the text of the currently displayed page.
    func speakPage() {
        guard let page = pdfDocument.page(at: currentPage),
              let text = page.string, !text.isEmpty else { return }
        if speechSynthesizer == nil { speechSynthesizer = AVSpeechSynthesizer() }
        speechSynthesizer?.speak(AVSpeechUtterance(string: text))
    }

    /// Speak the current text selection (falls back to the page text if none).
    func speakSelection() {
        if let sel = pdfView?.currentSelection, let text = sel.string, !text.isEmpty {
            if speechSynthesizer == nil { speechSynthesizer = AVSpeechSynthesizer() }
            speechSynthesizer?.speak(AVSpeechUtterance(string: text))
        } else {
            speakPage()
        }
    }

    func stopSpeaking() { speechSynthesizer?.stopSpeaking(at: .immediate) }
    var isSpeaking: Bool { speechSynthesizer?.isSpeaking ?? false }
}
