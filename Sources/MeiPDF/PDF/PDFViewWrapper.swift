import SwiftUI
import PDFKit
import AppKit

/// A stamp annotation that renders a captured signature image. PDFKit has no public
/// image-annotation property, so we subclass and draw the `NSImage` in `draw`.
final class ImageStampAnnotation: PDFAnnotation {
    var image: NSImage?

    init(bounds: CGRect, image: NSImage, userName: String) {
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
        self.image = image
        self.userName = userName
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Do NOT call super — the default stamp rendering draws a border frame
        // around the annotation (the "wireframe" that showed up on the page).
        guard let img = image,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let r = self.bounds
        context.saveGState()
        // The PDFKit draw context is already set up in page coordinates where a
        // direct image draw renders upright — the earlier manual Y-flip inverted
        // the signature. The rect below is identical to what the old transform
        // produced; only the content orientation changes (now correct).
        context.draw(cg, in: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
        context.restoreGState()
    }
}

extension NSImage {
    /// PNG representation (NSImage has no built-in png exporter).
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png
    }
}

/// PDFView subclass that additionally supports:
///  - drawing shape / line annotations via mouse drag when an annotation tool is active;
///  - dragging existing annotations (shapes, notes, lines, and foreign/Preview ones)
///    when no tool is active, so users can reposition marks directly on the page.
final class MeiPDFView: PDFView {
    weak var documentState: DocumentState?

    // Shape-creation drag state.
    private var dragStart: CGPoint?
    private var tempPage: PDFPage?
    private var tempAnn: PDFAnnotation?

    // Freehand (ink) creation state.
    private var inkPage: PDFPage?
    private var inkRawPoints: [CGPoint] = []
    private var inkTempAnn: PDFAnnotation?

    // Annotation-move drag state.
    private var moveAnn: PDFAnnotation?
    private var movePage: PDFPage?
    private var moveStart: CGPoint?
    private var moveOrigBounds: CGRect?
    private var moveOrigStart: CGPoint?
    private var moveOrigEnd: CGPoint?

    private func pagePoint(_ event: NSEvent, page: PDFPage) -> CGPoint {
        let viewPoint = self.convert(event.locationInWindow, from: nil)
        return self.convert(viewPoint, to: page)
    }

    /// Returns the topmost draggable annotation under the event, skipping text marks
    /// (highlight / underline / strike-out) so they never hijack text selection.
    private func draggableAnnotation(at event: NSEvent) -> (PDFPage, PDFAnnotation)? {
        guard let page = currentPage else { return nil }
        let p = pagePoint(event, page: page)
        for ann in page.annotations.reversed() {
            guard let t = ann.type else { continue }
            if t == "Highlight" || t == "Underline" || t == "StrikeOut" { continue }
            if ann.bounds.contains(p) { return (page, ann) }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        // Let right-clicks fall through to the system so the context menu shows.
        guard event.buttonNumber == 0 else { super.mouseDown(with: event); return }

        let tool = MainActor.assumeIsolated { documentState?.activeTool }
        if let tool, let page = currentPage {
            MainActor.assumeIsolated {
                let ds = self.documentState!
                let p = self.pagePoint(event, page: page)
                // Text box: click to drop an editable free-text annotation.
                if tool == .freeText {
                    let w: CGFloat = 150, h: CGFloat = 30
                    let b = CGRect(x: p.x, y: p.y - h, width: w, height: h)
                    let idx = ds.pdfDocument.index(for: page)
                    ds.addFreeText(bounds: b, color: ds.activeColor, pageIndex: idx)
                    ds.activeTool = nil
                    return
                }
                // Freehand: start capturing a stroke.
                if tool == .ink {
                    self.inkPage = page
                    self.inkRawPoints = [p]
                    let ann = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y, width: 1, height: 1), forType: .ink, withProperties: nil)
                    ann.color = ds.activeColor
                    let border = PDFBorder()
                    border.lineWidth = ds.activeLineWidth
                    if let pattern = ds.activeLineStyle.dashPattern { border.dashPattern = pattern }
                    ann.border = border
                page.addAnnotation(ann)
                self.inkTempAnn = ann
                return
            }
            // Signature: stamp the captured image at the click point.
            if tool == .signature {
                if let img = ds.pendingSignature, let data = img.pngData() {
                    let w = img.size.width, h = img.size.height
                    let targetW: CGFloat = 150
                    let scale = targetW / max(w, 1)
                    let bw = w * scale, bh = h * scale
                    let b = CGRect(x: p.x, y: p.y - bh, width: bw, height: bh)
                    let idx = ds.pdfDocument.index(for: page)
                    ds.addSignature(bounds: b, imageData: data, color: ds.activeColor, pageIndex: idx)
                }
                ds.pendingSignature = nil
                ds.activeTool = nil
                return
            }
            self.dragStart = p
            self.tempPage = page
                let subtype: PDFAnnotationSubtype = (tool == .circle) ? .circle : (tool == .line || tool == .arrow) ? .line : .square
                let ann = PDFAnnotation(bounds: NSRect(x: p.x, y: p.y, width: 1, height: 1), forType: subtype, withProperties: nil)
                ann.color = ds.activeColor
                if subtype == .line {
                    // startPoint/endPoint are relative to the annotation's bounds; the
                    // transient 1×1 box is anchored at the click point `p`, so both
                    // endpoints sit at the box origin (0,0) for now.
                    ann.startPoint = CGPoint(x: 0, y: 0)
                    ann.endPoint = CGPoint(x: 0, y: 0)
                } else {
                    let border = PDFBorder()
                    border.lineWidth = ds.activeLineWidth
                    if let pattern = ds.activeLineStyle.dashPattern { border.dashPattern = pattern }
                    ann.border = border
                    if ds.activeFill { ann.interiorColor = ds.activeColor.withAlphaComponent(0.22) }
                }
                page.addAnnotation(ann)
                self.tempAnn = ann
            }
            return
        }

        // No tool: try to grab an existing annotation.
        //  - Shapes / lines: custom drag (proven to move + persist reliably).
        //  - Notes (.text): hand the event to PDFView so a plain click opens the
        //    note's text popup for editing, while a drag still moves it via PDFView's
        //    native annotation dragging; we persist the new geometry on mouseUp.
        if let (page, ann) = draggableAnnotation(at: event) {
            moveAnn = ann
            movePage = page
            moveStart = pagePoint(event, page: page)
            moveOrigBounds = ann.bounds
            moveOrigStart = ann.startPoint
            moveOrigEnd = ann.endPoint
            if ann.type == "Note" {
                // Our own note: open the SwiftUI edit popover instead of the native
                // (often non-editable) PDFView note bubble. Foreign notes fall through
                // to PDFView's built-in popup.
                if let userName = ann.userName, userName.hasPrefix("MeiPDF:"),
                   let id = UUID(uuidString: String(userName.dropFirst("MeiPDF:".count))) {
                    let idx = self.document?.index(for: page) ?? 0
                    MainActor.assumeIsolated {
                        self.documentState?.editingNote = NoteEditTarget(id: id, pageIndex: idx)
                    }
                    return
                }
                super.mouseDown(with: event)
            }
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        // Freehand: accumulate stroke points and rebuild the live ink annotation.
        if let page = inkPage, inkTempAnn != nil {
            let p = pagePoint(event, page: page)
            inkRawPoints.append(p)
            MainActor.assumeIsolated {
                let ds = self.documentState!
                var minX = inkRawPoints[0].x, minY = inkRawPoints[0].y
                var maxX = minX, maxY = minY
                for q in inkRawPoints {
                    minX = min(minX, q.x); minY = min(minY, q.y)
                    maxX = max(maxX, q.x); maxY = max(maxY, q.y)
                }
                let pad: CGFloat = 4
                let b = CGRect(x: minX - pad, y: minY - pad,
                               width: (maxX - minX) + 2 * pad, height: (maxY - minY) + 2 * pad)
                let ann = PDFAnnotation(bounds: b, forType: .ink, withProperties: nil)
                ann.color = ds.activeColor
                let border = PDFBorder()
                border.lineWidth = ds.activeLineWidth
                if let pattern = ds.activeLineStyle.dashPattern { border.dashPattern = pattern }
                ann.border = border
                let path = NSBezierPath()
                path.move(to: CGPoint(x: inkRawPoints[0].x - b.minX, y: inkRawPoints[0].y - b.minY))
                for q in inkRawPoints.dropFirst() {
                    path.line(to: CGPoint(x: q.x - b.minX, y: q.y - b.minY))
                }
                ann.add(path)
                page.removeAnnotation(self.inkTempAnn!)
                page.addAnnotation(ann)
                self.inkTempAnn = ann
            }
            return
        }

        if let ann = moveAnn, let page = movePage, let start = moveStart, let orig = moveOrigBounds {
            if ann.type == "Note" {
                // Native drag handled by PDFView; geometry persisted on mouseUp.
                super.mouseDragged(with: event)
                return
            }
            // Custom move for shapes / lines (reliable, persists to our model).
            let p = pagePoint(event, page: page)
            let dx = p.x - start.x, dy = p.y - start.y
            var b = orig
            b.origin.x += dx; b.origin.y += dy
            ann.bounds = b
            if ann.type == "Line" {
                if let s = moveOrigStart, let e = moveOrigEnd {
                    ann.startPoint = CGPoint(x: s.x + dx, y: s.y + dy)
                    ann.endPoint = CGPoint(x: e.x + dx, y: e.y + dy)
                }
            }
            self.needsDisplay = true
            return
        }

        guard tempPage != nil, tempAnn != nil, dragStart != nil else {
            super.mouseDragged(with: event)
            return
        }
        let tool = MainActor.assumeIsolated { documentState?.activeTool }
        guard tool != nil else {
            super.mouseDragged(with: event)
            return
        }
        let page = tempPage!, ann = tempAnn!, start = dragStart!
        let p = pagePoint(event, page: page)
        let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                          width: abs(p.x - start.x), height: abs(p.y - start.y))
        ann.bounds = rect
        if tool == .line || tool == .arrow {
            // Keep endpoints relative to the (changing) bounds so the live preview
            // tracks the cursor correctly, matching how `makePDFAnnotation` rebuilds
            // the final annotation from its stored absolute points.
            ann.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            ann.endPoint = CGPoint(x: p.x - rect.minX, y: p.y - rect.minY)
        }
        self.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let ann = moveAnn, let _ = movePage {
            if ann.type == "Note" {
                super.mouseUp(with: event)
                // Persist the new position only if the note actually moved (a plain
                // click opens the popup instead and must not be treated as a move).
                if let id = meiPDFId(ann), noteMoved(ann) {
                    MainActor.assumeIsolated {
                        self.documentState?.updateAnnotation(id: id, bounds: ann.bounds,
                            start: ann.type == "Line" ? ann.startPoint : nil,
                            end: ann.type == "Line" ? ann.endPoint : nil)
                    }
                }
                resetMove()
                return
            }
            if let userName = ann.userName, userName.hasPrefix("MeiPDF:"),
               let id = UUID(uuidString: String(userName.dropFirst("MeiPDF:".count))) {
                MainActor.assumeIsolated {
                    self.documentState?.updateAnnotation(id: id, bounds: ann.bounds,
                        start: ann.type == "Line" ? ann.startPoint : nil,
                        end: ann.type == "Line" ? ann.endPoint : nil)
                }
            }
            resetMove()
            return
        }

        // Finalize a freehand stroke: drop the transient preview annotation and let
        // the model rebuild a durable one (with `inkPoints`) via `addInk`.
        if let page = inkPage, inkTempAnn != nil, inkRawPoints.count > 1 {
            let color = MainActor.assumeIsolated { self.documentState?.activeColor } ?? NSColor.systemYellow
            let idx = MainActor.assumeIsolated { self.documentState?.pdfDocument.index(for: page) } ?? 0
            MainActor.assumeIsolated {
                self.documentState?.addInk(points: self.inkRawPoints, color: color, pageIndex: idx)
                self.documentState?.activeTool = nil
            }
            page.removeAnnotation(self.inkTempAnn!)
        }
        inkPage = nil; inkRawPoints.removeAll(); inkTempAnn = nil

        guard let page = tempPage, let ann = tempAnn, let start = dragStart else {
            super.mouseUp(with: event)
            return
        }
        let tool = MainActor.assumeIsolated { documentState?.activeTool }
        guard tool != nil else {
            super.mouseUp(with: event)
            return
        }
        let pageIndex = MainActor.assumeIsolated { self.documentState?.pdfDocument.index(for: page) } ?? 0
        let p = pagePoint(event, page: page)
        page.removeAnnotation(ann)
        if tool == .line || tool == .arrow {
            let len = hypot(p.x - start.x, p.y - start.y)
            if len > 3 {
                let color = MainActor.assumeIsolated { self.documentState?.activeColor } ?? NSColor.systemYellow
                MainActor.assumeIsolated {
                    if tool == .arrow {
                        self.documentState?.addArrow(start: start, end: p, color: color, pageIndex: pageIndex)
                    } else {
                        self.documentState?.addLine(start: start, end: p, color: color, pageIndex: pageIndex)
                    }
                    self.documentState?.activeTool = nil
                }
            }
        } else {
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(p.x - start.x), height: abs(p.y - start.y))
            if rect.width > 3 && rect.height > 3 {
                let type: AnnotationType = (tool == .circle) ? .circle : .square
                let color = MainActor.assumeIsolated { self.documentState?.activeColor } ?? NSColor.systemYellow
                MainActor.assumeIsolated { self.documentState?.addShape(type: type, rect: rect, color: color, pageIndex: pageIndex) }
                MainActor.assumeIsolated { self.documentState?.activeTool = nil }
            }
        }
        tempAnn = nil; tempPage = nil; dragStart = nil
    }

    // MARK: Move helpers

    private func meiPDFId(_ ann: PDFAnnotation) -> UUID? {
        guard let u = ann.userName, u.hasPrefix("MeiPDF:"),
              let id = UUID(uuidString: String(u.dropFirst("MeiPDF:".count))) else { return nil }
        return id
    }

    private func noteMoved(_ ann: PDFAnnotation) -> Bool {
        guard let o = moveOrigBounds else { return false }
        let b = ann.bounds
        return abs(b.origin.x - o.origin.x) > 2 || abs(b.origin.y - o.origin.y) > 2
    }

    private func resetMove() {
        moveAnn = nil; movePage = nil; moveStart = nil
        moveOrigBounds = nil; moveOrigStart = nil; moveOrigEnd = nil
    }
}

// MARK: - Context menu target (retained by the coordinator)

final class ContextMenuTarget: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func trigger() { run() }
}

// MARK: - Coordinator

@MainActor
final class PDFViewCoordinator: NSObject, PDFViewDelegate {
    var doc: DocumentState
    /// Retained targets for the PDF context-menu items so their closures stay alive.
    var contextTargets: [Any] = []
    /// KVO token for the live `currentPage` sync.
    var pageObservation: NSKeyValueObservation?
    /// NotificationCenter observer for `.PDFViewPageChanged` (belt-and-braces — the
    /// delegate method alone was never called because its selector name was wrong).
    var pageNotificationObserver: NSObjectProtocol?
    init(_ doc: DocumentState) { self.doc = doc }

    /// Keep `doc.currentPage` in lock-step with whatever page PDFView is showing.
    private func syncCurrentPage(from view: PDFView) {
        guard let document = view.document, let page = view.currentPage else { return }
        let idx = document.index(for: page)
        if doc.currentPage != idx {
            doc.currentPage = idx
            if doc.preferences.rememberLastPosition { doc.persist() }
        }
    }

    func startObserving(_ view: MeiPDFView) {
        pageObservation = view.observe(\.currentPage, options: [.new]) { [weak self, weak view] _, _ in
            guard let view else { return }
            Task { @MainActor in
                guard let self else { return }
                self.syncCurrentPage(from: view)
            }
        }
        pageNotificationObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged, object: view, queue: .main
        ) { [weak self, weak view] _ in
            guard let view else { return }
            Task { @MainActor in
                guard let self else { return }
                self.syncCurrentPage(from: view)
            }
        }
    }

    /// The real PDFViewDelegate selector for page changes is `pdfViewPageChanged(_:)`.
    /// (An earlier build implemented a non-existent `pdfViewCurrentPageDidChange`,
    /// which silently never fired — one reason the page readout stopped updating.)
    func pdfViewPageChanged(_ sender: PDFView) {
        syncCurrentPage(from: sender)
    }
}

// MARK: - Representable

struct PDFViewWrapper: NSViewRepresentable {
    let doc: DocumentState

    func makeNSView(context: Context) -> MeiPDFView {
        let view = MeiPDFView()
        view.documentState = doc
        view.displayMode = doc.displayMode
        view.displayDirection = doc.displayDirection
        view.backgroundColor = doc.theme.backgroundColor
        view.interpolationQuality = .high
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.document = doc.pdfDocument
        if doc.zoomLocked {
            // Restore the locked zoom factor captured the last time this document's
            // view was on screen (this is what makes per-tab zoom survive tab switches).
            view.autoScales = false
            view.scaleFactor = doc.scaleFactor
        } else {
            // Default-zoom preference is applied once in `updateNSView`, after the
            // view's bounds are known (needed to compute fitWidth / fitHeight).
            view.autoScales = true
        }
        doc.scaleFactor = view.scaleFactor
        if doc.currentPage > 0, let page = doc.pdfDocument.page(at: doc.currentPage) {
            view.go(to: page)
        }
        view.delegate = context.coordinator
        context.coordinator.startObserving(view)
        doc.pdfView = view
        view.menu = buildContextMenu(doc: doc, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: MeiPDFView, context: Context) {
        nsView.documentState = doc
        // Keep the document's view reference pointing at the *live* view. This is what
        // makes toolbar commands (zoom / fit / rotate / search) always act on the
        // currently visible PDF, even right after a tab switch.
        doc.pdfView = nsView
        if nsView.document !== doc.pdfDocument { nsView.document = doc.pdfDocument }
        if nsView.displayMode != doc.displayMode { nsView.displayMode = doc.displayMode }
        if nsView.displayDirection != doc.displayDirection { nsView.displayDirection = doc.displayDirection }
        nsView.backgroundColor = doc.theme.backgroundColor
        // Apply the app's default-zoom preference exactly once, now that the view's
        // bounds are known (required to compute fitWidth / fitHeight / fitPage).
        if !doc.zoomLocked, !doc.defaultZoomApplied,
           doc.preferences.defaultZoom != .none, nsView.bounds.width > 0 {
            doc.applyDefaultZoom(in: nsView)
            doc.defaultZoomApplied = true
        }
        if nsView.autoScales {
            // Auto-scaling owns the factor; mirror it into the model for the % readout.
            doc.scaleFactor = nsView.scaleFactor
        } else {
            if abs(nsView.scaleFactor - doc.scaleFactor) > 0.001 {
                nsView.scaleFactor = doc.scaleFactor
            }
            doc.scaleFactor = nsView.scaleFactor
        }
        context.coordinator.doc = doc
        nsView.menu = buildContextMenu(doc: doc, coordinator: context.coordinator)
    }

    func makeCoordinator() -> PDFViewCoordinator {
        PDFViewCoordinator(doc)
    }

    // MARK: Context menu

    @MainActor
    private func buildContextMenu(doc: DocumentState, coordinator: PDFViewCoordinator) -> NSMenu {
        coordinator.contextTargets.removeAll()
        let menu = NSMenu()

        /// Build a retained-closure menu item and append it to `target`.
        func item(_ title: String, enabled: Bool = true, into target: NSMenu, _ run: @escaping () -> Void) {
            let t = ContextMenuTarget(run)
            coordinator.contextTargets.append(t)
            let mi = NSMenuItem(title: title, action: #selector(ContextMenuTarget.trigger), keyEquivalent: "")
            mi.target = t
            mi.isEnabled = enabled
            target.addItem(mi)
        }
        func shapeItem(_ title: String, _ type: AnnotationType, into target: NSMenu) {
            let t = ContextMenuTarget { MainActor.assumeIsolated { doc.activeTool = type } }
            coordinator.contextTargets.append(t)
            let mi = NSMenuItem(title: title, action: #selector(ContextMenuTarget.trigger), keyEquivalent: "")
            mi.target = t
            if doc.activeTool == type { mi.state = NSControl.StateValue.on }
            target.addItem(mi)
        }

        let hasSelection = doc.pdfView?.currentSelection != nil

        // Unified "标注工具" submenu.
        let ann = NSMenu()
        item("高亮", enabled: hasSelection, into: ann) { MainActor.assumeIsolated { doc.addTextMark(type: .highlight, color: doc.activeColor) } }
        item("下划线", enabled: hasSelection, into: ann) { MainActor.assumeIsolated { doc.addTextMark(type: .underline, color: doc.activeColor) } }
        item("删除线", enabled: hasSelection, into: ann) { MainActor.assumeIsolated { doc.addTextMark(type: .strikeOut, color: doc.activeColor) } }
        item("添加笔记", enabled: hasSelection, into: ann) { MainActor.assumeIsolated { doc.addNote(text: "", color: doc.activeColor) } }
        ann.addItem(.separator())
        shapeItem("矩形", .square, into: ann)
        shapeItem("椭圆", .circle, into: ann)
        shapeItem("直线", .line, into: ann)
        shapeItem("箭头", .arrow, into: ann)
        shapeItem("手绘", .ink, into: ann)
        shapeItem("文本框", .freeText, into: ann)
        shapeItem("签名", .signature, into: ann)
        let annTop = NSMenuItem(title: "标注工具", action: nil, keyEquivalent: "")
        annTop.submenu = ann
        menu.addItem(annTop)

        menu.addItem(.separator())
        item("复制本页为图片", enabled: true, into: menu) { MainActor.assumeIsolated { doc.copyPageImage() } }
        return menu
    }
}
