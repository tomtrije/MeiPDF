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

/// A note annotation that ALWAYS renders its text: a small icon + the contents in
/// a rounded bubble. PDFKit's plain `.text` note only shows an icon and hides the
/// contents behind a popup (which our custom click handling suppresses), so the
/// filled-in text was invisible. This subclass draws both, with colors that adapt
/// to the current appearance (light/dark).
final class NoteBubbleAnnotation: PDFAnnotation {
    var noteColor: NSColor = .systemYellow

    init(bounds: CGRect, color: NSColor, userName: String) {
        super.init(bounds: bounds, forType: .text, withProperties: nil)
        self.noteColor = color
        self.userName = userName
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        // Do NOT call super — the default text-note rendering draws only the icon.
        let r = bounds
        context.saveGState()
        // Convert to a flipped (Y-down) local space anchored at the bounds' top-left
        // so AppKit bezier + text drawing behaves naturally.
        context.translateBy(x: r.minX, y: r.maxY)
        context.scaleBy(x: 1, y: -1)
        let nsctx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsctx

        let local = CGRect(x: 0, y: 0, width: r.width, height: r.height)
        let text = contents ?? ""

        // Bubble background: adaptive surface tinted with the note colour.
        let base = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        let tinted = base.blended(withFraction: 0.15, of: noteColor.withAlphaComponent(0.35)) ?? base
        tinted.setFill()
        NSBezierPath(roundedRect: local, xRadius: 4, yRadius: 4).fill()
        noteColor.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(roundedRect: local.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()

        // Icon: a small colour chip with two "text lines" at the top-left.
        let icon = CGRect(x: 5, y: 5, width: 12, height: 12)
        noteColor.setFill()
        NSBezierPath(roundedRect: icon, xRadius: 2, yRadius: 2).fill()
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(rect: CGRect(x: icon.minX + 2.5, y: icon.minY + 2.5, width: icon.width - 5, height: 1.5)).fill()
        NSBezierPath(rect: CGRect(x: icon.minX + 2.5, y: icon.minY + 5.5, width: icon.width - 5, height: 1.5)).fill()

        if !text.isEmpty {
            let font = NSFont.systemFont(ofSize: 12)
            let textRect = CGRect(x: icon.maxX + 5, y: 4, width: max(local.width - icon.maxX - 9, 20), height: max(local.height - 8, 20))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let str = NSAttributedString(string: text, attributes: attrs)
            str.draw(with: textRect, options: [.usesLineFragmentOrigin])
        }

        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}

/// Preview-style "添加文本": draws ONLY the text on the page — no border, no
/// background — in the user-chosen annotation colour.
final class PlainTextAnnotation: PDFAnnotation {
    init(bounds: CGRect, color: NSColor, userName: String) {
        super.init(bounds: bounds, forType: .freeText, withProperties: nil)
        self.userName = userName
        self.plainColor = color
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    var plainColor: NSColor = .systemRed

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let r = bounds
        context.saveGState()
        context.translateBy(x: r.minX, y: r.maxY)
        context.scaleBy(x: 1, y: -1)
        let nsctx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsctx

        let text = contents ?? ""
        if !text.isEmpty {
            let font = NSFont.systemFont(ofSize: 14)
            let textRect = CGRect(x: 1, y: 1, width: max(r.width - 2, 10), height: max(r.height - 2, 10))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: plainColor]
            let str = NSAttributedString(string: text, attributes: attrs)
            str.draw(with: textRect, options: [.usesLineFragmentOrigin])
        }

        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}

/// NSTextView used for in-place annotation editing. Optionally commits on Return
/// (文本框 / 添加文本) or inserts a newline (笔记 — committed on losing focus).
final class InlineTextView: NSTextView {
    var commitOnReturn = false
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func insertNewline(_ sender: Any?) {
        if commitOnReturn {
            onCommit?()
        } else {
            super.insertNewline(sender)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape — discard the edit
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

/// Hosts an `InlineTextView` on the PDF's documentView so editing happens right at
/// the annotation's position and tracks scrolling / zoom for free. The host is
/// styled to stand in for the annotation itself: notes get the bubble look, text
/// annotations are transparent — so editing feels like editing the annotation,
/// not a separate box. Commits on focus loss (like Preview) and on Return for
/// single-line types.
final class InlineEditorHost: NSView, NSTextViewDelegate {
    let textView = InlineTextView()
    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var finished = false

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 3, height: 3)
        textView.delegate = self
        addSubview(textView)
        textView.autoresizingMask = [.width, .height]
        textView.frame = bounds
    }

    func textDidEndEditing(_ notification: Notification) {
        finish(commit: true)
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if commit { onSave?(textView.string) } else { onCancel?() }
    }

    /// `bubble` styles the host like a note bubble (tinted rounded rect + accent
    /// border); otherwise it is fully transparent so text is edited in place.
    func beginEditing(text: String, font: NSFont, textColor: NSColor,
                      commitOnReturn: Bool, bubble: Bool, accent: NSColor) {
        finished = false
        textView.string = text
        textView.font = font
        textView.textColor = textColor
        textView.commitOnReturn = commitOnReturn
        textView.onCommit = { [weak self] in self?.finish(commit: true) }
        textView.onCancel = { [weak self] in self?.finish(commit: false) }
        if bubble {
            // Opaque so it fully covers the note bubble underneath while editing.
            let base = NSColor.windowBackgroundColor
            layer?.backgroundColor = (base.blended(withFraction: 0.15, of: accent.withAlphaComponent(0.35)) ?? base).cgColor
            layer?.cornerRadius = 4
            layer?.borderWidth = 1
            layer?.borderColor = accent.withAlphaComponent(0.45).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = 0
            layer?.borderWidth = 0
        }
        window?.makeFirstResponder(textView)
    }
}

/// The eight resize handles of a selected annotation (corners + edge midpoints).
fileprivate enum Handle: Int { case nw, n, ne, e, se, s, sw, w }

/// PDFView subclass that additionally supports:
///  - drawing shape / line annotations via mouse drag when an annotation tool is active;
///  - selecting / moving / resizing existing own annotations (when no tool is active);
///  - double-clicking a free-text / note to open its inline text editor.
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

    // Annotation-resize drag state.
    private var resizeAnn: PDFAnnotation?
    private var resizePage: PDFPage?
    private var resizeHandle: Handle?
    private var resizeOrigBounds: CGRect?
    private var resizeOrigStart: CGPoint?
    private var resizeOrigEnd: CGPoint?

    /// Transparent overlay (a subview of `documentView`) that draws the selection
    /// rectangle and resize handles for the currently selected annotation.
    weak var selectionOverlay: SelectionOverlay?
    /// Tracks zoom changes so the overlay re-draws handle sizes / positions.
    var scaleObserver: NSKeyValueObservation?

    private func pagePoint(_ event: NSEvent, page: PDFPage) -> CGPoint {
        let viewPoint = self.convert(event.locationInWindow, from: nil)
        return self.convert(viewPoint, to: page)
    }

    /// Topmost *own* annotation (tagged `MeiPDF:<uuid>`) under the event — used for
    /// selection / move / resize. Text marks are skipped (they must not hijack
    /// text selection or dragging). Robust against PDFKit quirks: ours are matched
    /// by `userName` first (never skipped when `type` is nil), and if the live
    /// `bounds` is unreliable after a reopen the authoritative model bounds act as
    /// a fallback.
    private func ourAnnotationUnder(_ event: NSEvent) -> (PDFPage, PDFAnnotation)? {
        guard let page = currentPage, let ds = documentState else { return nil }
        let p = pagePoint(event, page: page)
        // 1) Live annotations (fast path).
        for ann in page.annotations.reversed() {
            guard ann.userName?.hasPrefix("MeiPDF:") == true else { continue }
            if let t = ann.type, t == "Highlight" || t == "Underline" || t == "StrikeOut" { continue }
            if ann.bounds.contains(p) { return (page, ann) }
        }
        // 2) Fallback: authoritative model bounds (reopen can leave a live
        //    annotation's bounds off for some subtypes, e.g. free text).
        let idx = ds.pdfDocument.index(for: page)
        for a in ds.annotations where a.pageIndex == idx {
            let b = CGRect(x: a.bounds.x, y: a.bounds.y, width: a.bounds.w, height: a.bounds.h)
            if b.contains(p),
               let live = page.annotations.first(where: { $0.userName == "MeiPDF:" + a.id.uuidString }) {
                return (page, live)
            }
        }
        return nil
    }

    /// Find the own annotation with the given stable id on `page`.
    private func ourAnnotation(id: UUID, at page: PDFPage) -> (PDFPage, PDFAnnotation)? {
        let key = "MeiPDF:" + id.uuidString
        for ann in page.annotations where ann.userName == key {
            return (page, ann)
        }
        return nil
    }

    /// Whether an annotation can be resized via handles (text marks and ink are not).
    private func canResize(_ ann: PDFAnnotation) -> Bool {
        guard let t = ann.type else { return false }
        return t != "Highlight" && t != "Underline" && t != "StrikeOut" && t != "Ink"
    }

    /// The 8 handle centres (nw, n, ne, e, se, s, sw, w) in the view's coordinate
    /// space, derived from the annotation's page bounds.
    private func handleCenters(for ann: PDFAnnotation, page: PDFPage) -> [CGPoint] {
        let b = ann.bounds
        let pagePts = [
            CGPoint(x: b.minX, y: b.maxY), // nw
            CGPoint(x: b.midX, y: b.maxY), // n
            CGPoint(x: b.maxX, y: b.maxY), // ne
            CGPoint(x: b.maxX, y: b.midY), // e
            CGPoint(x: b.maxX, y: b.minY), // se
            CGPoint(x: b.midX, y: b.minY), // s
            CGPoint(x: b.minX, y: b.minY), // sw
            CGPoint(x: b.minX, y: b.midY)  // w
        ]
        return pagePts.map { convert($0, from: page) }
    }

    /// Which handle (if any) is under the cursor — `eventView` and the handle
    /// centres are both in the view's coordinate space.
    private func handleAt(_ eventView: CGPoint, for ann: PDFAnnotation, page: PDFPage) -> Handle? {
        let centers = handleCenters(for: ann, page: page)
        let hs: CGFloat = 7
        for (i, c) in centers.enumerated() {
            if abs(c.x - eventView.x) <= hs, abs(c.y - eventView.y) <= hs {
                return Handle(rawValue: i)
            }
        }
        return nil
    }

    private func startResize(ann: PDFAnnotation, page: PDFPage, handle: Handle) {
        resizeAnn = ann; resizePage = page; resizeHandle = handle
        resizeOrigBounds = ann.bounds
        resizeOrigStart = ann.startPoint
        resizeOrigEnd = ann.endPoint
    }

    override func mouseDown(with event: NSEvent) {
        // Let right-clicks fall through to the system so the context menu shows.
        guard event.buttonNumber == 0 else { super.mouseDown(with: event); return }

        let tool = MainActor.assumeIsolated { documentState?.activeTool }
        if let tool, let page = currentPage {
            MainActor.assumeIsolated {
                let ds = self.documentState!
                let p = self.pagePoint(event, page: page)
                // Text box / 添加文本: click to drop an editable annotation, then open
                // the inline text editor so the user can type immediately.
                if tool == .freeText || tool == .plainText {
                    let w: CGFloat = 150, h: CGFloat = 30
                    let b = CGRect(x: p.x, y: p.y - h, width: w, height: h)
                    let idx = ds.pdfDocument.index(for: page)
                    let ann = tool == .plainText
                        ? ds.addPlainText(bounds: b, color: ds.activeColor, pageIndex: idx)
                        : ds.addFreeText(bounds: b, color: ds.activeColor, pageIndex: idx)
                    ds.activeTool = nil
                    ds.selectedAnnotationID = ann.id
                    ds.editingFreeText = NoteEditTarget(id: ann.id, pageIndex: idx)
                    self.syncInlineEditor()
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
            // Note: drop a note icon at the click point and open its text editor
            // immediately (the toolbar "笔记" tool does not need a text selection).
            if tool == .note {
                let idx = ds.pdfDocument.index(for: page)
                let ann = ds.addNote(at: p, pageIndex: idx, color: ds.activeColor)
                ds.activeTool = nil
                ds.selectedAnnotationID = ann.id
                ds.editingNote = NoteEditTarget(id: ann.id, pageIndex: idx)
                self.syncInlineEditor()
                return
            }
            self.dragStart = p
            self.tempPage = page
                let subtype: PDFAnnotationSubtype = (tool == .circle) ? .circle : (tool == .line || tool == .arrow || tool == .squiggle) ? .line : .square
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

        // No tool active: selection / move / resize / inline edit.
        guard let page = currentPage else { super.mouseDown(with: event); return }
        let p = pagePoint(event, page: page)
        let eventView = convert(event.locationInWindow, from: nil)

        // 1) Resize if a handle of the currently selected annotation is hit.
        if let sel = MainActor.assumeIsolated({ documentState?.selectedAnnotationID }),
           let (rpage, rann) = ourAnnotation(id: sel, at: page),
           canResize(rann),
           let handle = handleAt(eventView, for: rann, page: rpage) {
            startResize(ann: rann, page: rpage, handle: handle)
            return
        }

        // 2) Double-click a note / text box / pure text → open its in-place editor.
        if event.clickCount == 2 {
            if let (dpage, dann) = ourAnnotationUnder(event),
               let id = meiPDFId(dann) {
                let idx = self.document?.index(for: dpage) ?? 0
                MainActor.assumeIsolated {
                    // Decide by the authoritative model type (robust after a reopen,
                    // where the live annotation's `type` string may be unreliable).
                    if let model = self.documentState?.annotations.first(where: { $0.id == id }) {
                        switch model.type {
                        case .note:
                            self.documentState?.editingNote = NoteEditTarget(id: id, pageIndex: idx)
                        case .freeText, .plainText:
                            self.documentState?.editingFreeText = NoteEditTarget(id: id, pageIndex: idx)
                        default:
                            break
                        }
                    } else if dann.type == "Text" {
                        self.documentState?.editingNote = NoteEditTarget(id: id, pageIndex: idx)
                    } else if dann.type == "FreeText" {
                        self.documentState?.editingFreeText = NoteEditTarget(id: id, pageIndex: idx)
                    }
                }
                // Show the editor immediately (do not wait for a SwiftUI re-render).
                self.syncInlineEditor()
                return
            }
        }

        // 3) Single click on one of our annotations → select + begin move.
        if let (dpage, dann) = ourAnnotationUnder(event) {
            MainActor.assumeIsolated { documentState?.selectedAnnotationID = meiPDFId(dann) }
            selectionOverlay?.setNeedsDisplay(selectionOverlay?.bounds ?? bounds)
            moveAnn = dann
            movePage = dpage
            moveStart = p
            moveOrigBounds = dann.bounds
            moveOrigStart = dann.startPoint
            moveOrigEnd = dann.endPoint
            return
        }

        // 4) Empty area → deselect and let PDFView handle the click.
        MainActor.assumeIsolated { documentState?.selectedAnnotationID = nil }
        selectionOverlay?.setNeedsDisplay(selectionOverlay?.bounds ?? bounds)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        // Resize an annotation by dragging one of its handles.
        if let handle = resizeHandle, let ann = resizeAnn, let page = resizePage, let orig = resizeOrigBounds {
            let p = pagePoint(event, page: page)
            var b = orig
            switch handle {
            case .nw: b.origin.x = p.x; b.origin.y = p.y; b.size.width = orig.maxX - p.x; b.size.height = p.y - orig.minY
            case .n:  b.origin.y = p.y; b.size.height = p.y - orig.minY
            case .ne: b.size.width = p.x - orig.minX; b.origin.y = p.y; b.size.height = p.y - orig.minY
            case .e:  b.size.width = p.x - orig.minX
            case .se: b.size.width = p.x - orig.minX; b.size.height = orig.maxY - p.y
            case .s:  b.size.height = orig.maxY - p.y
            case .sw: b.origin.x = p.x; b.size.width = orig.maxX - p.x; b.size.height = orig.maxY - p.y
            case .w:  b.origin.x = p.x; b.size.width = orig.maxX - p.x
            }
            let minS: CGFloat = 10
            if b.width < minS { b.size.width = minS }
            if b.height < minS { b.size.height = minS }
            ann.bounds = b
            if ann.type == "Line" {
                if let s = resizeOrigStart, let e = resizeOrigEnd {
                    ann.startPoint = CGPoint(x: s.x - b.minX, y: s.y - b.minY)
                    ann.endPoint = CGPoint(x: e.x - b.minX, y: e.y - b.minY)
                }
            }
            self.needsDisplay = true
            selectionOverlay?.setNeedsDisplay(selectionOverlay?.bounds ?? self.bounds)
            return
        }

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
            // Custom move for all our annotations (shapes / lines / notes / text /
            // ink / signature). Reliable, persists to our model on mouseUp.
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
            // Keep the selection box + handles glued to the annotation while it
            // moves (the overlay redraws from the live bounds each frame).
            selectionOverlay?.setNeedsDisplay(selectionOverlay?.bounds ?? self.bounds)
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
        if tool == .line || tool == .arrow || tool == .squiggle {
            // Keep endpoints relative to the (changing) bounds so the live preview
            // tracks the cursor correctly, matching how `makePDFAnnotation` rebuilds
            // the final annotation from its stored absolute points.
            ann.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            ann.endPoint = CGPoint(x: p.x - rect.minX, y: p.y - rect.minY)
        }
        self.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // Commit a resize (handles) before the move path.
        if let handle = resizeHandle, let ann = resizeAnn, let page = resizePage {
            _ = handle; _ = page
            if let id = meiPDFId(ann) {
                MainActor.assumeIsolated {
                    self.documentState?.updateAnnotation(id: id, bounds: ann.bounds,
                        start: ann.type == "Line" ? ann.startPoint : nil,
                        end: ann.type == "Line" ? ann.endPoint : nil)
                }
            }
            resizeHandle = nil; resizeAnn = nil; resizePage = nil; resizeOrigBounds = nil
            selectionOverlay?.setNeedsDisplay(selectionOverlay?.bounds ?? bounds)
            return
        }

        if let ann = moveAnn, let _ = movePage {
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
        if tool == .line || tool == .arrow || tool == .squiggle {
            let len = hypot(p.x - start.x, p.y - start.y)
            if len > 3 {
                let color = MainActor.assumeIsolated { self.documentState?.activeColor } ?? NSColor.systemYellow
                MainActor.assumeIsolated {
                    if tool == .arrow {
                        self.documentState?.addArrow(start: start, end: p, color: color, pageIndex: pageIndex)
                    } else if tool == .squiggle {
                        self.documentState?.addSquiggle(start: start, end: p, color: color, pageIndex: pageIndex)
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

    private func resetMove() {
        moveAnn = nil; movePage = nil; moveStart = nil
        moveOrigBounds = nil; moveOrigStart = nil; moveOrigEnd = nil
    }

    // MARK: Keyboard

    /// Backspace / Delete removes the currently selected annotation (mirrors
    /// Preview's behaviour). Ignored when nothing is selected or when a text field
    /// (e.g. the search box) is the first responder.
    override func keyDown(with event: NSEvent) {
        if let ds = documentState, ds.selectedAnnotationID != nil,
           event.keyCode == 51 || event.keyCode == 117 {
            ds.deleteSelectedAnnotation()
            selectionOverlay?.setNeedsDisplay(selectionOverlay?.bounds ?? bounds)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Inline text editing (no popover)

    private var inlineEditor: InlineEditorHost?
    private var activeEditID: UUID?
    /// The annotation currently being edited. It is hidden (`shouldDisplay = false`)
    /// while editing so the editor's text never overlaps the original, and is
    /// restored **directly in the same event** (onSave / onCancel / hideInlineEditor)
    /// — never through the unreliable observation → re-render chain (the 1.0.20
    /// disappearing regression). `syncInlineEditor` also self-heals at its start.
    private weak var editingAnnotation: PDFAnnotation?

    /// Show / move / hide the in-place editor based on `editingNote`/`editingFreeText`.
    /// Called from the mouse handlers (immediately) and from `updateNSView` (deferred
    /// off the display cycle, as a safety net). The editor is a subview of
    /// `documentView`, so it tracks scrolling and zoom automatically.
    func syncInlineEditor() {
        guard let ds = documentState else { hideInlineEditor(); return }
        guard let target = ds.editingNote ?? ds.editingFreeText else {
            // No editing target: restore any hidden annotation and close the editor.
            hideInlineEditor()
            return
        }

        // Only re-seed the text when we are not already editing this annotation
        // (otherwise every SwiftUI re-render would clobber what the user typed).
        if let ed = inlineEditor, activeEditID == target.id {
            repositionEditor(ed, pageIndex: target.pageIndex, id: target.id)
            return
        }

        // Switching to a (possibly different) annotation: restore anything left
        // hidden by the previous edit session before hiding the new target.
        if let prev = editingAnnotation {
            prev.shouldDisplay = ds.showAnnotations
            editingAnnotation = nil
        }

        guard let page = ds.pdfDocument.page(at: target.pageIndex),
              let ann = page.annotations.first(where: { $0.userName == "MeiPDF:" + target.id.uuidString }),
              let dv = documentView else { hideInlineEditor(); return }

        let model = ds.annotations.first(where: { $0.id == target.id })
        let isNote = model?.type == .note
        let isPlain = model?.type == .plainText
        let font = NSFont.systemFont(ofSize: isNote ? 12 : (isPlain ? 14 : max(11, (model?.lineWidth ?? 2) * 6)))
        let textColor: NSColor = isNote ? .labelColor : (model?.color.nsColor ?? .labelColor)
        let accent = model?.color.nsColor ?? .systemYellow

        // Hide the original while editing so the editor's text never overlaps it.
        ann.shouldDisplay = false
        editingAnnotation = ann

        let ed: InlineEditorHost
        if let existing = inlineEditor {
            ed = existing
        } else {
            ed = InlineEditorHost(frame: .zero)
            ed.onSave = { [weak self, weak ds] text in
                guard let ds else { return }
                ds.updateAnnotationContents(id: target.id, contents: text)
                ds.editingNote = nil
                ds.editingFreeText = nil
                // Restore + close the editor directly, in this same event.
                self?.hideInlineEditor()
                self?.selectionOverlay?.setNeedsDisplay(self?.selectionOverlay?.bounds ?? .zero)
            }
            ed.onCancel = { [weak self, weak ds] in
                ds?.editingNote = nil
                ds?.editingFreeText = nil
                self?.hideInlineEditor()
            }
            inlineEditor = ed
            dv.addSubview(ed)
        }
        activeEditID = target.id
        ed.beginEditing(text: ann.contents ?? "", font: font, textColor: textColor,
                        commitOnReturn: !isNote, bubble: isNote, accent: accent)
        repositionEditor(ed, pageIndex: target.pageIndex, id: target.id)
    }

    private func repositionEditor(_ ed: InlineEditorHost, pageIndex: Int, id: UUID) {
        guard let ds = documentState, let page = ds.pdfDocument.page(at: pageIndex),
              let ann = page.annotations.first(where: { $0.userName == "MeiPDF:" + id.uuidString }),
              let dv = documentView else { return }
        let rb = ann.bounds
        let tl = dv.convert(convert(CGPoint(x: rb.minX, y: rb.maxY), from: page), from: self)
        let br = dv.convert(convert(CGPoint(x: rb.maxX, y: rb.minY), from: page), from: self)
        // Tight to the annotation (small min so empty notes are still usable).
        let w = max(abs(br.x - tl.x), 120)
        let h = max(abs(br.y - tl.y), 32)
        let x = min(tl.x, br.x)
        let y = min(tl.y, br.y)
        ed.frame = CGRect(x: x, y: y, width: w, height: h)
    }

    private func hideInlineEditor() {
        // Bring the hidden annotation back (it was hidden while editing).
        if let ann = editingAnnotation, let ds = documentState {
            ann.shouldDisplay = ds.showAnnotations
        }
        editingAnnotation = nil
        activeEditID = nil
        inlineEditor?.removeFromSuperview()
        inlineEditor = nil
    }
}

// MARK: - Context menu target (retained by the coordinator)

final class ContextMenuTarget: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func trigger() { run() }
}

/// Transparent overlay (a subview of the PDFView's `documentView`) that draws the
/// selection rectangle and 8 resize handles for the currently selected annotation.
/// Because it lives inside the scrolled document view, it tracks page scrolling for
/// free; zoom changes trigger a re-draw via the KVO set up in `attachSelectionOverlay`.
final class SelectionOverlay: NSView {
    weak var documentState: DocumentState?

    /// Never capture mouse events — all hit-testing / dragging is handled by
    /// `MeiPDFView` itself, so the overlay stays purely visual.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ds = documentState, let id = ds.selectedAnnotationID,
              let view = ds.pdfView, let page = view.currentPage,
              let dv = view.documentView else { return }
        let key = "MeiPDF:" + id.uuidString
        guard let ann = page.annotations.first(where: { $0.userName == key }) else { return }
        let b = ann.bounds
        let pagePts = [
            CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.midX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY),
            CGPoint(x: b.maxX, y: b.midY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.midX, y: b.minY),
            CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.minX, y: b.midY)
        ]
        // Page → view → documentView coordinate space (screen-aligned, zoom-correct).
        let pts = pagePts.map { dp in
            let vp = view.convert(dp, from: page)
            return dv.convert(vp, from: view)
        }
        let outer = [pts[0], pts[2], pts[4], pts[6]]
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath()
        path.move(to: outer[0]); path.line(to: outer[1]); path.line(to: outer[2]); path.line(to: outer[3]); path.close()
        path.lineWidth = 1.5
        path.stroke()
        for c in pts {
            let r = NSRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
            let hp = NSBezierPath(rect: r)
            NSColor.white.setFill(); hp.fill()
            NSColor.systemBlue.setStroke(); hp.lineWidth = 1.5; hp.stroke()
        }
    }
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
        if doc.currentPage > 0, let page = doc.pdfDocument.page(at: doc.currentPage) {
            view.go(to: page)
        }
        // Mirror the initial scale into the model off the display cycle (see the
        // updateNSView comment — @Observable writes here can crash AppKit).
        let d = doc
        DispatchQueue.main.async { d.scaleFactor = view.scaleFactor }
        view.delegate = context.coordinator
        context.coordinator.startObserving(view)
        doc.pdfView = view
        attachSelectionOverlay(view, doc: doc)
        view.menu = buildContextMenu(doc: doc, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: MeiPDFView, context: Context) {
        nsView.documentState = doc
        // Keep the document's view reference pointing at the *live* view. This is what
        // makes toolbar commands (zoom / fit / rotate / search) always act on the
        // currently visible PDF, even right after a tab switch.
        doc.pdfView = nsView
        attachSelectionOverlay(nsView, doc: doc)
        if nsView.document !== doc.pdfDocument { nsView.document = doc.pdfDocument }
        if nsView.displayMode != doc.displayMode { nsView.displayMode = doc.displayMode }
        if nsView.displayDirection != doc.displayDirection { nsView.displayDirection = doc.displayDirection }
        nsView.backgroundColor = doc.theme.backgroundColor
        context.coordinator.doc = doc
        nsView.menu = buildContextMenu(doc: doc, coordinator: context.coordinator)
        // Defer every *observable-model* write (default-zoom apply + scaleFactor
        // mirror) out of the SwiftUI display cycle: mutating @Observable state here
        // triggers a re-entrant SwiftUI transaction → `NSHostingView.beginTransaction
        // → setNeedsUpdateConstraints`, and AppKit raises during the window's layout
        // pass (crash seen in 1.0.14). The view-level work above is untouched.
        let d = doc
        DispatchQueue.main.async {
            nsView.syncInlineEditor()
            // Apply the app's default-zoom preference exactly once, now that the view's
            // bounds are known (required to compute fitWidth / fitHeight / fitPage).
            if !d.zoomLocked, !d.defaultZoomApplied,
               d.preferences.defaultZoom != .none, nsView.bounds.width > 0 {
                d.applyDefaultZoom(in: nsView)
                d.defaultZoomApplied = true
            }
            if nsView.autoScales {
                // Auto-scaling owns the factor; mirror it into the model for the % readout.
                d.scaleFactor = nsView.scaleFactor
            } else {
                if abs(nsView.scaleFactor - d.scaleFactor) > 0.001 {
                    nsView.scaleFactor = d.scaleFactor
                }
                d.scaleFactor = nsView.scaleFactor
            }
        }
    }

    func makeCoordinator() -> PDFViewCoordinator {
        PDFViewCoordinator(doc)
    }

    // MARK: Selection overlay + context-menu helpers

    /// Attach the selection-handle overlay to the PDFView's scrolling document view
    /// (once). The overlay redraws on zoom changes via a KVO on `scaleFactor`.
    private func attachSelectionOverlay(_ view: MeiPDFView, doc: DocumentState) {
        guard view.selectionOverlay == nil else { return }
        guard let dv = view.documentView else { return }
        let ov = SelectionOverlay()
        ov.documentState = doc
        ov.autoresizingMask = [.width, .height]
        ov.frame = dv.bounds
        ov.wantsLayer = true
        dv.addSubview(ov)
        view.selectionOverlay = ov
        view.scaleObserver = view.observe(\.scaleFactor, options: [.new]) { [weak view] _, _ in
            guard let v = view else { return }
            Task { @MainActor in
                v.selectionOverlay?.setNeedsDisplay(v.selectionOverlay?.bounds ?? .zero)
            }
        }
    }

    /// The annotation (ours or foreign) under the right-click location, if any.
    @MainActor
    private func annotationUnderCursor(doc: DocumentState) -> (page: PDFPage, ann: PDFAnnotation)? {
        guard let ev = NSApp.currentEvent, let view = doc.pdfView, let page = view.currentPage else { return nil }
        let vp = view.convert(ev.locationInWindow, from: nil)
        let p = view.convert(vp, to: page)
        for ann in page.annotations.reversed() {
            guard let t = ann.type else { continue }
            if t == "Highlight" || t == "Underline" || t == "StrikeOut" { continue }
            if ann.bounds.contains(p) { return (page, ann) }
        }
        return nil
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
        shapeItem("波浪线", .squiggle, into: ann)
        shapeItem("手绘", .ink, into: ann)
        shapeItem("文本框", .freeText, into: ann)
        shapeItem("添加文本", .plainText, into: ann)
        shapeItem("签名", .signature, into: ann)
        let annTop = NSMenuItem(title: "标注工具", action: nil, keyEquivalent: "")
        annTop.submenu = ann
        menu.addItem(annTop)

        menu.addItem(.separator())
        item("复制本页为图片", enabled: true, into: menu) { MainActor.assumeIsolated { doc.copyPageImage() } }

        // Delete the annotation under the cursor (ours or foreign/Preview-authored).
        if let found = annotationUnderCursor(doc: doc) {
            let isOurs = found.ann.userName?.hasPrefix("MeiPDF:") == true
            menu.addItem(.separator())
            item("删除标注", into: menu) {
                if isOurs,
                   let id = UUID(uuidString: String((found.ann.userName ?? "").dropFirst("MeiPDF:".count))) {
                    doc.removeAnnotation(id: id)
                } else {
                    let idx = doc.pdfDocument.index(for: found.page)
                    doc.removeNativeAnnotation(pageIndex: idx, annotation: found.ann)
                }
                doc.selectedAnnotationID = nil
            }
        }
        return menu
    }
}
