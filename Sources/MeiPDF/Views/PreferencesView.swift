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

    var body: some View {
        TabView {
            Form {
                Section("默认外观") {
                    Picker("主题", selection: defaultTheme) {
                        ForEach(Theme.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("默认版式", selection: defaultDisplayMode) {
                        ForEach(modes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("行为") {
                    Toggle("记住阅读位置", isOn: rememberLastPosition)
                    Toggle("启用触控板手势", isOn: enableGestures)
                }
                Section("更新") {
                    Toggle("自动检查更新", isOn: checkUpdates)
                    Button("检查更新…") { checkForUpdates() }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
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
                Section {
                    Button("将当前打开文档的设置存为默认") {
                        if let d = appState.selectedDocument(id: appState.selectedID) {
                            d.saveAsDefault()
                            appState.showToast("已保存为默认设置")
                        } else {
                            appState.showToast("请先打开一个文档")
                        }
                    }
                } header: {
                    Text("应用当前为默认")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("默认设置", systemImage: "slider.horizontal.3") }

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
