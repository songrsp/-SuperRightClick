import AppKit
import SwiftUI

/// 一条「残余文件」候选项
struct ResidualItem: Identifiable {
    let id = UUID()
    let url: URL
    let bytes: Int64
    var include: Bool = true          // 是否纳入删除（默认勾选）
    let isAppBundle: Bool             // 是不是 .app 本体

    var displayPath: String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 卸载流程总控：扫描残余 → 弹窗确认 → 移到废纸篓。
@MainActor
final class UninstallManager: ObservableObject {
    static let shared = UninstallManager()

    @Published var appName: String = ""
    @Published var bundleID: String = ""
    @Published var items: [ResidualItem] = []
    @Published var scanning = false

    private var window: NSWindow?

    func startUninstall(appURL: URL) {
        appName = appURL.deletingPathExtension().lastPathComponent
        bundleID = Self.bundleID(of: appURL) ?? ""
        items = []
        scanning = true
        showWindow()

        // 后台扫描，避免卡 UI
        let name = appName, bid = bundleID
        DispatchQueue.global(qos: .userInitiated).async {
            var found = Self.scanResiduals(appName: name, bundleID: bid)
            // 把 .app 本体放在最前面
            let appBytes = Self.size(of: appURL)
            found.insert(ResidualItem(url: appURL, bytes: appBytes, include: true, isAppBundle: true), at: 0)
            let foundItems = found
            DispatchQueue.main.async {
                self.items = foundItems
                self.scanning = false
            }
        }
    }

    /// 用户确认后执行：勾选的项统统移到废纸篓（比直接删除安全，可后悔）。
    func performDeletion() {
        var failed: [String] = []
        for item in items where item.include {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            } catch {
                failed.append(item.displayPath)
            }
        }
        window?.close()
        if failed.isEmpty {
            Alerts.info("卸载完成", "「\(appName)」及所选残余已移到废纸篓。")
        } else {
            Alerts.warn("部分文件未能删除",
                        "可能需要在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中授权本程序。\n\n失败：\n" + failed.joined(separator: "\n"))
        }
    }

    func cancel() { window?.close() }

    // MARK: - 扫描逻辑（思路参考 AppCleaner / Pearcleaner：按 Bundle ID 与应用名在常见目录中匹配）

    nonisolated static func scanResiduals(appName: String, bundleID: String) -> [ResidualItem] {
        let home = NSHomeDirectory()
        let searchDirs = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Caches",
            "\(home)/Library/Preferences",
            "\(home)/Library/Logs",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/Cookies",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Preferences/ByHost",
            "\(home)/Library/Application Support/CrashReporter",
            "/Library/Application Support",
            "/Library/Caches",
            "/Library/Preferences",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]

        // 归一化用于匹配的关键词
        let nameKey = appName.lowercased().replacingOccurrences(of: " ", with: "")
        let bidLower = bundleID.lowercased()

        var results: [ResidualItem] = []
        let fm = FileManager.default
        for dir in searchDirs {
            guard let children = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for child in children {
                let full = "\(dir)/\(child)"
                let lc = child.lowercased()
                let nameMatch = !nameKey.isEmpty && lc.replacingOccurrences(of: " ", with: "").contains(nameKey)
                let bidMatch = !bidLower.isEmpty && lc.contains(bidLower)
                let plistMatch = isLaunchPlist(full) && launchPlist(at: full, matches: appName, bundleID: bundleID)
                if nameMatch || bidMatch || plistMatch {
                    let url = URL(fileURLWithPath: full)
                    results.append(ResidualItem(url: url, bytes: size(of: url), include: true, isAppBundle: false))
                }
            }
        }
        // 去重 + 按体积排序
        var seen = Set<String>()
        return results
            .filter { seen.insert($0.url.path).inserted }
            .sorted { $0.bytes > $1.bytes }
    }

    nonisolated private static func isLaunchPlist(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".plist") &&
            (lower.contains("/library/launchagents/") || lower.contains("/library/launchdaemons/"))
    }

    nonisolated private static func launchPlist(at path: String, matches appName: String, bundleID: String) -> Bool {
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else { return false }
        let fields = [
            dict["Program"] as? String,
            (dict["ProgramArguments"] as? [String])?.joined(separator: " "),
            dict["Label"] as? String,
        ].compactMap { $0?.lowercased() }

        let normalizedName = appName.lowercased().replacingOccurrences(of: " ", with: "")
        let normalizedFields = fields.map { $0.replacingOccurrences(of: " ", with: "") }
        let nameMatch = !normalizedName.isEmpty && normalizedFields.contains { $0.contains(normalizedName) }
        let bundleMatch = !bundleID.isEmpty && fields.contains { $0.contains(bundleID.lowercased()) }
        return nameMatch || bundleMatch
    }

    nonisolated static func bundleID(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    nonisolated static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        if let en = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in en {
                if let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   v.isRegularFile == true {
                    total += Int64(v.fileSize ?? 0)
                }
            }
        } else if let v = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            total = Int64(v.fileSize ?? 0)
        }
        return total
    }

    // MARK: - 窗口

    private func showWindow() {
        if window == nil {
            let view = UninstallView().environmentObject(self)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "彻底卸载"
            win.setContentSize(NSSize(width: 560, height: 520))
            win.styleMask = [.titled, .closable]
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
