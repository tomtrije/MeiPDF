import SwiftUI

struct PrintSheet: View {
    let doc: DocumentState
    @Environment(\.dismiss) private var dismiss
    @State private var s: PrintSettings

    init(doc: DocumentState) {
        self.doc = doc
        _s = State(initialValue: PrintSettings())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("打印设置").font(.headline)
            Form {
                Section("页码范围") {
                    TextField("例如：all、1,3,5-9", text: $s.pageRange)
                        .frame(width: 220)
                    Text("共 \(doc.pageCount) 页").foregroundStyle(.secondary)
                }
                Section("纸张与版式") {
                    Picker("纸张尺寸", selection: $s.paperSize) {
                        ForEach(PaperSize.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("方向", selection: $s.orientation) {
                        ForEach(PrintOrientation.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("每张页数", selection: $s.nUp) {
                        ForEach([1, 2, 4, 6, 9, 16], id: \.self) { Text("\($0) 页/张").tag($0) }
                    }
                    Picker("双面", selection: $s.duplex) {
                        ForEach(DuplexMode.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("缩放") {
                    Picker("模式", selection: $s.scaleMode) {
                        ForEach(ScaleMode.allCases) { Text($0.label).tag($0) }
                    }
                    if s.scaleMode == .percent {
                        HStack {
                            Slider(value: $s.scalePercent, in: 10...400, step: 5)
                            Text(String(format: "%.0f%%", s.scalePercent)).frame(width: 50)
                        }
                    }
                }
                Section("色彩") {
                    Picker("模式", selection: $s.colorMode) {
                        ForEach(ColorMode.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("边距 (mm)") {
                    Stepper("页边距：\(String(format: "%.0f", s.margins))", value: $s.margins, in: 0...50, step: 1)
                    Stepper("装订边：\(String(format: "%.0f", s.binding))", value: $s.binding, in: 0...50, step: 1)
                }
                Section("页眉页脚") {
                    Toggle("添加页码", isOn: $s.pageNumbering)
                    TextField("页眉", text: $s.headerText)
                    TextField("页脚", text: $s.footerText)
                }
                Section {
                    Toggle("打印标注", isOn: $s.printAnnotations)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("打印…") {
                    PrintController(doc: doc, settings: s).run()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 440, height: 560)
    }
}
