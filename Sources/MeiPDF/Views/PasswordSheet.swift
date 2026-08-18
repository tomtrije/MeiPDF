import SwiftUI

struct PasswordSheet: View {
    let url: URL?
    let onUnlock: (URL, String) -> Void
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("该 PDF 已加密").font(.headline)
            if let url { Text(url.lastPathComponent).foregroundStyle(.secondary) }
            SecureField("密码", text: $password)
                .frame(width: 240)
            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                Button("解锁") {
                    if let url { onUnlock(url, password) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
