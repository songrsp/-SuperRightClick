import Cocoa
import FinderSync

/// 菜单项载荷：动作 + 可选参数（如 openWith 的目标 App 路径）。
struct MenuPayload {
    let action: ActionID
    let arg: String?
}

/// 菜单项载荷登记处（仅扩展进程内使用）。
///
/// 为什么需要它：Finder Sync 扩展运行在独立进程，`menu(for:)` 返回的 NSMenu 会被
/// Finder 跨进程「复制」一份再展示。这次复制只保留 NSMenuItem 里可被 NSCoding 序列化的
/// 基本属性（title / tag / state / action / target 映射 / keyEquivalent / image / submenu）。
/// `representedObject` 装的是任意对象，**不在序列化范围内**，回调时必然变成 nil —— 这正是
/// 之前 `payload=nil` 的根因。
///
/// 解决办法：用一定会被保留的 `tag`(Int) 当索引，把真正的载荷存在本进程的静态表里。
/// build 与 click 都发生在同一个扩展进程，static 表自然共享。
enum MenuRegistry {
    private static var store: [Int: MenuPayload] = [:]
    private static var counter = 0

    /// 每次重建菜单时清空，避免无限增长 / 旧 tag 串味。
    static func reset() {
        store.removeAll()
        counter = 0
    }

    /// 登记一条载荷，返回它的 tag。tag 从 1 开始，绝不返回 0
    /// （0 是 NSMenuItem 默认 tag，留给分隔符 / 子菜单父项等无载荷项）。
    static func register(_ payload: MenuPayload) -> Int {
        counter += 1
        store[counter] = payload
        return counter
    }

    static func lookup(_ tag: Int) -> MenuPayload? {
        store[tag]
    }
}

/// 负责拼装仿 Windows 风格的右键菜单。
/// - 菜单项是否出现，会按「当前选中内容」+「用户偏好开关(Pref)」动态决定。
/// - 默认平铺进 Finder 原生右键；用户可在设置里改成收进「⚡️ 超级右键」子菜单。
enum MenuBuilder {

    static func build(target: AnyObject, action: Selector, menuKind: FIMenuKind) -> NSMenu {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let hasSelection = !selected.isEmpty
        let hasApp = selected.contains { $0.pathExtension == "app" }
        let hasArchive = selected.contains {
            ["zip", "tar", "gz", "tgz", "7z", "rar"].contains($0.pathExtension.lowercased())
        }
        Log.debugFile("build menu kind=\(menuKind.rawValue) selected=\(selected.map { $0.path }.joined(separator: ","))")

        // 关键：每次重建菜单先清空登记处，tag 从 1 重新发号。
        MenuRegistry.reset()

        let root = NSMenu()

        // 内容容器：平铺时直接用 root；否则塞进一个父项的子菜单。
        let dest: NSMenu
        if Pref.useSubmenu {
            let parent = NSMenuItem(title: "⚡️ 超级右键", action: nil, keyEquivalent: "")
            let m = NSMenu()
            parent.submenu = m
            root.addItem(parent)
            dest = m
        } else {
            dest = root
        }

        func item(_ title: String, _ id: ActionID, arg: String? = nil) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
            mi.target = target

            // 主载荷通道：tag → 登记处（跨进程一定能保住的 Int）。
            let tag = MenuRegistry.register(MenuPayload(action: id, arg: arg))
            mi.tag = tag

            // 兼容 fallback：representedObject 仍照设，但回调里不再依赖它
            // （Finder 复制菜单时大概率会丢，仅作冗余）。
            var dict = ["action": id.rawValue]
            if let arg = arg { dict["arg"] = arg }
            mi.representedObject = dict

            Log.debugFile("item build title=\(title) tag=\(tag) action=\(id.rawValue) arg=\(arg ?? "nil")")
            return mi
        }
        func addSubmenu(_ title: String, _ items: [NSMenuItem]) {
            guard !items.isEmpty else { return }
            let head = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu()
            items.forEach { m.addItem($0) }
            head.submenu = m
            dest.addItem(head)
        }

        // 排版说明：Finder Sync 注入的上下文菜单里,第三方 .separator() 不会渲染成
        // 原生那种细分隔线,而是变成一整截突兀的空白。用户选择「紧凑平铺」,所以这里
        // 六组功能直接连成一条连续列表,不插任何分隔符。

        // —— 打开方式（含动态列出可打开选中文件的 App）——
        if Pref.openWith {
            var openItems = [
                item("在此打开终端", .openInTerminal),
                item("用 VS Code 打开", .openInVSCode),
            ]
            let apps = appsThatOpen(selected)
            if !apps.isEmpty {
                for appURL in apps {
                    openItems.append(item(appURL.deletingPathExtension().lastPathComponent,
                                          .openWith, arg: appURL.path))
                }
            }
            addSubmenu("打开方式", openItems)
        }

        // —— 复制信息 ——
        if Pref.copyInfo && hasSelection {
            dest.addItem(item("复制路径", .copyPath))
            dest.addItem(item("复制文件名", .copyName))
            dest.addItem(item("复制所在目录", .copyDirPath))
        }

        // —— 新建 ——
        if Pref.newItems {
            addSubmenu("新建", [
                item("文本文件 (.txt)", .newFileTxt),
                item("Markdown (.md)", .newFileMarkdown),
                item("文件夹", .newFolder),
            ])
        }

        // —— 文件操作（需选中对象）——
        if Pref.fileOps && hasSelection {
            dest.addItem(item("复制到…", .copyToFolder))
            dest.addItem(item("移动到…", .moveToFolder))
            dest.addItem(item("压缩为 ZIP", .compress))
            if hasArchive { dest.addItem(item("解压到此处", .decompress)) }
            if selected.count > 1 { dest.addItem(item("批量重命名…", .batchRename)) }
            dest.addItem(item("移到废纸篓", .moveToTrash))
        }

        // —— 开发者（哈希）——
        if Pref.developer && hasSelection {
            dest.addItem(item("复制 SHA256", .copyHashSHA256))
            dest.addItem(item("复制 MD5", .copyHashMD5))
        }

        // —— 仿 Windows 常驻项 ——
        if Pref.windows {
            dest.addItem(item("显示/隐藏隐藏文件", .toggleHiddenFiles))
            dest.addItem(item("刷新", .refreshFinder))
            if hasSelection { dest.addItem(item("属性", .showProperties)) }
        }

        // —— 卸载（仅选中 .app 时出现）——
        if Pref.uninstall && hasApp {
            dest.addItem(item("彻底卸载此应用并清理残余…", .uninstallApp))
        }

        return root
    }

    /// 查询能打开选中文件的 App（去重按名、限量 8 个）。多选时按第一个文件的类型。
    private static func appsThatOpen(_ urls: [URL]) -> [URL] {
        guard let first = urls.first else { return [] }
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
        var seen = Set<String>()
        var out: [URL] = []
        for a in apps {
            let name = a.deletingPathExtension().lastPathComponent
            if seen.insert(name).inserted { out.append(a) }
            if out.count >= 8 { break }
        }
        return out
    }
}
