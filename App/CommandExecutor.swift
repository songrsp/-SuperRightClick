import AppKit

/// 主程序里真正执行各类动作的地方。所有需要文件系统 / 子进程 / UI 的操作都在这里。
@MainActor
enum CommandExecutor {

    static func execute(_ command: Command) {
        let urls = command.paths.map { URL(fileURLWithPath: $0) }
        let containerURL = command.containerPath.map { URL(fileURLWithPath: $0) }
        Log.info("执行 \(command.action.rawValue)")

        switch command.action {

        // —— 复制类（理论上扩展已处理，这里兜底）——
        case .copyPath:    Pasteboard.set(command.paths.isEmpty ? (command.containerPath ?? "") : command.paths.joined(separator: "\n"))
        case .copyName:    Pasteboard.set(urls.map { $0.lastPathComponent }.joined(separator: "\n"))
        case .copyDirPath: Pasteboard.set(urls.isEmpty ? (command.containerPath ?? "") : urls.map { $0.deletingLastPathComponent().path }.joined(separator: "\n"))

        // —— 新建 ——
        case .newFileTxt:      newFile(ext: "txt", in: containerURL ?? urls.first)
        case .newFileMarkdown: newFile(ext: "md",  in: containerURL ?? urls.first)
        case .newFolder:       newFolder(in: containerURL ?? urls.first)

        // —— 文件管理 ——
        case .moveToTrash:   trash(urls)
        case .compress:      compress(urls)
        case .decompress:    decompress(urls)
        case .copyToFolder:  pickFolderThen(urls) { copy($0, to: $1) }
        case .moveToFolder:  pickFolderThen(urls) { move($0, to: $1) }
        case .batchRename:   BatchRenameWindow.show(for: urls)

        // —— 开发者 ——
        case .openInTerminal: openTerminal(at: containerURL ?? urls.first?.deletingLastPathComponent())
        case .openInVSCode:   openVSCode(urls.isEmpty ? [containerURL].compactMap { $0 } : urls)
        case .openWith:       openWith(urls.isEmpty ? [containerURL].compactMap { $0 } : urls, appPath: command.arg)
        case .copyHashSHA256: copyHash(urls, algo: .sha256)
        case .copyHashMD5:    copyHash(urls, algo: .md5)

        // —— 仿 Windows ——
        case .toggleHiddenFiles: toggleHidden()
        case .refreshFinder:     Shell.run("/usr/bin/killall", ["Finder"])
        case .showProperties:    showInfo(urls)

        // —— 卸载 ——
        case .uninstallApp:
            for app in urls where app.pathExtension == "app" {
                UninstallManager.shared.startUninstall(appURL: app)
            }
        }
    }

    // MARK: - 新建

    private static func newFile(ext: String, in dir: URL?) {
        guard let dir = directory(of: dir) else { return }
        let url = uniqueURL(dir: dir, base: "未命名", ext: ext)
        let ok = FileManager.default.createFile(atPath: url.path, contents: Data())
        Log.info("新建文件 \(url.path) \(ok ? "成功" : "失败")")
        revealInFinder(url)
    }

    private static func newFolder(in dir: URL?) {
        guard let dir = directory(of: dir) else { return }
        let url = uniqueURL(dir: dir, base: "新建文件夹", ext: nil)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        revealInFinder(url)
    }

    // MARK: - 文件管理

    private static func trash(_ urls: [URL]) {
        for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
    }

    private static func compress(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let parent = first.deletingLastPathComponent()
        if urls.count == 1 {
            let dst = uniqueURL(dir: parent, base: first.deletingPathExtension().lastPathComponent, ext: "zip")
            Shell.run("/usr/bin/zip", ["-r", "-q", dst.path, first.lastPathComponent], cwd: parent)
        } else {
            let dst = uniqueURL(dir: parent, base: "归档", ext: "zip")
            let names = urls.map { $0.lastPathComponent }
            Shell.run("/usr/bin/zip", ["-r", "-q", dst.path] + names, cwd: parent)
        }
    }

    private static func decompress(_ urls: [URL]) {
        for u in urls {
            let dst = u.deletingLastPathComponent()
            switch u.pathExtension.lowercased() {
            case "zip":
                Shell.run("/usr/bin/ditto", ["-x", "-k", u.path, dst.path])
            case "tar", "gz", "tgz":
                Shell.run("/usr/bin/tar", ["-xf", u.path, "-C", dst.path])
            default:
                Shell.run("/usr/bin/open", [u.path])   // 其它格式交给系统/第三方解压
            }
        }
    }

    private static func copy(_ urls: [URL], to dest: URL) {
        for u in urls {
            let target = uniqueURL(dir: dest, base: u.deletingPathExtension().lastPathComponent, ext: u.pathExtension.isEmpty ? nil : u.pathExtension)
            try? FileManager.default.copyItem(at: u, to: target)
        }
    }

    private static func move(_ urls: [URL], to dest: URL) {
        for u in urls {
            let target = dest.appendingPathComponent(u.lastPathComponent)
            try? FileManager.default.moveItem(at: u, to: target)
        }
    }

    // MARK: - 开发者

    private static func openTerminal(at dir: URL?) {
        guard let dir = dir else { return }
        Shell.run("/usr/bin/open", ["-a", "Terminal", dir.path])
    }

    private static func openVSCode(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // 优先用已安装的 VS Code；失败则提示。
        let r = Shell.run("/usr/bin/open", ["-a", "Visual Studio Code"] + urls.map { $0.path })
        if r.status != 0 {
            Alerts.warn("未找到 VS Code", "请先安装 Visual Studio Code，或在设置里改成你常用的编辑器。")
        }
    }

    /// 用指定 App 打开选中文件（菜单「打开方式」里动态列出的 App）。
    private static func openWith(_ urls: [URL], appPath: String?) {
        guard let appPath = appPath, !urls.isEmpty else { return }
        let appURL = URL(fileURLWithPath: appPath)
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: cfg) { _, error in
            if let error = error {
                Log.error("openWith 失败: \(error.localizedDescription)")
            }
        }
    }

    enum HashAlgo { case sha256, md5 }
    private static func copyHash(_ urls: [URL], algo: HashAlgo) {
        var lines: [String] = []
        for u in urls {
            let h = (algo == .sha256 ? HashUtil.sha256(of: u.path) : HashUtil.md5(of: u.path)) ?? "（无法读取）"
            lines.append("\(h)  \(u.lastPathComponent)")
        }
        Pasteboard.set(lines.joined(separator: "\n"))
        Alerts.info("已复制哈希", lines.joined(separator: "\n"))
    }

    // MARK: - 仿 Windows

    private static func toggleHidden() {
        let read = Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"])
        let cur = read.out.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let now = (cur == "1" || cur == "YES" || cur == "TRUE")
        let next = now ? "NO" : "YES"
        Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", next])
        Shell.run("/usr/bin/killall", ["Finder"])
    }

    private static func showInfo(_ urls: [URL]) {
        guard let u = urls.first else { return }
        // 用 AppleScript 打开 Finder 的「显示简介」窗口
        let script = """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(u.path)" as alias)
        end tell
        """
        Shell.osascript(script)
    }

    // MARK: - 工具

    private static func directory(of url: URL?) -> URL? {
        guard let url = url else { return nil }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private static func uniqueURL(dir: URL, base: String, ext: String?) -> URL {
        func make(_ name: String) -> URL {
            ext == nil ? dir.appendingPathComponent(name)
                       : dir.appendingPathComponent(name).appendingPathExtension(ext!)
        }
        var candidate = make(base)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(i)")
            i += 1
        }
        return candidate
    }

    private static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func pickFolderThen(_ urls: [URL], _ then: @escaping ([URL], URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择目标文件夹"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let dest = panel.url {
            then(urls, dest)
        }
    }
}

/// 剪贴板（主程序侧）
enum Pasteboard {
    static func set(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        Log.info("写入剪贴板 \(ok ? "成功" : "失败")，长度 \(text.count)")
    }
}

/// 简单弹窗
enum Alerts {
    static func info(_ title: String, _ msg: String) { show(title, msg, .informational) }
    static func warn(_ title: String, _ msg: String) { show(title, msg, .warning) }
    private static func show(_ title: String, _ msg: String, _ style: NSAlert.Style) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.alertStyle = style
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
