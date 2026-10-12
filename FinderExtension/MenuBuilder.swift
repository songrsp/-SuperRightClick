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

/// Finder 菜单的声明式模型。
///
/// 先用模型描述“这个功能是否启用、显示什么、点击后执行什么”，再由
/// `MenuBuilder` 统一转换为 `NSMenuItem`。这样偏好开关只影响模型层，
/// 不会把 UI 配置字段混进 Shared/Command.swift 的动作协议。
private indirect enum MenuModel {
    case leaf(title: String, action: ActionID, arg: String?, enabled: Bool)
    case group(title: String, children: [MenuModel], enabled: Bool)
    case section(children: [MenuModel], enabled: Bool)

    static func item(title: String, action: ActionID, arg: String? = nil,
                    enabled: Bool = true) -> MenuModel {
        .leaf(title: title, action: action, arg: arg, enabled: enabled)
    }

    static func submenu(title: String, children: [MenuModel],
                       enabled: Bool = true) -> MenuModel {
        .group(title: title, children: children, enabled: enabled)
    }

    static func flat(_ children: [MenuModel], enabled: Bool = true) -> MenuModel {
        .section(children: children, enabled: enabled)
    }

    var isEnabled: Bool {
        switch self {
        case let .leaf(_, _, _, enabled), let .group(_, _, enabled),
             let .section(_, enabled):
            return enabled
        }
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

        // 先生成启用状态的模型数组，再统一渲染。Finder 注入菜单时不插入
        // 分隔符，避免第三方上下文菜单出现大块空白。
        let models = makeModels(selected: selected,
                                hasSelection: hasSelection,
                                hasApp: hasApp,
                                hasArchive: hasArchive)
        render(models, into: dest, target: target, action: action)

        return root
    }

    private static func makeModels(selected: [URL], hasSelection: Bool,
                                   hasApp: Bool, hasArchive: Bool) -> [MenuModel] {
        var openItems: [MenuModel] = [
            .item(title: "在此打开终端", action: .openInTerminal),
            .item(title: "用 VS Code 打开", action: .openInVSCode),
        ]
        openItems += appsThatOpen(selected).map {
            .item(title: $0.deletingPathExtension().lastPathComponent,
                  action: .openWith, arg: $0.path)
        }

        var fileItems: [MenuModel] = []
        if hasSelection {
            fileItems += [
                .item(title: "剪切", action: .cutFiles),
                .item(title: "复制文件", action: .copyFiles),
            ]
        }
        let clipCount = FileClipboard.count
        if clipCount > 0 {
            fileItems.append(.item(title: "粘贴 \(clipCount) 项到此处", action: .pasteHere))
        }
        if hasSelection {
            fileItems += [
                .item(title: "复制到…", action: .copyToFolder),
                .item(title: "移动到…", action: .moveToFolder),
                .item(title: "压缩为 ZIP", action: .compress),
            ]
            if hasArchive { fileItems.append(.item(title: "解压到此处", action: .decompress)) }
            if selected.count > 1 { fileItems.append(.item(title: "批量重命名…", action: .batchRename)) }
            fileItems.append(.item(title: "移到废纸篓", action: .moveToTrash))
        }

        return [
            .submenu(title: "打开方式", children: openItems, enabled: Pref.openWith),
            .flat([
                .item(title: "复制路径", action: .copyPath),
                .item(title: "复制文件名", action: .copyName),
                .item(title: "复制所在目录", action: .copyDirPath),
            ], enabled: Pref.copyInfo && hasSelection),
            .submenu(title: "新建", children: [
                .item(title: "文本文件 (.txt)", action: .newFileTxt),
                .item(title: "Markdown (.md)", action: .newFileMarkdown),
                .item(title: "文件夹", action: .newFolder),
            ], enabled: Pref.newItems),
            .flat(fileItems, enabled: Pref.fileOps),
            .flat([
                .item(title: "复制 SHA256", action: .copyHashSHA256),
                .item(title: "复制 MD5", action: .copyHashMD5),
            ], enabled: Pref.developer && hasSelection),
            .flat([
                .item(title: "显示/隐藏隐藏文件", action: .toggleHiddenFiles),
                .item(title: "刷新", action: .refreshFinder),
                .item(title: "属性", action: .showProperties, enabled: hasSelection),
            ], enabled: Pref.windows),
            .item(title: "彻底卸载此应用并清理残余…", action: .uninstallApp,
                  enabled: Pref.uninstall && hasApp),
        ]
    }

    private static func render(_ models: [MenuModel], into menu: NSMenu,
                               target: AnyObject, action: Selector) {
        for model in models where model.isEnabled {
            switch model {
            case let .leaf(title, id, arg, _):
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = target
                let tag = MenuRegistry.register(MenuPayload(action: id, arg: arg))
                item.tag = tag
                var dict = ["action": id.rawValue]
                if let arg = arg { dict["arg"] = arg }
                item.representedObject = dict
                Log.debugFile("item build title=\(title) tag=\(tag) action=\(id.rawValue) arg=\(arg ?? "nil")")
                menu.addItem(item)

            case let .group(title, children, _):
                let visibleChildren = children.filter { $0.isEnabled }
                guard !visibleChildren.isEmpty else { continue }
                let head = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let childMenu = NSMenu()
                render(visibleChildren, into: childMenu, target: target, action: action)
                head.submenu = childMenu
                menu.addItem(head)

            case let .section(children, _):
                render(children, into: menu, target: target, action: action)
            }
        }
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
