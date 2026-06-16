# AGENTS.md —— 给编码 Agent 的交接说明

> 本文件是给自动化编码工具（Codex / Claude Code 等）读的。人看的入口在 [README.md](README.md)。

## 你的任务

这是一个 **macOS「超级右键」工具**（iRightMouse 自建替代）的脚手架，源码与文档已就绪，但**尚未在真机 Xcode 上编译过**。你的工作是：

1. 在 macOS 上把它**编译通过、能跑起来**；
2. 修掉所有编译/链接/签名错误（重点见 [`docs/验收清单.md`](docs/验收清单.md) 的"排雷点"）；
3. 跑通"右键菜单 → 主程序执行"的完整链路；
4. 补完 [`docs/验收清单.md`](docs/验收清单.md) 里列出的待办项。

**不要重写架构。** 两进程 + App Group 信箱的设计是刻意为之（原因见 [`docs/架构设计.md`](docs/架构设计.md)：App 扩展强制沙盒，重操作必须交给非沙盒主程序）。

## 环境与构建

```bash
brew install xcodegen          # 一次即可
# 改 project.yml 里的 DEVELOPMENT_TEAM 为真实 10 位 Team ID
./scripts/bootstrap.sh         # = xcodegen generate
open SuperRightClick.xcodeproj # Xcode ⌘R
```

工程由 `project.yml` 经 **XcodeGen** 生成，**不要手写 / 提交 `.xcodeproj`**。改配置改 `project.yml` 后重跑 `xcodegen generate`。

## 代码地图（★ = 核心）

| 文件 | 作用 |
|------|------|
| `Shared/Command.swift` ★ | `ActionID` 动作枚举 + `Command`(含 `arg`) + 指令信箱 `Mailbox` |
| `Shared/AppConfig.swift` | Bundle ID / App Group / 信箱路径常量 |
| `Shared/Preferences.swift` | 功能分组开关，存 App Group 共享 `UserDefaults`，扩展与主程序共读 |
| `FinderExtension/FinderSyncController.swift` ★ | `FIFinderSync` 子类，菜单点击分发；复制类就地做，其余投递信箱 |
| `FinderExtension/MenuBuilder.swift` ★ | 拼装仿 Windows 多级菜单 |
| `App/SuperRightClickApp.swift` | `@main` 入口 + 0.5s 轮询信箱 + URL Scheme 兜底 |
| `App/CommandExecutor.swift` ★ | 所有动作的真正执行逻辑（文件/shell/哈希） |
| `App/UninstallManager.swift` ★ | 卸载残余扫描 + 移废纸篓 |
| `App/UninstallView.swift` / `BatchRenameWindow.swift` | SwiftUI 窗口 |
| `App/SettingsView.swift` | 三步引导界面 |

## 加新功能的约定（三步）

1. `Shared/Command.swift` 的 `ActionID` 加 case；
2. `FinderExtension/MenuBuilder.swift` 加菜单项；
3. `App/CommandExecutor.swift` 的 `switch` 加分支。

详见 [`docs/开发指南-如何添加菜单项.md`](docs/开发指南-如何添加菜单项.md)。

## 硬性约束

- 主程序 `App/App.entitlements` 必须保持 **`app-sandbox = false`**（要访问 `/Applications`、`~/Library`）。因此只能 Developer ID 分发，不能上架 App Store。
- 扩展 `FinderExtension/FinderExtension.entitlements` 必须 **`app-sandbox = true`**（系统强制）。
- 三处的 App Group `group.com.team.superrightclick` 必须完全一致（`AppConfig.swift` + 两个 `.entitlements`）。
- 删除类操作一律用 `trashItem`（移废纸篓），**禁止** `removeItem` 永久删除。

## 验收标准

见 [`docs/验收清单.md`](docs/验收清单.md)。最低标准：两个 target 都编译通过、扩展能在 Finder 右键出现菜单项（默认平铺；设置里可切换为「⚡️ 超级右键」子菜单）、点"复制路径"剪贴板有内容、点"彻底卸载"能弹出残余扫描窗口。

> 菜单项点击载荷是字典 `{"action": <ActionID raw>, "arg": <可选>}`（见 `MenuBuilder.item` 与 `FinderSyncController.handleMenu`）。带参数的动作（如 `openWith` 传 App 路径）走 `arg`。调试日志在 App Group 容器 `debug.log`，不是 `/tmp`。
