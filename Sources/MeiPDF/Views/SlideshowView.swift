import SwiftUI
import PDFKit

/// Full-screen presentation mode (对齐预览的「幻灯片放映」). Manual advance via
/// arrows / space / click; optional auto-play with a configurable interval and loop.
struct SlideshowView: View {
    @Bindable var doc: DocumentState
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int = 0
    @State private var autoplay: Bool = false
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                } else {
                    ProgressView().tint(.white)
                }

                // Top-right exit
                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])
                        .help("退出放映（Esc）")
                    }
                    .padding(16)
                    Spacer()
                }

                // Bottom control bar
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title) }
                            .buttonStyle(.plain).help("上一页（←）")
                        Button {
                            autoplay.toggle()
                            if autoplay { index = doc.currentPage }
                        } label: {
                            Image(systemName: autoplay ? "pause.circle.fill" : "play.circle.fill").font(.title)
                        }
                        .buttonStyle(.plain)
                        .help(autoplay ? "暂停" : "自动播放")
                        Button { step(1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title) }
                            .buttonStyle(.plain).help("下一页（→ / 空格）")
                        Text("\(index + 1) / \(doc.pageCount)")
                            .foregroundStyle(.white).font(.headline)
                            .frame(minWidth: 70)
                        Divider().frame(height: 22).overlay(Color.white.opacity(0.6))
                        Picker("间隔", selection: intervalBinding) {
                            Text("3 秒").tag(3.0)
                            Text("5 秒").tag(5.0)
                            Text("8 秒").tag(8.0)
                            Text("10 秒").tag(10.0)
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(.white)
                        Toggle("循环", isOn: loopBinding)
                            .foregroundStyle(.white)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(.bottom, 24)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { step(1) }
            .onAppear { index = doc.currentPage; render(in: geo.size) }
            .onChange(of: index) { _, _ in render(in: geo.size) }
            .onChange(of: geo.size) { _, new in render(in: new) }
            .onReceive(Timer.publish(every: appState.preferences.slideshowInterval, on: .main, in: .common).autoconnect()) { _ in
                if autoplay { step(1) }
            }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .onKeyPress(.space) { step(1); return .handled }
        }
    }

    private func step(_ dir: Int) {
        let n = doc.pageCount
        guard n > 0 else { return }
        var next = index + dir
        if next >= n {
            if appState.preferences.slideshowLoop { next = 0 } else { autoplay = false; next = n - 1 }
        } else if next < 0 {
            if appState.preferences.slideshowLoop { next = n - 1 } else { autoplay = false; next = 0 }
        }
        index = next
    }

    private var intervalBinding: Binding<Double> {
        Binding(get: { appState.preferences.slideshowInterval },
                set: { appState.preferences.slideshowInterval = $0; appState.preferences.save() })
    }
    private var loopBinding: Binding<Bool> {
        Binding(get: { appState.preferences.slideshowLoop },
                set: { appState.preferences.slideshowLoop = $0; appState.preferences.save() })
    }

    private func render(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        image = doc.pageImage(at: index, maxSize: size)
    }
}
