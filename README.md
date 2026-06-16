# ⚡️ 超级右键 (SuperRightClick)

一个 macOS 的"超级右键"工具，给 Finder 的右键菜单加上一堆好用的功能 —— 复制路径、新建文件、压缩解压、在此打开终端 / VS Code、计算哈希、显示隐藏文件，以及**彻底卸载 .app 并清理 `~/Library` 残余**。

原理与商业软件 iRightMouse 一致：用 **Finder Sync Extension** 注入右键菜单。本项目为团队内部自建版，**不依赖任何破解/ 付费授权**，源码可自由二次开发。

> 适用：macOS 13+ · Swift 5 · 需要 Apple 开发者账号（哪怕是免费账号也能本机自签调试）
>
> 🤖 **要交给编码 Agent（Codex / Claude Code）继续做？** 先读 [`AGENTS.md`](AGENTS.md) 和 [`docs/验收清单.md`](docs/验收清单.md)。

---

## 为什么这样设计（关键约束）

macOS 的 App 扩展**强制沙盒**，没法随便删 `~/Library`、跑 shell。所以本项目拆成两个部分：

| 部分 | 沙盒 | 职责 |
|------|------|------|
| **Finder 扩展** (`FinderExtension.appex`) | 是 | 只负责"出菜单 + 捕获点击"，把指令写进共享信箱 |
| **容器主程序** (`SuperRightClick.app`) | 否 | 常驻后台，轮询信箱，真正执行删除 / 压缩 / 卸载等重操作 |

两者通过 **App Group 共享目录**（一个"信箱"）通信：扩展写 JSON 指令 → 主程序读取执行后删除。复制路径这类轻操作直接在扩展内完成，不必唤起主程序。

> 因为主程序需要访问 `/Applications` 和 `~/Library`，它**不能开沙盒**，因此只能用 Developer ID 在团队内分发，**无法上架 Mac App Store**。这是这类工具的通用限制。

详见 [`docs/架构设计.md`](docs/架构设计.md)。

---

## 快速开始（5 步）

```bash
# 0. 安装工程生成器（一次即可）
brew install xcodegen

# 1. 进入项目目录
cd SuperRightClick

# 2. 改成你的 Apple Team ID
#    打开 project.yml，把 DEVELOPMENT_TEAM 改成你的 10 位 Team ID
#    （在 https://developer.apple.com/account 的 Membership 里可查）

# 3. 生成 Xcode 工程
xcodegen generate

# 4. 打开
open SuperRightClick.xcodeproj
```

5. 在 Xcode 里选中 `SuperRightClick` scheme → **Run（⌘R）**。首次运行后：
   - 在弹出的设置窗口里点 **"打开扩展设置"**，勾选「超级右键扩展」
   - 点 **"打开隐私设置"**，把 `SuperRightClick` 加入「完全磁盘访问权限」
   - 回到 Finder，右键任意文件/文件夹 → 看到 **⚡️ 超级右键** 子菜单即成功

> 没有付费开发者账号也能调试：Xcode 用免费个人 Team 自签即可在本机跑，只是签名 7 天过期、不能分发。团队分发见 [`docs/团队分发.md`](docs/团队分发.md)。

---

## 目录结构

```
SuperRightClick/
├── project.yml                 # XcodeGen 配置（工程的"源头"，不手写 .xcodeproj）
├── App/                        # 容器主程序（非沙盒）
│   ├── SuperRightClickApp.swift    # @main 入口 + 信箱轮询
│   ├── SettingsView.swift          # 引导/设置界面
│   ├── CommandExecutor.swift       # 所有动作的真正执行逻辑 ★
│   ├── UninstallManager.swift      # 卸载残余扫描 ★
│   ├── UninstallView.swift         # 卸载确认窗口
│   ├── BatchRenameWindow.swift     # 批量重命名窗口
│   ├── Shell.swift / HashUtil.swift
│   ├── Info.plist / App.entitlements
├── FinderExtension/            # Finder Sync 扩展（沙盒）
│   ├── FinderSyncController.swift  # FIFinderSync 子类，菜单点击分发 ★
│   ├── MenuBuilder.swift           # 拼装仿 Windows 多级菜单 ★
│   ├── Info.plist / FinderExtension.entitlements
├── Shared/                     # 两个 target 共用
│   ├── AppConfig.swift             # Bundle ID / App Group 常量
│   ├── Command.swift               # 动作枚举 + 指令信箱 ★
│   └── Logger.swift
└── docs/                       # 中文文档
    ├── 架构设计.md
    ├── 构建与签名.md
    ├── 功能清单.md
    ├── 开发指南-如何添加菜单项.md
    └── 团队分发.md
```

★ = 二次开发最常改的文件。

---

## 内置功能一览

仿 Windows 风格，按场景分组（详见 [`docs/功能清单.md`](docs/功能清单.md)）：

- **复制信息**：复制路径 / 文件名 / 所在目录
- **新建**：txt / Markdown / 文件夹
- **文件管理**：复制到… / 移动到… / 压缩 ZIP / 解压 / 批量重命名 / 移到废纸篓
- **开发者**：在此打开终端 / 用 VS Code 打开 / 复制 SHA256 · MD5
- **仿 Windows 常驻**：显示隐藏文件 / 刷新 / 属性
- **卸载**：右键 `.app` → 彻底卸载并扫描清理残余（移到废纸篓，可后悔）

---

## 想做二次开发？

加一个新右键功能只要三步（详见 [`docs/开发指南-如何添加菜单项.md`](docs/开发指南-如何添加菜单项.md)）：

1. 在 `Shared/Command.swift` 的 `ActionID` 里加一个 case
2. 在 `FinderExtension/MenuBuilder.swift` 里加一个菜单项
3. 在 `App/CommandExecutor.swift` 里加一个处理分支

---

## 参考的开源项目

本项目是从零自研，但思路借鉴了这些优秀开源项目，强烈建议对照阅读：

- **[OpenInTerminal](https://github.com/Ji4n1ng/OpenInTerminal)**（MIT）—— Finder 工具栏/右键"在此打开终端/编辑器"，可直接参考其菜单与调起逻辑。
- **[Pearcleaner](https://github.com/alienator88/Pearcleaner)**（source-available / fair-code）—— SwiftUI 写的应用卸载器，残余扫描思路（按 Bundle ID + 应用名扫 `~/Library`）值得借鉴。注意它**不是 MIT**，团队商用前请阅读其许可证，建议参考做法而非照搬代码。

---

## 许可与免责

- 卸载/清理功能会删文件，本项目默认**移到废纸篓**而非永久删除，给你后悔的机会。但仍请谨慎，对系统目录操作风险自负。
- 本项目仅供学习与团队内部使用。
