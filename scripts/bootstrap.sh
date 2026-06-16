#!/usr/bin/env bash
# 生成 Xcode 工程并（可选）命令行构建。
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "✗ 未找到 xcodegen，请先执行：brew install xcodegen"
  exit 1
fi

if [[ ! -f Local.xcconfig ]]; then
  cp Local.xcconfig.example Local.xcconfig
  echo "→ 已创建 Local.xcconfig，请填入你的 Apple Team ID 后重新运行。"
  echo "   位置：$(pwd)/Local.xcconfig"
  exit 1
fi

if ! grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}[[:space:]]*$' Local.xcconfig; then
  echo "✗ 请先在 Local.xcconfig 填入你的 10 位 Apple Team ID。"
  echo "   例：DEVELOPMENT_TEAM = ABCDE12345"
  exit 1
fi

echo "→ 生成 Xcode 工程 ..."
xcodegen generate

echo "✓ 已生成 SuperRightClick.xcodeproj"
echo
echo "接下来二选一："
echo "  1) 图形界面：open SuperRightClick.xcodeproj  然后 ⌘R"
echo "  2) 命令行构建（Debug）："
echo "     xcodebuild -project SuperRightClick.xcodeproj -scheme SuperRightClick -configuration Debug build"
