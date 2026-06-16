import Foundation
import os

/// 轻量日志封装。用 `log("...")` 即可，Console.app 里按 subsystem 过滤。
enum Log {
    private static let logger = os.Logger(subsystem: AppConfig.appBundleID, category: "general")

    static func info(_ msg: String)  { logger.info("\(msg, privacy: .public)") }
    static func error(_ msg: String) { logger.error("\(msg, privacy: .public)") }

    /// 调试日志落到 App Group 共享容器，扩展(沙盒)与主程序都能写、都能看。
    /// 路径：~/Library/Group Containers/group.com.team.superrightclick/debug.log
    /// 看日志：tail -f "$(echo ~)/Library/Group Containers/group.com.team.superrightclick/debug.log"
    static func debugFile(_ msg: String) {
        guard let url = debugLogURL else { return }
        let line = "\(Date()) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// App Group 容器根目录下的 debug.log。沙盒扩展无法写 /tmp，这里用共享容器。
    static var debugLogURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupID)?
            .appendingPathComponent("debug.log")
    }
}
