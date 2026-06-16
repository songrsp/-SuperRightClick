import Cocoa
import FinderSync

/// Finder Sync 扩展主类。
/// 职责：①声明监控范围（设为根目录 / ，从而在任何位置都出现菜单）
///      ②构建右键菜单
///      ③把用户点击转换成 Command，能就地做的就地做，做不了的投递给主程序
final class FinderSyncController: FIFinderSync {

    override init() {
        super.init()
        Log.info("FinderSync 扩展启动")

        // 关键技巧：把监控目录设为根目录，菜单就能在任意文件夹生效。
        // （iRightMouse 等工具同理。若只想在某些目录生效，改成对应 URL 数组即可。）
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // 只在右键上下文菜单里出现（选中文件 / 右键文件夹空白处）
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            return MenuBuilder.build(target: self,
                                     action: #selector(handleMenu(_:)),
                                     menuKind: menuKind)
        default:
            return nil
        }
    }

    // MARK: - 点击分发

    @objc private func handleMenu(_ sender: NSMenuItem) {
        // 主通道：tag → 登记处。Finder 跨进程复制菜单时 tag 一定保留，representedObject 会丢。
        var payload = MenuRegistry.lookup(sender.tag)

        // 兼容 fallback：万一 tag 没命中（极端情况），再尝试老的字典载荷。
        if payload == nil,
           let dict = sender.representedObject as? [String: String],
           let raw = dict["action"], let a = ActionID(rawValue: raw) {
            payload = MenuPayload(action: a, arg: dict["arg"])
        }

        Log.debugFile("clicked title=\(sender.title) tag=\(sender.tag) payload=\(payload.map { "action=\($0.action.rawValue) arg=\($0.arg ?? "nil")" } ?? "nil")")

        guard let payload = payload else {
            Log.debugFile("click ignored: no payload for tag=\(sender.tag)")
            return
        }
        let actionID = payload.action
        let arg = payload.arg

        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let container = FIFinderSyncController.default().targetedURL()
        let paths = selected.map { $0.path }
        let containerPath = container?.path

        Log.info("点击动作 \(actionID.rawValue)，选中 \(paths.count) 项")
        Log.debugFile("dispatch action=\(actionID.rawValue) arg=\(arg ?? "nil") paths=\(paths.joined(separator: ",")) container=\(containerPath ?? "nil")")

        // 复制类操作：扩展内就能完成剪贴板写入，最快、瞬时、不抢焦点，绝不唤起主程序。
        switch actionID {
        case .copyPath:
            Clipboard.copy(paths.isEmpty ? (containerPath ?? "") : paths.joined(separator: "\n"))
            return
        case .copyName:
            Clipboard.copy(selected.isEmpty ? (container?.lastPathComponent ?? "") : selected.map { $0.lastPathComponent }.joined(separator: "\n"))
            return
        case .copyDirPath:
            let dirs = selected.map { $0.deletingLastPathComponent().path }
            Clipboard.copy(dirs.isEmpty ? (containerPath ?? "") : dirs.joined(separator: "\n"))
            return

        // 剪切 / 复制文件：只是把选中项记进 App Group 的文件剪贴板，扩展内即时完成，
        // 不唤主程序。真正的搬运发生在「粘贴」时。
        case .cutFiles:
            FileClipboard.put(mode: .cut, paths: paths)
            Log.info("剪切 \(paths.count) 项")
            return
        case .copyFiles:
            FileClipboard.put(mode: .copy, paths: paths)
            Log.info("复制文件 \(paths.count) 项")
            return

        default:
            break
        }

        // 其余重操作 → 写信箱 + 后台唤起主程序执行（openApplication activates=false，不抢焦点）
        let command = Command(action: actionID, paths: paths, containerPath: containerPath, arg: arg)
        Mailbox.send(command)
        AppLauncher.wakeContainerApp()
    }
}

/// 剪贴板小工具（扩展内可用）
enum Clipboard {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        Log.info("扩展写入剪贴板 \(ok ? "成功" : "失败")，长度 \(text.count)")
    }
}

/// 唤起容器主程序，让它去处理信箱里的指令。
enum AppLauncher {
    static func wakeContainerApp() {
        // 主程序已在后台运行时，不要再次 openApplication。
        // 否则 SwiftUI 的设置窗口会被反复拉出来；信箱轮询本身会处理刚写入的命令。
        if !NSRunningApplication.runningApplications(withBundleIdentifier: AppConfig.appBundleID).isEmpty {
            Log.debugFile("container app already running; skip openApplication")
            return
        }
        BackgroundWakeMarker.mark()

        // 扩展 .appex 位于  XXX.app/Contents/PlugIns/FinderExtension.appex
        // 向上三级即为容器 App。
        let appURL = Bundle.main.bundleURL          // .../FinderExtension.appex
            .deletingLastPathComponent()            // .../PlugIns
            .deletingLastPathComponent()            // .../Contents
            .deletingLastPathComponent()            // .../XXX.app

        let config = NSWorkspace.OpenConfiguration()
        config.activates = false        // 后台唤起，不抢焦点
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error = error {
                Log.error("唤起主程序失败: \(error.localizedDescription)")
            }
        }
    }

    /// 兜底通道：当 App Group 信箱不可用时，用自定义 URL Scheme 投递。
    /// 注意：NSWorkspace.open(url) 会激活主程序到前台（会抢焦点），所以仅作 fallback，
    /// 复制类动作绝不要走这里。
    static func runViaURL(_ command: Command) {
        guard let data = try? JSONEncoder().encode(command.paths) else { return }
        var comps = URLComponents()
        comps.scheme = "superrightclick"
        comps.host = "run"
        comps.queryItems = [
            URLQueryItem(name: "action", value: command.action.rawValue),
            URLQueryItem(name: "paths", value: data.base64EncodedString()),
            URLQueryItem(name: "container", value: command.containerPath),
            URLQueryItem(name: "arg", value: command.arg),
        ]
        guard let url = comps.url else { return }
        NSWorkspace.shared.open(url)
    }
}
