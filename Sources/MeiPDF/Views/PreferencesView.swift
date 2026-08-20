import SwiftUI
import PDFKit

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    private let modes: [(PDFDisplayMode, String)] = [
        (.singlePage, "单页"),
        (.singlePageContinuous, "连续"),
        (.twoUp, "双页"),
        (.twoUpContinuous, "双页连续")
    ]

    private var defaultTheme: Binding<Theme> {
        Binding(get: { appState.preferences.defaultTheme },
                set: { appState.preferences.defaultTheme = $0; appState.preferences.save() })
    }
    private var defaultDisplayMode: Binding<PDFDisplayMode> {
        Binding(get: { appState.preferences.defaultDisplayMode },
                set: { appState.preferences.defaultDisplayMode = $0; appState.preferences.save() })
    }
    private var defaultDisplayDirection: Binding<PDFDisplayDirection> {
        Binding(get: { appState.preferences.defaultDisplayDirection },
                set: { appState.preferences.defaultDisplayDirection = $0; appState.preferences.save() })
    }
    private var rememberLastPosition: Binding<Bool> {
        Binding(get: { appState.preferences.rememberLastPosition },
                set: { appState.preferences.rememberLastPosition = $0; appState.preferences.save() })
    }
    private var enableGestures: Binding<Bool> {
        Binding(get: { appState.preferences.enableGestures },
                set: { appState.preferences.enableGestures = $0; appState.preferences.save() })
    }
    private var checkUpdates: Binding<Bool> {
        Binding(get: { appState.preferences.checkForUpdatesAutomatically },
                set: { appState.preferences.checkForUpdatesAutomatically = $0; appState.preferences.save() })
    }
    private var defaultColorBinding: Binding<Color> {
        Binding(get: { Color(appState.preferences.defaultColor.nsColor) },
                set: { appState.preferences.defaultColor = CodableColor(NSColor($0)); appState.preferences.save() })
    }
    private var defaultLineWidth: Binding<Double> {
        Binding(get: { appState.preferences.defaultLineWidth },
                set: { appState.preferences.defaultLineWidth = $0; appState.preferences.save() })
    }
    private var defaultLineStyle: Binding<LineStyle> {
        Binding(get: { appState.preferences.defaultLineStyle },
                set: { appState.preferences.defaultLineStyle = $0; appState.preferences.save() })
    }
    private var defaultFill: Binding<Bool> {
        Binding(get: { appState.preferences.defaultFill },
                set: { appState.preferences.defaultFill = $0; appState.preferences.save() })
    }
    private var thumbnailSizeBinding: Binding<ThumbSize> {
        Binding(get: { appState.preferences.thumbnailSize },
                set: { appState.preferences.thumbnailSize = $0; appState.preferences.save() })
    }
    private var defaultZoomBinding: Binding<DefaultZoom> {
        Binding(get: { appState.preferences.defaultZoom },
                set: { appState.preferences.defaultZoom = $0; appState.preferences.save() })
    }
    private var startPageBinding: Binding<StartPageMode> {
        Binding(get: { appState.preferences.startPageMode },
                set: { appState.preferences.startPageMode = $0; appState.preferences.save() })
    }
    private var exportWithAnnotationsBinding: Binding<Bool> {
        Binding(get: { appState.preferences.exportWithAnnotations },
                set: { appState.preferences.exportWithAnnotations = $0; appState.preferences.save() })
    }
    private var slideshowIntervalBinding: Binding<Double> {
        Binding(get: { appState.preferences.slideshowInterval },
                set: { appState.preferences.slideshowInterval = $0; appState.preferences.save() })
    }
    private var slideshowLoopBinding: Binding<Bool> {
        Binding(get: { appState.preferences.slideshowLoop },
                set: { appState.preferences.slideshowLoop = $0; appState.preferences.save() })
    }

    // MARK: 文件级（当前文档）绑定 — 每个具体项可手动修改并持久化到 sidecar

    private func docThemeBinding(_ d: DocumentState) -> Binding<Theme> {
        Binding(get: { d.theme }, set: { d.theme = $0; d.persist() })
    }
    private func docModeBinding(_ d: DocumentState) -> Binding<PDFDisplayMode> {
        Binding(get: { d.displayMode }, set: { d.displayMode = $0; d.persist() })
    }
    private func docDirectionBinding(_ d: DocumentState) -> Binding<PDFDisplayDirection> {
        Binding(get: { d.displayDirection }, set: { d.displayDirection = $0; d.persist() })
    }
    private func docRotationBinding(_ d: DocumentState) -> Binding<Int> {
        Binding(get: { d.rotation }, set: {
            d.rotation = $0 % 360
            d.applyRotationToPages()
            d.pdfView?.layoutDocumentView()
            d.persist()
        })
    }
    private func docColorBinding(_ d: DocumentState) -> Binding<Color> {
        Binding(get: { Color(d.activeColor) },
                set: { d.activeColor = NSColor($0); d.persist() })
    }
    private func docWidthBinding(_ d: DocumentState) -> Binding<Double> {
        Binding(get: { d.activeLineWidth }, set: { d.activeLineWidth = $0; d.persist() })
    }
    private func docStyleBinding(_ d: DocumentState) -> Binding<LineStyle> {
        Binding(get: { d.activeLineStyle }, set: { d.activeLineStyle = $0; d.persist() })
    }
    private func docFillBinding(_ d: DocumentState) -> Binding<Bool> {
        Binding(get: { d.activeFill }, set: { d.activeFill = $0; d.persist() })
    }

    // MARK: 页面（运行时）绑定

    private func docScaleBinding(_ d: DocumentState) -> Binding<Double> {
        Binding(get: { d.scaleFactor }, set: { d.setScale($0) })
    }
    private func docShowAnnotationsBinding(_ d: DocumentState) -> Binding<Bool> {
        Binding(get: { d.showAnnotations }, set: { d.showAnnotations = $0; d.persist() })
    }

    var body: some View {
        TabView {
            Form {
                appDefaultsForm
            }
            .formStyle(.grouped)
            .tabItem { Label("应用默认", systemImage: "gearshape") }

            Form {
                fileLevelForm
            }
            .formStyle(.grouped)
            .tabItem { Label("当前文档", systemImage: "doc.text") }

            Form {
                pageLevelForm
            }
            .formStyle(.grouped)
            .tabItem { Label("页面状态", systemImage: "gauge") }

            Form {
                Section("快捷键") {
                    shortcutRow("关闭标签页", "⌘W")
                    shortcutRow("打开文件", "⌘O")
                    shortcutRow("上一页 / 下一页", "⌘[ / ⌘]")
                    shortcutRow("放大 / 缩小", "⌘= / ⌘-")
                    shortcutRow("实际大小", "⌘0")
                    shortcutRow("书签当前页", "⌘D")
                    shortcutRow("高亮 / 下划线 / 删除线", "⌘⇧H / U / S")
                    shortcutRow("笔记", "⌘⇧N")
                    shortcutRow("矩形 / 椭圆 / 直线工具", "⌘⇧R / O / L")
                    shortcutRow("打印", "⌘P")
                    shortcutRow("检查更新", "⌘U")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("快捷键", systemImage: "command") }
        }
    }

    // MARK: 配置 tab —— 应用级默认（作用域：全局）

    @ViewBuilder
    private var appDefaultsForm: some View {
        Section("默认外观") {
            Picker("主题", selection: defaultTheme) {
                ForEach(Theme.allCases) { Text($0.label).tag($0) }
            }
            Picker("默认版式", selection: defaultDisplayMode) {
                ForEach(modes, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("默认滚动方向", selection: defaultDisplayDirection) {
                Text("纵向").tag(PDFDisplayDirection.vertical)
                Text("横向").tag(PDFDisplayDirection.horizontal)
            }
        }
        Section("行为") {
            Toggle("记住阅读位置", isOn: rememberLastPosition)
            Toggle("启用触控板手势", isOn: enableGestures)
        }
        Section("默认打开") {
            Picker("缩略图大小", selection: thumbnailSizeBinding) {
                ForEach(ThumbSize.allCases) { Text($0.label).tag($0) }
            }
            Picker("默认缩放", selection: defaultZoomBinding) {
                ForEach(DefaultZoom.allCases) { Text($0.label).tag($0) }
            }
            Picker("开始页", selection: startPageBinding) {
                ForEach(StartPageMode.allCases) { Text($0.label).tag($0) }
            }
            Toggle("导出时包含标注", isOn: exportWithAnnotationsBinding)
        }
        Section("幻灯片放映") {
            Picker("播放间隔", selection: slideshowIntervalBinding) {
                Text("3 秒").tag(3.0)
                Text("5 秒").tag(5.0)
                Text("8 秒").tag(8.0)
                Text("10 秒").tag(10.0)
            }
            Toggle("循环播放", isOn: slideshowLoopBinding)
        }
        Section("默认标注样式（新建标注时套用）") {
            ColorPicker("颜色", selection: defaultColorBinding)
            Picker("粗细", selection: defaultLineWidth) {
                Text("细").tag(1.0)
                Text("中").tag(2.0)
                Text("粗").tag(4.0)
                Text("特粗").tag(8.0)
            }
            .pickerStyle(.segmented)
            Picker("线型", selection: defaultLineStyle) {
                ForEach(LineStyle.allCases) { Text($0.label).tag($0) }
            }
            Toggle("填充（矩形 / 椭圆）", isOn: defaultFill)
        }
        Section("应用当前为默认") {
            Button("将当前打开文档的设置存为默认") {
                if let d = appState.selectedDocument(id: appState.selectedID) {
                    d.saveAsDefault()
                    appState.showToast("已保存为默认设置")
                } else {
                    appState.showToast("请先打开一个文档")
                }
            }
        }
        Section("更新") {
            Toggle("自动检查更新", isOn: checkUpdates)
            Button("检查更新…") { checkForUpdates() }
        }
    }

    // MARK: 配置 tab —— 文件级（作用域：当前文档，随文档记忆）

    @ViewBuilder
    private var fileLevelForm: some View {
        if let d = appState.selectedDocument(id: appState.selectedID) {
            Section("文件级设置（仅当前文档）") {
                Picker("主题", selection: docThemeBinding(d)) {
                    ForEach(Theme.allCases) { Text($0.label).tag($0) }
                }
                Picker("版式", selection: docModeBinding(d)) {
                    ForEach(modes, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("滚动方向", selection: docDirectionBinding(d)) {
                    Text("纵向").tag(PDFDisplayDirection.vertical)
                    Text("横向").tag(PDFDisplayDirection.horizontal)
                }
                Picker("旋转", selection: docRotationBinding(d)) {
                    Text("0°").tag(0)
                    Text("90°").tag(90)
                    Text("180°").tag(180)
                    Text("270°").tag(270)
                }
                ColorPicker("标注颜色", selection: docColorBinding(d))
                Picker("线宽", selection: docWidthBinding(d)) {
                    Text("细").tag(1.0)
                    Text("中").tag(2.0)
                    Text("粗").tag(4.0)
                    Text("特粗").tag(8.0)
                }
                .pickerStyle(.segmented)
                Picker("线型", selection: docStyleBinding(d)) {
                    ForEach(LineStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("填充（矩形 / 椭圆）", isOn: docFillBinding(d))
                Toggle("显示高亮与备注", isOn: docShowAnnotationsBinding(d))
            }
        } else {
            Text("请先打开一个文档，再编辑它的文件级设置。").foregroundStyle(.secondary)
        }
    }

    // MARK: 配置 tab —— 页面级（作用域：当前文档运行态）

    @ViewBuilder
    private var pageLevelForm: some View {
        if let d = appState.selectedDocument(id: appState.selectedID) {
            Section("缩放倍率（拖动调节，实时生效）") {
                HStack {
                    Text("缩放")
                    Spacer()
                    Text(String(format: "%.0f%%", docScaleBinding(d).wrappedValue * 100))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: docScaleBinding(d), in: 0.5...4.0, step: 0.05)
                HStack {
                    Button("适应宽度") { d.fitWidth() }
                    Button("适应页面") { d.fitPage() }
                    Button("适应高度") { d.fitHeight() }
                    Button("实际大小") { d.actualSize() }
                }
            }
        } else {
            Text("请先打开一个文档，再调整它的页面级配置。").foregroundStyle(.secondary)
        }
    }

    private func shortcutRow(_ name: String, _ keys: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(keys).foregroundStyle(.secondary).font(.system(.body, design: .monospaced))
        }
    }

    private func checkForUpdates() {
        UpdaterHost.shared.checkForUpdates()
    }
}
