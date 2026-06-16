# 发布 .dmg 与公证清单

把 SuperRightClick 打成能给**别人**用的 `.dmg`，需要签名 + 公证。纯自用/源码分发可跳过本文。

## 为什么必须公证

本 app **非沙盒**且**带 Finder Sync 扩展**。未签名/未公证的版本在别人机器上会：

- 被 Gatekeeper 拦「来自身份不明的开发者」；
- 即使强行打开，Finder 扩展也常常加载不出来。

所以对外分发是硬性要求，需要**付费 Apple 开发者账号（$99/年）**生成的 Developer ID 证书。

## 一次性准备

1. 在 Apple 开发者后台生成 **Developer ID Application** 证书，下载并装进钥匙串。确认证书名，例如
   `Developer ID Application: Your Name (TEAMID)`（用 `security find-identity -p codesigning -v` 可列出）。
2. 生成一个 **App 专用密码**（appleid.apple.com → 登录与安全 → App 专用密码）。
3. 把公证凭证存进钥匙串 profile（之后 notarytool 直接引用，免明文密码）：

   ```bash
   xcrun notarytool store-credentials srcprofile \
     --apple-id you@example.com \
     --team-id TEAMID \
     --password <App专用密码>
   ```

## 一键打包

```bash
DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=srcprofile \
./scripts/make-dmg.sh
```

脚本会依次：生成工程 → Release 构建 → 先签 `.appex` 再签 `.app`（顺序不能反）→ 校验签名 → 组织「app + Applications 快捷方式」→ 出 dmg → 签 dmg → 公证并 staple。产物在 `dist/SuperRightClick-<版本>.dmg`。

> 只想本机测试、不签名：直接 `./scripts/make-dmg.sh`，得到未签名 dmg（别人用不了）。

## 发布前自检

- [ ] `spctl -a -vvv -t install dist/SuperRightClick-*.dmg` 显示 `accepted / Notarized Developer ID`
- [ ] `xcrun stapler validate dist/SuperRightClick-*.dmg` 通过
- [ ] 找一台**没装过开发环境**的 Mac，下载 dmg → 拖进 Applications → 首次打开不被拦
- [ ] 在该机启用 Finder 扩展 + 完全磁盘访问，右键菜单功能正常
- [ ] dmg 里不包含调试符号外的多余文件、版本号正确
- [ ] GitHub Release 里附上 dmg，并在说明里写清需要的系统权限

## 常见坑

- **先签扩展再签外层**：反了会破坏外层签名（脚本已处理）。
- **必须带 `--options runtime`（Hardened Runtime）**，否则公证不过（工程已开 `ENABLE_HARDENED_RUNTIME`）。
- 公证失败时用 `xcrun notarytool log <id> --keychain-profile srcprofile` 看具体原因。
