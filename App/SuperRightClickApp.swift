import SwiftUI

/// 容器主程序入口。它常驻后台，轮询 App Group 信箱，把扩展投递的指令逐条执行。
@main
struct SuperRightClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("超级右键") {
            SettingsView()
                .frame(width: 560, height: 560)
        }
        .windowResizability(.contentSize)
    }
}

/// 负责：① 启动后开始轮询信箱  ② 处理自定义 URL Scheme（备用通道）
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var timer: Timer?
    private var launchedForBackgroundCommand = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("主程序启动")
        launchedForBackgroundCommand = BackgroundWakeMarker.consume()
        processMailbox()
        if launchedForBackgroundCommand {
            closeSettingsWindowsSoon()
        }
        // 0.5s 轮询信箱。也可改用 FSEvents 监听目录，这里用定时器最直观、最稳。
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.processMailbox()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        processMailbox()   // 被扩展唤起到前台时立即处理一次
        if launchedForBackgroundCommand {
            closeSettingsWindowsSoon()
        }
    }

    /// 处理 superrightclick://run?action=...&paths=<base64 json> 这类备用调用
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "superrightclick" {
            if let cmd = URLCommandParser.parse(url) {
                Task { @MainActor in CommandExecutor.execute(cmd) }
            }
        }
    }

    @MainActor
    private func processMailbox() {
        for (cmd, file) in Mailbox.readAll() {
            Log.info("信箱收到 \(cmd.action.rawValue)，路径 \(cmd.paths.count) 个，容器 \(cmd.containerPath ?? "nil")")
            CommandExecutor.execute(cmd)
            Mailbox.remove(file)
            Log.info("信箱完成并删除 \(file.lastPathComponent)")
        }
    }

    @MainActor
    private func closeSettingsWindowsSoon() {
        DispatchQueue.main.async {
            NSApp.windows
                .filter { $0.title == "超级右键" }
                .forEach { $0.close() }
            NSApp.hide(nil)
        }
    }
}

/// 备用通道：把 URL 解析成 Command（主通道是 App Group 信箱）。
enum URLCommandParser {
    static func parse(_ url: URL) -> Command? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let actionRaw = comps.queryItems?.first(where: { $0.name == "action" })?.value,
              let action = ActionID(rawValue: actionRaw) else { return nil }
        let pathsB64 = comps.queryItems?.first(where: { $0.name == "paths" })?.value
        var paths: [String] = []
        if let b64 = pathsB64, let data = Data(base64Encoded: b64),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            paths = arr
        }
        let container = comps.queryItems?.first(where: { $0.name == "container" })?.value
        let arg = comps.queryItems?.first(where: { $0.name == "arg" })?.value
        return Command(action: action, paths: paths, containerPath: container ?? paths.first, arg: arg)
    }
}
