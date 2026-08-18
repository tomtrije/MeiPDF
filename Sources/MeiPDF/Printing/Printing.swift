import Foundation
import PDFKit
import SwiftUI
import CoreImage

/// Parses a page-range string like "all", "1,3,5-9" into zero-based page indexes.
func pageIndexes(from range: String, total: Int) -> [Int] {
    let trimmed = range.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty, trimmed != "all" else { return Array(0..<total) }
    var result: [Int] = []
    for part in trimmed.split(separator: ",") {
        let p = part.trimmingCharacters(in: .whitespaces)
        if p.contains("-") {
            let nums = p.split(separator: "-").compactMap { Int($0) }
            if nums.count == 2 {
                let lo = max(1, nums[0]), hi = min(total, nums[1])
                if lo <= hi { result.append(contentsOf: lo...hi) }
            }
        } else if let n = Int(p), n >= 1, n <= total {
            result.append(n)
        }
    }
    return result.map { $0 - 1 }.sorted()
}

/// Renders a PDF page to an image at the requested pixel size, applying color-mode filters.
func renderPageImage(_ page: PDFPage, pixelSize: NSSize, colorMode: ColorMode) -> NSImage? {
    guard let cgPage = page.pageRef else { return nil }
    let scale = max(pixelSize.width, pixelSize.height) /
        max(page.bounds(for: .mediaBox).width, page.bounds(for: .mediaBox).height)
    let w = Int(page.bounds(for: .mediaBox).width * scale)
    let h = Int(page.bounds(for: .mediaBox).height * scale)
    guard w > 0, h > 0 else { return nil }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.drawPDFPage(cgPage)
    guard let cgImage = ctx.makeImage() else { return nil }
    var output: CGImage = cgImage
    if colorMode != .color {
        let ci = CIImage(cgImage: cgImage)
        let f: CIFilter
        if colorMode == .grayscale {
            f = CIFilter(name: "CIColorControls")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(0.0, forKey: kCIInputSaturationKey)
        } else {
            f = CIFilter(name: "CIPhotoEffectNoir")!
            f.setValue(ci, forKey: kCIInputImageKey)
        }
        if let out = f.outputImage,
           let cg = CIContext(options: nil).createCGImage(out, from: out.extent) {
            output = cg
        }
    }
    return NSImage(cgImage: output, size: NSSize(width: w, height: h))
}

final class PDFPrintView: NSView {
    let document: PDFDocument
    let settings: PrintSettings
    let pages: [Int]
    let effectivePaper: CGSize
    let nUp: Int
    let dpi: CGFloat = 150

    init(document: PDFDocument, settings: PrintSettings) {
        self.document = document
        self.settings = settings
        self.pages = pageIndexes(from: settings.pageRange, total: document.pageCount)
        let base = settings.paperSize.points
        self.effectivePaper = (settings.orientation == .landscape)
            ? CGSize(width: base.height, height: base.width) : base
        self.nUp = max(1, settings.nUp)
        super.init(frame: NSRect(origin: .zero, size: effectivePaper))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var grid: (cols: Int, rows: Int) {
        switch nUp {
        case 1: return (1, 1)
        case 2: return (2, 1)
        case 4: return (2, 2)
        case 6: return (3, 2)
        case 9: return (3, 3)
        case 16: return (4, 4)
        default: return (1, 1)
        }
    }

    private var sheetCount: Int {
        max(1, Int(ceil(Double(pages.count) / Double(nUp))))
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: sheetCount)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(origin: .zero, size: effectivePaper)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let marginPts = CGFloat(settings.margins) * 2.834645
        let bindingPts = CGFloat(settings.binding) * 2.834645
        var content = bounds.insetBy(dx: marginPts + bindingPts, dy: marginPts)
        content.origin.x += bindingPts

        let (cols, rows) = grid
        let cellW = content.width / CGFloat(cols)
        let cellH = content.height / CGFloat(rows)

        let scaleFactor: CGFloat = {
            switch settings.scaleMode {
            case .fit: return 1.0
            case .actual: return 1.0
            case .percent: return CGFloat(settings.scalePercent) / 100.0
            }
        }()
        // For "actual", pages are drawn at 1:1 PDF points; for "fit" the page is scaled to fill the cell.
        let fit = (settings.scaleMode == .fit)

        let sheetIndex = max(0, (NSPrintOperation.current?.currentPage ?? 1) - 1)
        for i in 0..<nUp {
            let pagePos = sheetIndex * nUp + i
            guard pagePos < pages.count else { break }
            let pageIndex = pages[pagePos]
            guard let page = document.page(at: pageIndex) else { continue }
            let col = i % cols
            let row = i / cols
            let cell = NSRect(x: content.origin.x + CGFloat(col) * cellW,
                              y: content.origin.y + CGFloat(row) * cellH,
                              width: cellW, height: cellH).insetBy(dx: 4, dy: 4)

            if let img = renderPageImage(page, pixelSize: NSSize(width: cell.width * dpi / 72, height: cell.height * dpi / 72), colorMode: settings.colorMode) {
                let aspect = img.size.width / img.size.height
                let boxAspect = cell.width / cell.height
                var draw = cell
                if fit {
                    if aspect > boxAspect {
                        let h = cell.width / aspect; draw = NSRect(x: cell.minX, y: cell.midY - h/2, width: cell.width, height: h)
                    } else {
                        let w = cell.height * aspect; draw = NSRect(x: cell.midX - w/2, y: cell.minY, width: w, height: cell.height)
                    }
                } else {
                    // actual size (1 PDF point = 1/72 inch); scale to points
                    let w = img.size.width / dpi * 72 * scaleFactor
                    let h = img.size.height / dpi * 72 * scaleFactor
                    draw = NSRect(x: cell.midX - w/2, y: cell.midY - h/2, width: w, height: h)
                }
                img.draw(in: draw)
            }
        }

        // Page numbering / header / footer
        if settings.pageNumbering || !settings.headerText.isEmpty || !settings.footerText.isEmpty {
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9),
                                                        .foregroundColor: NSColor.black,
                                                        .paragraphStyle: para]
            if !settings.headerText.isEmpty {
                let s = settings.headerText as NSString
                s.draw(at: NSPoint(x: content.midX - 200, y: 6), withAttributes: attrs)
            }
            if settings.pageNumbering {
                let s = "第 \(sheetIndex + 1) 页" as NSString
                s.draw(at: NSPoint(x: content.midX - 200, y: bounds.height - 18), withAttributes: attrs)
            }
            if !settings.footerText.isEmpty {
                let s = settings.footerText as NSString
                s.draw(at: NSPoint(x: content.midX - 200, y: bounds.height - 18), withAttributes: attrs)
            }
        }
    }
}

// MARK: - Controller

struct PrintController {
    let doc: DocumentState
    let settings: PrintSettings

    @MainActor
    func run() {
        let printInfo = NSPrintInfo(dictionary: [:])
        let base = settings.paperSize.points
        let effective = (settings.orientation == .landscape)
            ? CGSize(width: base.height, height: base.width) : base
        printInfo.paperSize = effective
        printInfo.orientation = (settings.orientation == .landscape) ? .landscape : .portrait
        // NSPrintInfo.duplexing isn't exposed by the Command Line Tools SDK, so we
        // apply duplex through the print-settings dictionary using the documented
        // NSPrintDuplexing key (DuplexMode raw values: none=0, longEdge=1, shortEdge=2).
        let duplexRaw: Int
        switch settings.duplex {
        case .longEdge: duplexRaw = 1
        case .shortEdge: duplexRaw = 2
        case .none: duplexRaw = 0
        }
        printInfo.printSettings["NSPrintDuplexing"] = duplexRaw
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit

        let view = PDFPrintView(document: doc.pdfDocument, settings: settings)
        let op = NSPrintOperation(view: view, printInfo: printInfo)
        op.showsProgressPanel = true
        op.showsPrintPanel = true
        op.run()
    }
}
