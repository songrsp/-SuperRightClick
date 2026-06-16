import Foundation

/// 所有右键动作的唯一标识。扩展用它发指令，主程序用它分发执行。
/// 新增功能时：在这里加一个 case → 在 MenuBuilder 里加菜单项 → 在 CommandExecutor 里加处理分支。
enum ActionID: String, Codable, CaseIterable {

    // —— 路径 / 文件信息（多数可在扩展内就地完成，无需主程序）——
    case copyPath          // 复制完整路径
    case copyName          // 复制文件名
    case copyDirPath       // 复制所在文件夹路径

    // —— 文件管理增强 ——
    case newFileTxt        // 在此新建 .txt
    case newFileMarkdown   // 在此新建 .md
    case newFolder         // 在此新建文件夹
    case moveToTrash       // 移到废纸篓
    case compress          // 压缩为 zip
    case decompress        // 解压
    case copyToFolder      // 复制到…（弹文件夹选择）
    case moveToFolder      // 移动到…（弹文件夹选择）
    case batchRename       // 批量重命名（弹窗）

    // —— Windows 式 剪切 / 复制 / 粘贴（自建文件剪贴板，见 FileClipboard）——
    case cutFiles          // 剪切：把选中项记入剪贴板(move 模式)，扩展内即时完成
    case copyFiles         // 复制文件：把选中项记入剪贴板(copy 模式)，扩展内即时完成
    case pasteHere         // 粘贴到此处：主程序按剪贴板 move/copy 进当前文件夹

    // —— 打开方式 ——
    case openInTerminal    // 在此打开终端
    case openInVSCode      // 用 VS Code 打开
    case openWith          // 用指定 App 打开（App 路径放在 Command.arg）

    // —— 开发者工具 ——
    case copyHashSHA256    // 计算并复制 SHA256
    case copyHashMD5       // 计算并复制 MD5

    // —— 仿 Windows ——
    case toggleHiddenFiles // 显示/隐藏隐藏文件
    case refreshFinder     // 刷新（重启 Finder）
    case showProperties    // 属性（文件信息面板）

    // —— 卸载并清理残余 ——
    case uninstallApp      // 彻底卸载选中的 .app（扫描残余 → 确认 → 删除）
}

/// 一条待执行指令：动作 + 目标路径列表。
struct Command: Codable {
    let id: String                 // 指令唯一 id（也用作信箱文件名）
    let action: ActionID
    let paths: [String]            // 选中项的绝对路径
    let containerPath: String?     // 当前所在文件夹（右键空白处时有用）
    let arg: String?               // 附加参数（如 openWith 的目标 App 路径）
    let createdAt: Date

    init(action: ActionID, paths: [String], containerPath: String? = nil, arg: String? = nil) {
        self.id = UUID().uuidString
        self.action = action
        self.paths = paths
        self.containerPath = containerPath
        self.arg = arg
        self.createdAt = Date()
    }
}

/// 指令信箱：扩展 write，主程序 readAll + remove。
enum Mailbox {

    static func send(_ command: Command) {
        guard let box = AppConfig.mailboxURL else { return }
        let file = box.appendingPathComponent("\(command.id).json")
        do {
            let data = try JSONEncoder.iso.encode(command)
            try data.write(to: file, options: .atomic)
        } catch {
            NSLog("[SuperRightClick] 写信箱失败: \(error)")
        }
    }

    /// 读取所有待处理指令（按时间排序），返回 (命令, 文件URL) 以便处理后删除。
    static func readAll() -> [(command: Command, file: URL)] {
        guard let box = AppConfig.mailboxURL else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: box, includingPropertiesForKeys: nil)) ?? []
        var result: [(Command, URL)] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let cmd = try? JSONDecoder.iso.decode(Command.self, from: data) {
                result.append((cmd, url))
            }
        }
        return result.sorted { $0.0.createdAt < $1.0.createdAt }
    }

    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }
}

/// 文件剪贴板：Windows 式「剪切 / 复制 → 粘贴」。
///
/// 和系统 NSPasteboard 无关——macOS Finder 没有「剪切文件」的概念，所以我们自己在
/// App Group 容器根写一个 `clipboard.json` 记录「待粘贴的源路径 + 模式」。
/// 扩展(沙盒)负责写(剪切/复制即时完成)，主程序(非沙盒)负责粘贴时真正搬运文件。
enum FileClipMode: String, Codable {
    case cut    // 粘贴=move，完成后清空剪贴板
    case copy   // 粘贴=copy，保留剪贴板可连续粘贴
}

struct FileClip: Codable {
    let mode: FileClipMode
    let paths: [String]
    let createdAt: Date
}

enum FileClipboard {

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)?
            .appendingPathComponent("clipboard.json")
    }

    /// 写入剪贴板（覆盖旧内容）。空路径不写。
    static func put(mode: FileClipMode, paths: [String]) {
        guard let url = fileURL, !paths.isEmpty else { return }
        let clip = FileClip(mode: mode, paths: paths, createdAt: Date())
        do {
            let data = try JSONEncoder.iso.encode(clip)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[SuperRightClick] 写文件剪贴板失败: \(error)")
        }
    }

    static func get() -> FileClip? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso.decode(FileClip.self, from: data)
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 当前待粘贴项数（菜单用来显示「粘贴 N 项」并决定是否出现该项）。
    static var count: Int { Self.get()?.paths.count ?? 0 }
}

/// 扩展后台唤醒主程序时写一个短暂标记。
///
/// SwiftUI 的 `WindowGroup` 默认会在 App 启动时打开设置窗口；这对用户主动打开 App 是好事，
/// 但 Finder 扩展只是想让主程序在后台处理信箱。用这个标记区分两种启动方式。
enum BackgroundWakeMarker {
    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)?
            .appendingPathComponent("background-wake")
    }

    static func mark() {
        guard let url = fileURL else { return }
        try? "1".write(to: url, atomically: true, encoding: .utf8)
    }

    static func consume() -> Bool {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return false }
        try? FileManager.default.removeItem(at: url)
        return true
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
