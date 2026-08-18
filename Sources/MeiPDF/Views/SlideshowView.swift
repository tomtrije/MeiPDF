import SwiftUI
import PDFKit

/// Full-screen presentation mode (对齐预览的「幻灯片放映」). Manual advance via
/// arrows / space / click; optional auto-play every 4 seconds.
struct SlideshowView: View {
    @Bindable var doc: DocumentState
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
            .onReceive(Timer.publish(every: 4, on: .main, in: .common).autoconnect()) { _ in
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
        index = (index + dir + n) % n
    }

    private func render(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        image = doc.pageImage(at: index, maxSize: size)
    }
}
