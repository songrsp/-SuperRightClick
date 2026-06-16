import Foundation

/// 用户偏好，存在 App Group 共享 UserDefaults 里，扩展与主程序都能读。
/// 设置页(主程序)改 → MenuBuilder(扩展)下次出菜单即生效。
enum Pref {

    /// 共享存储。App Group 不可用时退回标准域，保证不崩。
    static let store: UserDefaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard

    /// 各功能分组的开关 key（默认全开）。
    enum Key {
        static let groupOpenWith   = "grp.openWith"    // 打开方式
        static let groupCopyInfo   = "grp.copyInfo"    // 复制信息
        static let groupNewItems   = "grp.newItems"    // 新建
        static let groupFileOps    = "grp.fileOps"     // 文件操作
        static let groupDeveloper  = "grp.developer"   // 开发者(哈希)
        static let groupWindows    = "grp.windows"     // 仿 Windows
        static let groupUninstall  = "grp.uninstall"   // 卸载
        static let useSubmenu      = "ui.useSubmenu"   // 收进 ⚡️ 超级右键 子菜单 vs 平铺
    }

    /// 读 bool，未设置过返回默认值（分组默认开，子菜单默认关=平铺）。
    static func bool(_ key: String, default def: Bool) -> Bool {
        store.object(forKey: key) == nil ? def : store.bool(forKey: key)
    }

    // 便捷访问器（MenuBuilder 用）
    static var openWith:  Bool { bool(Key.groupOpenWith,  default: true) }
    static var copyInfo:  Bool { bool(Key.groupCopyInfo,  default: true) }
    static var newItems:  Bool { bool(Key.groupNewItems,  default: true) }
    static var fileOps:   Bool { bool(Key.groupFileOps,   default: true) }
    static var developer: Bool { bool(Key.groupDeveloper, default: true) }
    static var windows:   Bool { bool(Key.groupWindows,   default: true) }
    static var uninstall: Bool { bool(Key.groupUninstall, default: true) }
    static var useSubmenu: Bool { bool(Key.useSubmenu,    default: false) }
}
