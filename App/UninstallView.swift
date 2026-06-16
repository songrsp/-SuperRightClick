import SwiftUI

/// 卸载确认窗口：列出 .app 本体 + 扫描到的残余文件，逐项可勾选，确认后移到废纸篓。
struct UninstallView: View {
    @EnvironmentObject var mgr: UninstallManager

    private var selectedBytes: Int64 {
        mgr.items.filter { $0.include }.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            VStack(alignment: .leading, spacing: 4) {
                Text("彻底卸载「\(mgr.appName)」")
                    .font(.title2).bold()
                Text(mgr.bundleID.isEmpty ? "未读到 Bundle ID" : mgr.bundleID)
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding()

            Divider()

            if mgr.scanning {
                HStack { ProgressView(); Text("正在扫描残余文件…").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($mgr.items) { $item in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $item.include).labelsHidden()
                            Image(systemName: item.isAppBundle ? "app.fill" : "doc.fill")
                                .foregroundColor(item.isAppBundle ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.url.lastPathComponent)
                                    .lineLimit(1)
                                Text(item.displayPath)
                                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(item.sizeText).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // 底部操作栏
            HStack {
                Text("共 \(mgr.items.count) 项 · 已选 \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("取消") { mgr.cancel() }
                Button("移到废纸篓") { mgr.performDeletion() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(mgr.scanning || mgr.items.allSatisfy { !$0.include })
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 480)
    }
}
