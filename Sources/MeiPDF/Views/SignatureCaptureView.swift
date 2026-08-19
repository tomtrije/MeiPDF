import SwiftUI
import AppKit

/// Mouse-drawing surface for capturing a handwritten signature. Stores strokes in
/// view coordinates (origin bottom-left, Y up) so the snapshot image lines up with
/// how `ImageStampAnnotation` later draws it onto the page.
final class SignatureDrawView: NSView {
    private var strokes: [[CGPoint]] = []
    private var current: [CGPoint] = []
    var onUpdate: (() -> Void)?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        for s in strokes { appendStroke(s, to: path) }
        appendStroke(current, to: path)
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func appendStroke(_ stroke: [CGPoint], to path: NSBezierPath) {
        guard let first = stroke.first else { return }
        path.move(to: first)
        for p in stroke.dropFirst() { path.line(to: p) }
    }

    override func mouseDown(with event: NSEvent) {
        current = [convert(event.locationInWindow, from: nil)]
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        current.append(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if !current.isEmpty { strokes.append(current) }
        current = []
        needsDisplay = true
        onUpdate?()
    }

    func clear() { strokes = []; current = []; needsDisplay = true }
    func hasInk() -> Bool { !strokes.isEmpty }

    /// Render the current strokes to a transparent-background PNG-ready NSImage.
    func snapshot() -> NSImage? {
        guard hasInk() else { return nil }
        let img = NSImage(size: bounds.size)
        img.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath()
        for s in strokes { appendStroke(s, to: path) }
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        img.unlockFocus()
        return img
    }
}

struct SignaturePad: NSViewRepresentable {
    @Binding var image: NSImage?

    func makeNSView(context: Context) -> SignatureDrawView {
        let v = SignatureDrawView()
        context.coordinator.view = v
        v.onUpdate = { context.coordinator.update() }
        return v
    }
    func updateNSView(_ nsView: SignatureDrawView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(image: $image) }

    final class Coordinator {
        var image: Binding<NSImage?>
        weak var view: SignatureDrawView?
        init(image: Binding<NSImage?>) { self.image = image }
        @MainActor func update() { image.wrappedValue = view?.snapshot() }
    }
}

/// Sheet that lets the user draw a signature, then arms the 签名 tool so a click on
/// the page stamps it (non-destructive, stored as a stamp annotation).
struct SignatureCaptureView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var padID = 0

    var body: some View {
        VStack(spacing: 14) {
            Text("签名").font(.headline)
            Text("在下方区域用鼠标书写，点击「使用」后，在页面点击即可盖章。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            SignaturePad(image: $image)
                .id(padID)
                .frame(width: 420, height: 180)
                .background(Color(NSColor.textBackgroundColor))
                .border(Color.gray.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("清除") { image = nil; padID += 1 }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("使用") { use() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func use() {
        guard let img = image else { return }
        if let d = appState.selectedDocument(id: appState.selectedID) {
            d.pendingSignature = img
            d.activeTool = .signature
        }
        dismiss()
    }
}
