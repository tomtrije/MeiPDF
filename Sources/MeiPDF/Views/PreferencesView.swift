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
                set: { appState.preferences.defaultTheme = $0 })
    }
    private var defaultDisplayMode: Binding<PDFDisplayMode> {
        Binding(get: { appState.preferences.defaultDisplayMode },
                set: { appState.preferences.defaultDisplayMode = $0 })
    }
    private var rememberLastPosition: Binding<Bool> {
        Binding(get: { appState.preferences.rememberLastPosition },
                set: { appState.preferences.rememberLastPosition = $0 })
    }
    private var enableGestures: Binding<Bool> {
        Binding(get: { appState.preferences.enableGestures },
                set: { appState.preferences.enableGestures = $0 })
    }
    private var checkUpdates: Binding<Bool> {
        Binding(get: { appState.preferences.checkForUpdatesAutomatically },
                set: { appState.preferences.checkForUpdatesAutomatically = $0 })
    }
    private var defaultColorBinding: Binding<Color> {
        Binding(get: { Color(appState.preferences.defaultColor.nsColor) },
                set: { appState.preferences.defaultColor = CodableColor(NSColor($0)) })
    }

    var body: some View {
        Form {
            Section("默认外观") {
                Picker("主题", selection: defaultTheme) {
                    ForEach(Theme.allCases) { Text($0.label).tag($0) }
                }
                Picker("默认版式", selection: defaultDisplayMode) {
                    ForEach(modes, id: \.0) { Text($0.1).tag($0.0) }
                }
                ColorPicker("默认标注颜色", selection: defaultColorBinding)
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
    }

    private func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "检查更新"
        alert.informativeText = "当前为 DMG 直接分发版本；Sparkle 自动更新将在发布阶段接入。"
        alert.runModal()
    }
}
