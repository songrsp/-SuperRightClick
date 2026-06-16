import SwiftUI
import FinderSync

/// 设置 / 引导界面。首次使用按这里三步走即可。
struct SettingsView: View {
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled

    // 功能分组开关，存在 App Group 共享域，扩展出菜单时即时生效。
    @AppStorage(Pref.Key.groupOpenWith,  store: Pref.store) private var grpOpenWith  = true
    @AppStorage(Pref.Key.groupCopyInfo,  store: Pref.store) private var grpCopyInfo  = true
    @AppStorage(Pref.Key.groupNewItems,  store: Pref.store) private var grpNewItems  = true
    @AppStorage(Pref.Key.groupFileOps,   store: Pref.store) private var grpFileOps   = true
    @AppStorage(Pref.Key.groupDeveloper, store: Pref.store) private var grpDeveloper = true
    @AppStorage(Pref.Key.groupWindows,   store: Pref.store) private var grpWindows   = true
    @AppStorage(Pref.Key.groupUninstall, store: Pref.store) private var grpUninstall = true
    @AppStorage(Pref.Key.useSubmenu,     store: Pref.store) private var useSubmenu   = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                stepCard(
                    n: 1,
                    title: "启用 Finder 扩展",
                    desc: "打开「系统设置 → 通用 → 登录项与扩展 → 访达扩展」，勾选「超级右键扩展」。",
                    status: extensionEnabled ? "已启用" : "未启用",
                    ok: extensionEnabled
                ) {
                    Button("打开扩展设置") {
                        FIFinderSyncController.showExtensionManagementInterface()
                    }
                    Button("刷新状态") {
                        extensionEnabled = FIFinderSyncController.isExtensionEnabled
                    }
                }

                stepCard(
                    n: 2,
                    title: "授予完全磁盘访问权限",
                    desc: "卸载应用、清理 ~/Library 残余需要此权限。打开「系统设置 → 隐私与安全性 → 完全磁盘访问权限」，把本程序加进去并打开。",
                    status: "需手动",
                    ok: nil
                ) {
                    Button("打开隐私设置") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                        NSWorkspace.shared.open(url)
                    }
                }

                stepCard(
                    n: 3,
                    title: "保持本程序在后台",
                    desc: "扩展点击后会自动把本程序唤起到后台执行指令。建议加入登录项，开机自启。",
                    status: "建议",
                    ok: nil
                ) {
                    Button("打开登录项设置") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
                        NSWorkspace.shared.open(url)
                    }
                }

                togglesCard
                featureList
                aboutCard
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("⚡️ 超级右键").font(.largeTitle).bold()
            Text("为 macOS Finder 增强右键菜单 · 团队内部版 \(appVersion)")
                .foregroundColor(.secondary)
        }
    }

    private var togglesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("功能开关").font(.headline)
            Text("关掉的分组不会出现在右键菜单里，改动下次右键即生效。")
                .font(.caption).foregroundColor(.secondary)
            Toggle("打开方式（终端 / VS Code / 动态 App 列表）", isOn: $grpOpenWith)
            Toggle("复制信息（路径 / 文件名 / 目录）", isOn: $grpCopyInfo)
            Toggle("新建（txt / md / 文件夹）", isOn: $grpNewItems)
            Toggle("文件操作（复制 / 移动 / 压缩 / 解压 / 重命名 / 废纸篓）", isOn: $grpFileOps)
            Toggle("开发者（SHA256 / MD5）", isOn: $grpDeveloper)
            Toggle("仿 Windows（隐藏文件 / 刷新 / 属性）", isOn: $grpWindows)
            Toggle("彻底卸载 .app", isOn: $grpUninstall)
            Divider().padding(.vertical, 4)
            Toggle("收进「⚡️ 超级右键」子菜单（关=平铺到 Finder 菜单）", isOn: $useSubmenu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关于").font(.headline)
            Text("超级右键 \(appVersion) · MIT 许可 · 仅供团队内部使用")
                .font(.callout).foregroundColor(.secondary)
            Text("卸载/清理一律移到废纸篓，可后悔。需要主程序常驻后台 + 完全磁盘访问权限。")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func stepCard<Buttons: View>(n: Int, title: String, desc: String,
                                         status: String, ok: Bool?,
                                         @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("第 \(n) 步 · \(title)").font(.headline)
                Spacer()
                Text(status)
                    .font(.caption).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badgeColor(ok).opacity(0.18))
                    .foregroundColor(badgeColor(ok))
                    .clipShape(Capsule())
            }
            Text(desc).font(.callout).foregroundColor(.secondary)
            HStack { buttons() }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func badgeColor(_ ok: Bool?) -> Color {
        switch ok { case .some(true): return .green; case .some(false): return .red; default: return .orange }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已内置功能").font(.headline)
            Text("""
            • 复制路径 / 文件名 / 所在目录
            • 新建 txt / md / 文件夹
            • 复制到 / 移动到 / 压缩 ZIP / 解压 / 批量重命名 / 移到废纸篓
            • 在此打开终端 / 用 VS Code 打开 / 复制 SHA256 · MD5
            • 显示隐藏文件 / 刷新 Finder / 属性
            • 彻底卸载 .app 并扫描清理残余
            """)
            .font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
