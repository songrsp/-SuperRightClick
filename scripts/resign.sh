#!/bin/bash
# resign.sh — SuperRightClick 到期自动重签
# 由 LaunchAgent 每天执行一次：检查 /Applications/SuperRightClick.app 内嵌 profile
# 的有效期，剩余 < 48h（或已过期/缺失）时自动重新签名构建并安装到 /Applications。
# 手动立即执行一次：./scripts/resign.sh --force
set -u

# 脚本在 <repo>/scripts/ 下，工程根目录即上一级
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="/Applications/SuperRightClick.app"
LOG="$HOME/Library/Logs/superrightclick-resign.log"
THRESHOLD_SEC=172800   # 48 小时
XCODEBUILD="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
XCODEGEN="$(command -v xcodegen 2>/dev/null || echo "$HOME/bin/xcodegen/bin/xcodegen")"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

profile_expiry_ts() {
    # 输出内嵌 profile 的过期时间戳；取不到则输出空
    python3 - "$APP/Contents/embedded.provisionprofile" <<'PY' 2>/dev/null
import plistlib, subprocess, sys
try:
    raw = subprocess.run(['security', 'cms', '-D', '-i', sys.argv[1]],
                         capture_output=True, check=True).stdout
    pl = plistlib.loads(raw)
    print(int(pl['ExpirationDate'].timestamp()))
except Exception:
    pass
PY
}

needs_resign() {
    [ "${1:-}" = "--force" ] && return 0
    local exp_ts now_ts
    exp_ts=$(profile_expiry_ts)
    [ -n "$exp_ts" ] || return 0        # 读不到有效期：宁可重签
    now_ts=$(date +%s)
    [ $((exp_ts - now_ts)) -lt $THRESHOLD_SEC ]
}

log "=== 检查开始 ==="
if ! needs_resign "$@"; then
    log "profile 仍在有效期内，跳过"
    exit 0
fi
log "需要重签，开始构建"

[ -d "$SRC" ] || { log "FAIL: 源码目录不存在 $SRC"; exit 1; }
[ -x "$XCODEGEN" ] || { log "FAIL: 找不到 xcodegen $XCODEGEN"; exit 1; }
[ -x "$XCODEBUILD" ] || { log "FAIL: 找不到 xcodebuild $XCODEBUILD"; exit 1; }

cd "$SRC" || exit 1
"$XCODEGEN" generate >>"$LOG" 2>&1 || { log "FAIL: xcodegen generate"; exit 1; }
"$XCODEBUILD" -project SuperRightClick.xcodeproj -scheme SuperRightClick \
    -configuration Debug -allowProvisioningUpdates build >>"$LOG" 2>&1 \
    || { log "FAIL: xcodebuild"; exit 1; }

BUILT=$(echo "$HOME"/Library/Developer/Xcode/DerivedData/SuperRightClick-*/Build/Products/Debug/SuperRightClick.app)
[ -d "$BUILT" ] || { log "FAIL: 找不到构建产物"; exit 1; }

# 先退出旧版本，再替换安装
osascript -e 'tell application "SuperRightClick" to quit' >/dev/null 2>&1 || true
sleep 1
# 旧版本移到废纸篓（可找回），不永久删除
osascript -e "tell application \"Finder\" to delete (POSIX file \"$APP\" as alias)" >/dev/null 2>&1 || mv "$APP" "$HOME/.Trash/SuperRightClick-$(date +%s).app"
cp -R "$BUILT" "$APP" || { log "FAIL: 拷贝到 /Applications"; exit 1; }
open "$APP" >/dev/null 2>&1 || true
log "OK: 重签完成，已安装到 $APP"
