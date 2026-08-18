import SwiftUI
import PDFKit

/// PDFView subclass that additionally supports drawing shape annotations (square / circle / line)
/// via mouse drag when an annotation tool is active.
final class MeiPDFView: PDFView {
    weak var documentState: DocumentState?

    private var dragStart: CGPoint?
    private var tempPage: PDFPage?
    private var tempAnn: PDFAnnotation?

    private func pagePoint(_ event: NSEvent, page: PDFPage) -> CGPoint {
        let viewPoint = self.convert(event.locationInWindow, from: nil)
        return self.convert(viewPoint, to: page)
    }

    override func mouseDown(with event: NSEvent) {
        let tool = MainActor.assumeIsolated { documentState?.activeTool }
        guard tool != nil, let page = currentPage else {
            super.mouseDown(with: event)
            return
        }
        MainActor.assumeIsolated {
            let ds = self.documentState!
            let p = self.pagePoint(event, page: page)
            self.dragStart = p
            self.tempPage = page
            let subtype: PDFAnnotationSubtype = (tool == .circle) ? .circle : (tool == .line) ? .line : .square
            let ann = PDFAnnotation(bounds: NSRect(x: p.x, y: p.y, width: 1, height: 1), forType: subtype, withProperties: nil)
            ann.color = ds.activeColor
            if subtype == .line { ann.startPoint = p; ann.endPoint = p }
            page.addAnnotation(ann)
            self.tempAnn = ann
        }
    }

    override func mouseDragged(with event: NSEvent) {
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
        if tool == .line { ann.endPoint = p }
        self.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let page = tempPage, let ann = tempAnn, let start = dragStart else {
            super.mouseUp(with: event)
            return
        }
        let tool = MainActor.assumeIsolated { documentState?.activeTool }
        guard tool != nil else {
            super.mouseUp(with: event)
            return
        }
        let p = pagePoint(event, page: page)
        let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                          width: abs(p.x - start.x), height: abs(p.y - start.y))
        page.removeAnnotation(ann)
        if rect.width > 3 && rect.height > 3 {
            let type: AnnotationType = (tool == .circle) ? .circle : (tool == .line) ? .line : .square
            let color = MainActor.assumeIsolated { self.documentState?.activeColor } ?? NSColor.systemYellow
            MainActor.assumeIsolated { self.documentState?.addShape(type: type, rect: rect, color: color) }
            MainActor.assumeIsolated { self.documentState?.activeTool = nil }
        }
        tempAnn = nil; tempPage = nil; dragStart = nil
    }
}

// MARK: - Coordinator

@MainActor
final class PDFViewCoordinator: NSObject, PDFViewDelegate {
    var doc: DocumentState
    init(_ doc: DocumentState) { self.doc = doc }

    func pdfViewCurrentPageDidChange(_ sender: PDFView) {
        guard let page = sender.currentPage, let idx = sender.document?.index(for: page) else { return }
        if doc.currentPage != idx {
            doc.currentPage = idx
            if doc.preferences.rememberLastPosition { doc.persist() }
        }
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
        view.autoScales = true
        doc.scaleFactor = view.scaleFactor
        if doc.currentPage > 0, let page = doc.pdfDocument.page(at: doc.currentPage) {
            view.go(to: page)
        }
        view.delegate = context.coordinator
        doc.pdfView = view
        return view
    }

    func updateNSView(_ nsView: MeiPDFView, context: Context) {
        nsView.documentState = doc
        if nsView.document !== doc.pdfDocument { nsView.document = doc.pdfDocument }
        if nsView.displayMode != doc.displayMode { nsView.displayMode = doc.displayMode }
        if nsView.displayDirection != doc.displayDirection { nsView.displayDirection = doc.displayDirection }
        nsView.backgroundColor = doc.theme.backgroundColor
        if !(nsView.autoScales) {
            if abs(nsView.scaleFactor - doc.scaleFactor) > 0.001 {
                nsView.scaleFactor = doc.scaleFactor
            }
            doc.scaleFactor = nsView.scaleFactor
        }
    }

    func makeCoordinator() -> PDFViewCoordinator {
        PDFViewCoordinator(doc)
    }
}
