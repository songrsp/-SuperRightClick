import AppKit
import SwiftUI

/// 批量重命名：前缀 + 起始序号，实时预览，应用后写回磁盘。
@MainActor
final class BatchRenameModel: ObservableObject {
    @Published var prefix: String = "文件"
    @Published var startIndex: Int = 1
    @Published var padZero = true
    let urls: [URL]

    init(urls: [URL]) { self.urls = urls }

    func newName(for index: Int, url: URL) -> String {
        let n = startIndex + index
        let num = padZero ? String(format: "%03d", n) : String(n)
        let ext = url.pathExtension
        return ext.isEmpty ? "\(prefix)\(num)" : "\(prefix)\(num).\(ext)"
    }

    func apply(_ onDone: @escaping () -> Void) {
        for (i, url) in urls.enumerated() {
            let target = url.deletingLastPathComponent().appendingPathComponent(newName(for: i, url: url))
            try? FileManager.default.moveItem(at: url, to: target)
        }
        onDone()
    }
}

struct BatchRenameView: View {
    @ObservedObject var model: BatchRenameModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("批量重命名 \(model.urls.count) 个文件").font(.headline)
            HStack {
                Text("前缀")
                TextField("前缀", text: $model.prefix)
            }
            HStack {
                Text("起始序号")
                Stepper(value: $model.startIndex, in: 0...99999) { Text("\(model.startIndex)") }
                Toggle("补零(001)", isOn: $model.padZero)
            }
            Divider()
            Text("预览").font(.caption).foregroundColor(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.urls.enumerated()), id: \.offset) { i, url in
                        HStack {
                            Text(url.lastPathComponent).foregroundColor(.secondary).lineLimit(1)
                            Image(systemName: "arrow.right").font(.caption2).foregroundColor(.secondary)
                            Text(model.newName(for: i, url: url)).bold().lineLimit(1)
                        }.font(.caption)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 180)
            HStack {
                Spacer()
                Button("取消") { onClose() }
                Button("应用") { model.apply(onClose) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460, height: 380)
    }
}

enum BatchRenameWindow {
    private static var window: NSWindow?

    @MainActor
    static func show(for urls: [URL]) {
        let model = BatchRenameModel(urls: urls)
        let view = BatchRenameView(model: model) { window?.close(); window = nil }
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = "批量重命名"
        win.styleMask = [.titled, .closable]
        win.center()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
