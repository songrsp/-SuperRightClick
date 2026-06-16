import Foundation

/// 全局共享常量。App 与 Finder 扩展两个 target 都会编译到这份代码。
/// 改 Bundle ID / App Group 时，记得同步改 project.yml 与各 entitlements。
enum AppConfig {

    /// 容器主程序 Bundle ID
    static let appBundleID = "com.team.superrightclick"

    /// Finder 扩展 Bundle ID
    static let extensionBundleID = "com.team.superrightclick.FinderExtension"

    /// App Group —— 扩展与主程序之间共享「指令信箱」靠它。
    /// 注意：两个 target 的 entitlements 必须都声明同一个 App Group，且同属一个 Team。
    static let appGroupID = "group.com.team.superrightclick"

    /// 信箱目录（位于 App Group 共享容器内）。
    /// 扩展把要执行的指令写成 json 丢进来，主程序轮询读取并执行后删除。
    static var mailboxURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let box = container.appendingPathComponent("mailbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        return box
    }
}
