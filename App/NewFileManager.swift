import AppKit

/// 新建文件/文件夹的执行器。
///
/// Finder 扩展只负责展示 `NewFileTemplateStore` 中的模型并传回模板 id；
/// 这里在非沙盒主程序中完成模板复制、冲突命名和 Finder 反馈。
@MainActor
enum NewFileManager {

    static func create(templateID: String, in location: URL?) {
        guard let template = NewFileTemplateStore.template(id: templateID) else {
            Alerts.warn("无法新建", "找不到模板：\(templateID)")
            return
        }
        guard let directory = directory(of: location) else {
            Alerts.warn("无法新建", "目标文件夹无效。")
            return
        }

        let destination = uniqueURL(
            directory: directory,
            baseName: template.baseName,
            fileExtension: normalizedExtension(template.fileExtension),
            isDirectory: template.isDirectory
        )

        do {
            if let source = NewFileTemplateStore.templateURL(for: template),
               FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            } else if template.isDirectory {
                try FileManager.default.createDirectory(
                    at: destination, withIntermediateDirectories: false
                )
            } else {
                guard FileManager.default.createFile(atPath: destination.path, contents: Data())
                else { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            Alerts.warn("新建失败", "无法创建 \(destination.lastPathComponent)：\(error.localizedDescription)")
            Log.error("新建模板失败 \(destination.path)：\(error.localizedDescription)")
            return
        }

        Log.info("新建 \(template.id) → \(destination.path)")
        if Pref.newFileAutoOpen {
            NSWorkspace.shared.open(destination)
        }
        if Pref.newFileAutoReveal {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    private static func normalizedExtension(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        let normalized = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
    }

    private static func directory(of url: URL?) -> URL? {
        guard let url = url else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private static func uniqueURL(directory: URL, baseName: String,
                                  fileExtension: String?, isDirectory: Bool) -> URL {
        let base = baseName.isEmpty ? (isDirectory ? "新建文件夹" : "未命名") : baseName
        func make(_ name: String) -> URL {
            let url = directory.appendingPathComponent(name)
            guard let fileExtension = fileExtension else { return url }
            return url.appendingPathExtension(fileExtension)
        }

        var candidate = make(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(suffix)")
            suffix += 1
        }
        return candidate
    }
}
