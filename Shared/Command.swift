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
