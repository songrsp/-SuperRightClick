#!/usr/bin/env bash
#
# make-dmg.sh —— 把 SuperRightClick 打包成可分发的 .dmg
#
# 用法：
#   ./scripts/make-dmg.sh                     # 仅构建 + 打包（未签名，自用/测试）
#   DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
#     NOTARY_PROFILE=srcprofile \
#     ./scripts/make-dmg.sh                   # 构建 + 签名 + 公证 + staple（对外分发）
#
# 环境变量（都可选）：
#   CONFIGURATION       构建配置，默认 Release
#   DEVELOPER_ID_APP    Developer ID Application 证书名；设了才签名
#   NOTARY_PROFILE      notarytool 的 keychain 凭证 profile 名；设了才公证
#                       （先跑一次：xcrun notarytool store-credentials <名字>
#                        --apple-id <你的AppleID> --team-id <TEAMID> --password <App专用密码>）
#
# ⚠️ 给别人用的 dmg 必须签名 + 公证，否则非沙盒 app + Finder 扩展会被 Gatekeeper 拦、
#    扩展也加载不出来。纯自用可跳过签名。完整清单见 docs/发布-dmg-与公证.md。

set -euo pipefail

# —— 路径与参数 ——
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="SuperRightClick"
APP_NAME="SuperRightClick"
PROJECT="SuperRightClick.xcodeproj"

BUILD_DIR="$ROOT/build"
PRODUCT="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
STAGING="$DIST_DIR/dmg-staging"

# 版本号从 project.yml 里读（拿不到就用 dev）
VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/' || true)"
VERSION="${VERSION:-dev}"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

log() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }

# —— 0. 依赖检查 ——
command -v xcodegen >/dev/null || { echo "缺少 xcodegen：brew install xcodegen"; exit 1; }

# —— 1. 生成工程 ——
log "生成 Xcode 工程 (xcodegen)"
xcodegen generate

# —— 2. Release 构建 ——
log "构建 $CONFIGURATION"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration "$CONFIGURATION" \
           -derivedDataPath "$BUILD_DIR" \
           build

[ -d "$PRODUCT" ] || { echo "构建产物不存在：$PRODUCT"; exit 1; }

# —— 3.（可选）Developer ID 签名 ——
# 注意顺序：先签里层的扩展(.appex)，再签外层 app，否则会破坏外层签名。
if [ -n "${DEVELOPER_ID_APP:-}" ]; then
  log "用 Developer ID 签名：$DEVELOPER_ID_APP"
  APPEX="$PRODUCT/Contents/PlugIns/FinderExtension.appex"
  if [ -d "$APPEX" ]; then
    codesign --force --options runtime --timestamp \
             --sign "$DEVELOPER_ID_APP" "$APPEX"
  fi
  codesign --force --options runtime --timestamp \
           --sign "$DEVELOPER_ID_APP" "$PRODUCT"
  log "校验签名"
  codesign --verify --deep --strict --verbose=2 "$PRODUCT"
else
  log "未设置 DEVELOPER_ID_APP —— 跳过签名（产物仅适合本机自用/测试）"
fi

# —— 4. 组织 dmg 内容（app + 指向 /Applications 的快捷方式）——
log "组织 dmg 内容"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$PRODUCT" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# —— 5. 生成 dmg ——
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
if command -v create-dmg >/dev/null; then
  log "用 create-dmg 打包（带拖拽布局）"
  create-dmg \
    --volname "$APP_NAME" \
    --app-drop-link 450 180 \
    --icon "$APP_NAME.app" 150 180 \
    --window-size 600 360 \
    "$DMG_PATH" "$STAGING" || true
  # create-dmg 某些版本即使成功也返回非 0，这里再确认产物是否生成
  [ -f "$DMG_PATH" ] || { echo "create-dmg 未生成 dmg"; exit 1; }
else
  log "用 hdiutil 打包（未装 create-dmg，可 brew install create-dmg 获得更好布局）"
  hdiutil create -volname "$APP_NAME" \
                 -srcfolder "$STAGING" \
                 -ov -format UDZO \
                 "$DMG_PATH"
fi

# —— 6.（可选）签名 dmg 本体 ——
if [ -n "${DEVELOPER_ID_APP:-}" ]; then
  log "签名 dmg"
  codesign --force --sign "$DEVELOPER_ID_APP" --timestamp "$DMG_PATH"
fi

# —— 7.（可选）公证 + staple ——
if [ -n "${NOTARY_PROFILE:-}" ]; then
  log "提交公证（notarytool，会等待 Apple 处理完）"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  log "装订公证票据（staple）"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  log "未设置 NOTARY_PROFILE —— 跳过公证（对外分发前务必补上）"
fi

log "完成 ✅  $DMG_PATH"
