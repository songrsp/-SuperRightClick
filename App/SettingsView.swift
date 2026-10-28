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
    @AppStorage(Pref.Key.newFileAutoOpen, store: Pref.store) private var newFileAutoOpen = false
    @AppStorage(Pref.Key.newFileAutoReveal, store: Pref.store) private var newFileAutoReveal = true
    @AppStorage(Pref.Key.coloredIcons,    store: Pref.store) private var coloredIcons    = true
    @AppStorage(Pref.Key.hotkeyCutPaste,  store: Pref.store) private var hotkeyCutPaste  = true
    @AppStorage(Pref.Key.hotkeyDelete,    store: Pref.store) private var hotkeyDelete    = true
    @AppStorage(Pref.Key.hotkeyEnterOpen, store: Pref.store) private var hotkeyEnterOpen = false
    @State private var accessibilityTrusted = FinderHotkeys.isTrusted

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

                stepCard(
                    n: 4,
                    title: "授予辅助功能权限（Finder 快捷键）",
                    desc: "⌘X 剪切、Delete 删除等快捷键需要此权限。打开「系统设置 → 隐私与安全性 → 辅助功能」，把本程序加进去并打开。授权后无需重启即生效。",
                    status: accessibilityTrusted ? "已授权" : "未授权",
                    ok: accessibilityTrusted
                ) {
                    Button("请求授权") {
                        FinderHotkeys.requestAccess()
                    }
                    Button("打开辅助功能设置") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        NSWorkspace.shared.open(url)
                    }
                    Button("刷新状态") {
                        accessibilityTrusted = FinderHotkeys.isTrusted
                    }
                }

                togglesCard
                hotkeysCard
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
            Toggle("新建后用默认 App 打开", isOn: $newFileAutoOpen)
            Toggle("新建后在 Finder 中选中", isOn: $newFileAutoReveal)
            Divider().padding(.vertical, 4)
            Toggle("收进「⚡️ 超级右键」子菜单（关=平铺到 Finder 菜单）", isOn: $useSubmenu)
            Toggle("菜单项显示彩色图标（和 Finder 原生菜单区分）", isOn: $coloredIcons)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var hotkeysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finder 快捷键（仿 Windows）").font(.headline)
            Text("只在 Finder 浏览文件时生效；重命名、搜索框里打字时保持系统原样。需要第 4 步的辅助功能权限，且本程序在后台运行。")
                .font(.caption).foregroundColor(.secondary)
            Toggle("⌘X 剪切 → ⌘V 粘贴时移动（⌘C 复制保持不变）", isOn: $hotkeyCutPaste)
            Toggle("Delete 键（⌫ / ⌦）移到废纸篓", isOn: $hotkeyDelete)
            Toggle("回车打开、F2 重命名（会改变 Mac 回车重命名的习惯）", isOn: $hotkeyEnterOpen)
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
            • Finder 快捷键：⌘X 剪切 / ⌘V 粘贴、Delete 删除、回车打开、F2 重命名
            """)
            .font(.callout).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
