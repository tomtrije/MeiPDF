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
    case highlight, underline, strikeOut, note, square, circle, line
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
    var createdAt: Date
}

// MARK: - Document metadata (non-destructive sidecar)

struct DocumentMeta: Codable {
    var bookmarks: [Int] = []
    var lastPage: Int = 0
    var rotation: Int = 0
    var annotations: [Annotation] = []
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
