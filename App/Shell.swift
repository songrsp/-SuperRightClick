import Foundation

/// 在「非沙盒」主程序里跑子进程的封装。扩展里不要用（沙盒会拦）。
enum Shell {

    @discardableResult
    static func run(_ launchPath: String,
                    _ args: [String],
                    cwd: URL? = nil) -> (status: Int32, out: String, err: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        if let cwd = cwd { task.currentDirectoryURL = cwd }

        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return (-1, "", "启动失败: \(error.localizedDescription)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    /// 跑一段 AppleScript（用于「属性」面板、与 Finder 交互等）
    @discardableResult
    static func osascript(_ script: String) -> (status: Int32, out: String, err: String) {
        run("/usr/bin/osascript", ["-e", script])
    }
}
