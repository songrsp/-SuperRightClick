import Foundation

/// 新建菜单使用的模板模型。
///
/// 该模型由 Finder 扩展和主程序共同读取；模板文件本身放在 App Group
/// 容器或用户配置的路径中，命令只传稳定的 `id`，不把模板详情塞进 Command。
struct NewFileTemplate: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let baseName: String
    let fileExtension: String?
    let iconName: String?
    let menuGroup: String
    let templatePath: String?
    let isDirectory: Bool
    let enabled: Bool

    init(id: String, displayName: String, baseName: String,
         fileExtension: String?, iconName: String?, menuGroup: String,
         templatePath: String?, isDirectory: Bool, enabled: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.baseName = baseName
        self.fileExtension = fileExtension
        self.iconName = iconName
        self.menuGroup = menuGroup
        self.templatePath = templatePath
        self.isDirectory = isDirectory
        self.enabled = enabled
    }

    /// 兼容用户手写的较短 JSON 配置：缺失字段使用安全默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        baseName = try c.decodeIfPresent(String.self, forKey: .baseName) ?? "未命名"
        fileExtension = try c.decodeIfPresent(String.self, forKey: .fileExtension)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName)
        menuGroup = try c.decodeIfPresent(String.self, forKey: .menuGroup) ?? "新建"
        templatePath = try c.decodeIfPresent(String.self, forKey: .templatePath)
        isDirectory = try c.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

enum NewFileTemplateID {
    static let text = "builtin.text"
    static let markdown = "builtin.markdown"
    static let folder = "builtin.folder"
}

/// App Group 中的模板清单。
///
/// 自定义模板可写入 `new-file-templates.json`。清单不存在或无法解码时，
/// 仍返回内置的空模板，保证原有 txt/Markdown/文件夹功能可用。
enum NewFileTemplateStore {

    static let builtIns: [NewFileTemplate] = [
        NewFileTemplate(
            id: NewFileTemplateID.text,
            displayName: "文本文件 (.txt)", baseName: "未命名",
            fileExtension: "txt", iconName: "doc.text", menuGroup: "新建",
            templatePath: nil, isDirectory: false
        ),
        NewFileTemplate(
            id: NewFileTemplateID.markdown,
            displayName: "Markdown (.md)", baseName: "未命名",
            fileExtension: "md", iconName: "doc.richtext", menuGroup: "新建",
            templatePath: nil, isDirectory: false
        ),
        NewFileTemplate(
            id: NewFileTemplateID.folder,
            displayName: "文件夹", baseName: "新建文件夹",
            fileExtension: nil, iconName: "folder", menuGroup: "新建",
            templatePath: nil, isDirectory: true
        ),
    ]

    static var all: [NewFileTemplate] {
        var result = builtIns
        guard let url = configURL,
              let data = try? Data(contentsOf: url),
              let custom = try? JSONDecoder().decode([NewFileTemplate].self, from: data)
        else { return result }

        var indexByID = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.id, $0.offset) })
        for template in custom {
            if let index = indexByID[template.id] {
                result[index] = template
            } else {
                indexByID[template.id] = result.count
                result.append(template)
            }
        }
        return result
    }

    static var enabled: [NewFileTemplate] {
        all.filter { $0.enabled }
    }

    static func template(id: String) -> NewFileTemplate? {
        all.first { $0.id == id }
    }

    static func templateURL(for template: NewFileTemplate) -> URL? {
        guard let raw = template.templatePath, !raw.isEmpty else { return nil }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        return appGroupURL?.appendingPathComponent(raw)
    }

    private static var appGroupURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConfig.appGroupID
        )
    }

    private static var configURL: URL? {
        appGroupURL?.appendingPathComponent("new-file-templates.json")
    }
}
