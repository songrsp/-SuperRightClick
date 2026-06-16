# ⚡️ 超级右键 (SuperRightClick)

给 macOS 的 Finder 右键菜单加上一堆 Windows 用户熟悉的实用功能：复制路径、剪切/复制/粘贴文件、新建文件、压缩解压、在此打开终端 / VS Code、计算哈希、显示隐藏文件，以及**彻底卸载 .app 并清理 `~/Library` 残余**。

原理与商业软件 iRightMouse 一致：用 **Finder Sync Extension** 注入右键菜单。本项目从零自研、开源（MIT），**不依赖任何破解或付费授权**，欢迎自由使用与二次开发。

![平台](https://img.shields.io/badge/macOS-13%2B-blue) ![语言](https://img.shields.io/badge/Swift-5-orange) ![许可](https://img.shields.io/badge/License-MIT-green)

> 适用：macOS 13+ · Swift 5 · 需要一个 Apple 开发者账号（免费个人账号即可本机自签运行）。
>
> 🤖 想交给编码 Agent（Codex / Claude Code）继续开发？先读 [`AGENTS.md`](AGENTS.md)。

---

## 截图

> _建议在这里放一张右键菜单的截图或 GIF（拖进仓库后改成 `![demo](docs/demo.png)`）。一图胜千言，对工具类项目尤其重要。_

---

## 功能一览

仿 Windows 风格，按场景分组（详见 [`docs/功能清单.md`](docs/功能清单.md)）：

- **复制信息**：复制路径 / 文件名 / 所在目录（在扩展内瞬时完成，不抢焦点）
- **剪切 / 复制 / 粘贴**：Windows 式文件剪贴板——剪切(move) / 复制文件(copy) → 粘贴到任意文件夹，同名自动加后缀不覆盖
- **新建**：txt / Markdown / 文件夹
- **文件管理**：复制到… / 移动到… / 压缩 ZIP / 解压 / 批量重命名 / 移到废纸篓
- **开发者**：在此打开终端 / 用 VS Code 打开 / 复制 SHA256 · MD5
- **仿 Windows 常驻**：显示隐藏文件 / 刷新 / 属性
- **卸载**：右键 `.app` → 彻底卸载并扫描清理残余（移到废纸篓，可后悔）

菜单项是否出现，会按「当前选中内容」+「功能分组开关」动态决定。默认**平铺**进 Finder 原生右键；可在设置里改成收进「⚡️ 超级右键」子菜单。

---

## 为什么是「两个进程」（关键设计）

macOS 的 App 扩展**强制沙盒**，没法随便删 `~/Library`、跑 shell。所以本项目拆成两部分：

| 部分 | 沙盒 | 职责 |
|------|------|------|
| **Finder 扩展** (`FinderExtension.appex`) | 是 | 只负责「出菜单 + 捕获点击」，把指令写进共享信箱 |
| **容器主程序** (`SuperRightClick.app`) | 否 | 常驻后台，轮询信箱，真正执行删除 / 压缩 / 卸载等重操作 |

两者通过 **App Group 共享目录**（一个「信箱」）通信：扩展写 JSON 指令 → 主程序读取执行后删除。复制路径、剪切/复制这类轻操作直接在扩展内完成，不必唤起主程序。详见 [`docs/架构设计.md`](docs/架构设计.md)。

---

## 这个工具要什么权限？（请先读）

它是个会**直接操作你文件系统**的工具，所以坦白讲清楚：

- **主程序不开沙盒**，因为卸载/清理需要访问 `/Applications` 和 `~/Library`。这也意味着它**无法上架 Mac App Store**，只能源码自建或 Developer ID 分发——这是这类工具的通用限制。
- **完全磁盘访问权限**：卸载清理残余、跨目录搬运文件时需要。首次运行会引导你在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里把 `SuperRightClick.app` 加进去。
- **删除一律走废纸篓**：所有删除/卸载操作用 `trashItem`（移到废纸篓）而非永久删除，给你后悔的机会。
- 代码全部开源，你可以自己审计每一个动作的实现都在 [`App/CommandExecutor.swift`](App/CommandExecutor.swift) 和 [`App/UninstallManager.swift`](App/UninstallManager.swift)。

---

## 从源码构建（推荐方式）

这是开源用户的标准路径——用你自己的 Apple 账号本机编译运行，无需公证。

### 前置条件

- macOS 13 或更高、Xcode 15+（含命令行工具 `xcode-select --install`）
- [XcodeGen](https://github.com/yonyz/XcodeGen)：`brew install xcodegen`
- 一个 Apple 开发者账号（免费个人账号即可，签名 7 天过期需重签；付费 $99/年 可生成 Developer ID 长期分发）

### 步骤

```bash
# 0. 安装工程生成器（一次即可）
brew install xcodegen

# 1. 克隆并进入项目
git clone https://github.com/songrsp/-SuperRightClick.git SuperRightClick
cd SuperRightClick

# 2. 填入你自己的 Apple Team ID
#    复制 Local.xcconfig.example 为 Local.xcconfig，并填入你的 10 位 Team ID
#    （在 https://developer.apple.com/account 的 Membership 里可查）
cp Local.xcconfig.example Local.xcconfig
open Local.xcconfig

# 3. 生成 Xcode 工程
./scripts/bootstrap.sh

# 4. 打开并运行
open SuperRightClick.xcodeproj
```

5. 在 Xcode 里选中 `SuperRightClick` scheme → **Run（⌘R）**。首次运行后：
   - 在弹出的设置窗口点 **「打开扩展设置」**，勾选「超级右键扩展」（或系统设置 → 通用 → 登录项与扩展 → 访达扩展）
   - 点 **「打开隐私设置」**，把 `SuperRightClick` 加入「完全磁盘访问权限」，然后完全退出再重开主程序
   - 回到 Finder，右键任意文件/文件夹 → 看到新增的菜单项即成功

构建/签名的更多细节与排错见 [`docs/构建与签名.md`](docs/构建与签名.md)。

---

## 打包成 .dmg 分发

仓库自带 [`scripts/make-dmg.sh`](scripts/make-dmg.sh)，一条命令出 `.dmg`：

```bash
./scripts/make-dmg.sh
```

⚠️ **要给别人用的 dmg 必须签名 + 公证**。因为本 app 非沙盒且带 Finder 扩展，未公证的版本在别人机器上会被 Gatekeeper 拦截、扩展也加载不出来。需要付费 Developer ID 账号，流程与清单见 [`docs/发布-dmg-与公证.md`](docs/发布-dmg-与公证.md)。**纯自用或源码分发不需要这步。**

---

## 二次开发

加一个新右键功能只要三步（详见 [`docs/开发指南-如何添加菜单项.md`](docs/开发指南-如何添加菜单项.md)）：

1. 在 `Shared/Command.swift` 的 `ActionID` 里加一个 case
2. 在 `FinderExtension/MenuBuilder.swift` 里加一个菜单项
3. 在 `App/CommandExecutor.swift` 里加一个处理分支

> ⚠️ 加菜单项时用现成的 `MenuBuilder.item(...)` 即可——菜单载荷靠 `tag` + 进程内登记表传递，**不要回退用 `representedObject` 传 action/arg**：Finder 跨进程复制菜单时 `representedObject` 会丢，点击会收不到载荷。

### 目录结构

```
SuperRightClick/
├── project.yml                 # XcodeGen 配置（工程的「源头」，不手写 .xcodeproj）
├── App/                        # 容器主程序（非沙盒）
│   ├── SuperRightClickApp.swift    # @main 入口 + 信箱轮询
│   ├── CommandExecutor.swift       # 所有动作的真正执行逻辑 ★
│   ├── UninstallManager.swift      # 卸载残余扫描 ★
│   ├── SettingsView.swift / UninstallView.swift / BatchRenameWindow.swift
│   └── Shell.swift / HashUtil.swift
├── FinderExtension/            # Finder Sync 扩展（沙盒）
│   ├── FinderSyncController.swift  # FIFinderSync 子类，菜单点击分发 ★
│   └── MenuBuilder.swift           # 拼装仿 Windows 多级菜单 ★
├── Shared/                     # 两个 target 共用
│   ├── AppConfig.swift             # Bundle ID / App Group 常量
│   ├── Command.swift               # 动作枚举 + 指令信箱 + 文件剪贴板 ★
│   ├── Preferences.swift           # 功能分组开关
│   └── Logger.swift
├── scripts/                    # bootstrap.sh（生成工程）/ make-dmg.sh（打包）
└── docs/                       # 中文文档
```

★ = 二次开发最常改的文件。

---

## 致谢

本项目从零自研，但思路借鉴了这些优秀开源项目，强烈建议对照阅读：

- **[OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal)**（MIT）—— Finder「在此打开终端/编辑器」，可参考其菜单与调起逻辑。
- **[Pearcleaner](https://github.com/alienator88/Pearcleaner)**（fair-code）—— SwiftUI 应用卸载器，残余扫描思路（按 Bundle ID + 应用名扫 `~/Library`）值得借鉴。注意它**不是 MIT**，请参考做法而非照搬代码。

与 iRightMouse 无任何代码/资源关系，仅功能定位相似。

---

## 许可与免责

- 采用 [MIT License](LICENSE)。
- 卸载/清理功能会删文件，本项目默认**移到废纸篓**而非永久删除。但对系统目录操作仍请谨慎，风险自负。
- 本项目仅供学习与个人/团队使用。
