import Foundation
import PDFKit
import SwiftUI

// MARK: - Theme

enum Theme: String, Codable, CaseIterable, Identifiable {
    case light, dark, sepia
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        case .sepia: "护眼"
        }
    }
    var backgroundColor: NSColor {
        switch self {
        case .light: NSColor(white: 0.92, alpha: 1)
        case .dark: NSColor(white: 0.16, alpha: 1)
        case .sepia: NSColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1)
        }
    }
}

// MARK: - Annotation types

enum AnnotationType: String, Codable, CaseIterable, Identifiable {
    case highlight, underline, strikeOut, note, square, circle, line, arrow, ink, freeText
    var id: String { rawValue }
    var label: String {
        switch self {
        case .highlight: "高亮"
        case .underline: "下划线"
        case .strikeOut: "删除线"
        case .note: "笔记"
        case .square: "矩形"
        case .circle: "椭圆"
        case .line: "直线"
        case .arrow: "箭头"
        case .ink: "手绘"
        case .freeText: "文本框"
        }
    }
}

// MARK: - Annotation line styles

enum LineStyle: String, Codable, CaseIterable, Identifiable {
    case solid, dashed, dotted
    var id: String { rawValue }
    var label: String {
        switch self {
        case .solid: "实线"
        case .dashed: "虚线"
        case .dotted: "点线"
        }
    }
    /// Dash pattern in PDF points; `nil` means a solid line.
    var dashPattern: [CGFloat]? {
        switch self {
        case .solid: nil
        case .dashed: [4, 3]
        case .dotted: [1.5, 3]
        }
    }
}

struct CodableColor: Codable {
    var r: Double, g: Double, b: Double, a: Double
    var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        r = c.redComponent
        g = c.greenComponent
        b = c.blueComponent
        a = c.alphaComponent
    }
    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

struct CRect: Codable { var x: Double, y: Double, w: Double, h: Double }
struct CPoint: Codable { var x: Double, y: Double }

struct Annotation: Codable, Identifiable {
    var id: UUID
    var pageIndex: Int
    var type: AnnotationType
    var bounds: CRect
    var quadPoints: [CPoint]?
    var color: CodableColor
    var contents: String?
    /// Display name shown in the sidebar; editable by the user. Defaults to the
    /// type label when `nil`.
    var name: String?
    var createdAt: Date

    // Style fields (only meaningful for shape / line annotations).
    var lineWidth: Double = 2
    var lineStyle: LineStyle = .solid
    var hasFill: Bool = false
    // Precise endpoints for line / arrow annotations (page coordinates).
    var lineStart: CPoint?
    var lineEnd: CPoint?
    // Stroke points for ink (freehand) annotations, one sub-array per stroke,
    // stored in absolute page coordinates. Rebuilt relative to `bounds` on render.
    var inkPoints: [[CPoint]]? = nil

    init(id: UUID, pageIndex: Int, type: AnnotationType, bounds: CRect,
         quadPoints: [CPoint]?, color: CodableColor, contents: String?,
         name: String? = nil,
         createdAt: Date, lineWidth: Double = 2, lineStyle: LineStyle = .solid,
         hasFill: Bool = false, lineStart: CPoint? = nil, lineEnd: CPoint? = nil,
         inkPoints: [[CPoint]]? = nil) {
        self.id = id
        self.pageIndex = pageIndex
        self.type = type
        self.bounds = bounds
        self.quadPoints = quadPoints
        self.color = color
        self.contents = contents
        self.name = name
        self.createdAt = createdAt
        self.lineWidth = lineWidth
        self.lineStyle = lineStyle
        self.hasFill = hasFill
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.inkPoints = inkPoints
    }

    /// Custom decoder keeps old sidecar files (without style fields) decodable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pageIndex = try c.decode(Int.self, forKey: .pageIndex)
        type = try c.decode(AnnotationType.self, forKey: .type)
        bounds = try c.decode(CRect.self, forKey: .bounds)
        quadPoints = try c.decodeIfPresent([CPoint].self, forKey: .quadPoints)
        color = try c.decode(CodableColor.self, forKey: .color)
        contents = try c.decodeIfPresent(String.self, forKey: .contents)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 2
        lineStyle = try c.decodeIfPresent(LineStyle.self, forKey: .lineStyle) ?? .solid
        hasFill = try c.decodeIfPresent(Bool.self, forKey: .hasFill) ?? false
        lineStart = try c.decodeIfPresent(CPoint.self, forKey: .lineStart)
        lineEnd = try c.decodeIfPresent(CPoint.self, forKey: .lineEnd)
        inkPoints = try c.decodeIfPresent([[CPoint]].self, forKey: .inkPoints)
    }
}

// MARK: - Document metadata (non-destructive sidecar)

/// Everything MeiPDF remembers about a single file, stored in a sidecar JSON next
/// to the PDF (never mutating the original). Three responsibility levels:
///  - **page-level**: `lastPage`, `bookmarks` (which page + its display name)
///  - **file-level viewing settings**: `theme` / `displayMode` / `displayDirection` /
///    `activeColor` / `lineWidth` / `lineStyle` / `hasFill` — restored every time the
///    file is reopened, but overridden by the global app defaults until the user
///    changes them in-session.
///  - **annotations**: the user's own (non-destructive) marks.
struct DocumentMeta: Codable {
    var bookmarks: [Int: String] = [:]
    var lastPage: Int = 0
    var rotation: Int = 0
    var annotations: [Annotation] = []

    // File-level viewing settings (see DocumentState.loadMeta / persist).
    var theme: String = Theme.light.rawValue
    var displayMode: Int = PDFDisplayMode.singlePageContinuous.rawValue
    var displayDirection: Int = PDFDisplayDirection.vertical.rawValue
    var activeColor: [Double] = [1, 0.8, 0, 1]
    var lineWidth: Double = 2
    var lineStyle: String = LineStyle.solid.rawValue
    var hasFill: Bool = false
}

// MARK: - Recent files

struct RecentFile: Codable, Identifiable {
    var id: UUID
    var path: String
    var name: String
    var lastOpened: Date
}

// MARK: - Preferences

@MainActor
@Observable
final class Preferences {
    var defaultTheme: Theme = .light
    var defaultDisplayMode: PDFDisplayMode = .singlePageContinuous
    var defaultDisplayDirection: PDFDisplayDirection = .vertical
    var rememberLastPosition: Bool = true
    var enableGestures: Bool = true
    var checkForUpdatesAutomatically: Bool = true
    var defaultColor: CodableColor = CodableColor(NSColor.systemYellow)
    var defaultLineWidth: Double = 2
    var defaultLineStyle: LineStyle = .solid
    var defaultFill: Bool = false

    private let defaultsKey = "meipdf.preferences"

    init() { load() }

    func load() {
        guard let d = UserDefaults.standard.dictionary(forKey: defaultsKey) else { return }
        if let t = d["theme"] as? String, let th = Theme(rawValue: t) { defaultTheme = th }
        if let m = d["mode"] as? Int {
            defaultDisplayMode = PDFDisplayMode(rawValue: m) ?? .singlePageContinuous
        }
        if let dir = d["dir"] as? Int {
            defaultDisplayDirection = PDFDisplayDirection(rawValue: dir) ?? .vertical
        }
        if let c = d["color"] as? [Double], c.count == 4 {
            defaultColor = CodableColor(r: c[0], g: c[1], b: c[2], a: c[3])
        }
        if let w = d["width"] as? Double { defaultLineWidth = w }
        if let s = d["style"] as? String, let ls = LineStyle(rawValue: s) { defaultLineStyle = ls }
        if let f = d["fill"] as? Bool { defaultFill = f }
    }

    func save() {
        let d: [String: Any] = [
            "theme": defaultTheme.rawValue,
            "mode": Int(defaultDisplayMode.rawValue),
            "dir": Int(defaultDisplayDirection.rawValue),
            "color": [defaultColor.r, defaultColor.g, defaultColor.b, defaultColor.a],
            "width": defaultLineWidth,
            "style": defaultLineStyle.rawValue,
            "fill": defaultFill
        ]
        UserDefaults.standard.set(d, forKey: defaultsKey)
    }
}

// MARK: - Print settings

enum PaperSize: String, Codable, CaseIterable, Identifiable {
    case a4, letter, a3, a5, b5
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var points: CGSize {
        switch self {
        case .a4: CGSize(width: 595.28, height: 841.89)
        case .letter: CGSize(width: 612, height: 792)
        case .a3: CGSize(width: 841.89, height: 1190.55)
        case .a5: CGSize(width: 419.53, height: 595.28)
        case .b5: CGSize(width: 515.91, height: 728.50)
        }
    }
}

enum ScaleMode: String, Codable, CaseIterable, Identifiable {
    case fit, actual, percent
    var id: String { rawValue }
    var label: String {
        switch self { case .fit: "适应页面"; case .actual: "实际大小"; case .percent: "百分比" }
    }
}

enum PrintOrientation: String, Codable, CaseIterable, Identifiable {
    case auto, portrait, landscape
    var id: String { rawValue }
    var label: String {
        switch self { case .auto: "自动"; case .portrait: "纵向"; case .landscape: "横向" }
    }
}

enum DuplexMode: String, Codable, CaseIterable, Identifiable {
    case none, longEdge, shortEdge
    var id: String { rawValue }
    var label: String {
        switch self { case .none: "单面"; case .longEdge: "长边翻转"; case .shortEdge: "短边翻转" }
    }
}

enum ColorMode: String, Codable, CaseIterable, Identifiable {
    case color, grayscale, blackWhite
    var id: String { rawValue }
    var label: String {
        switch self { case .color: "彩色"; case .grayscale: "灰度"; case .blackWhite: "黑白" }
    }
}

struct PrintSettings: Codable {
    var pageRange: String = "all"
    var paperSize: PaperSize = .a4
    var scaleMode: ScaleMode = .fit
    var scalePercent: Double = 100
    var orientation: PrintOrientation = .auto
    var nUp: Int = 1
    var duplex: DuplexMode = .none
    var colorMode: ColorMode = .color
    var margins: Double = 18.0
    var binding: Double = 0
    var pageNumbering: Bool = false
    var headerText: String = ""
    var footerText: String = ""
    var printAnnotations: Bool = true
}
