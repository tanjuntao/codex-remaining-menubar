# 发布 Codex Remaining

本项目使用 GitHub Releases 分发 ad-hoc 签名的 Universal DMG，不依赖 Apple Developer Program、Developer ID 证书或 Apple Notarization。

## 发布产物

每个正式版本包含：

- `Codex-Remaining-<version>.dmg`：同时支持 Apple Silicon 和 Intel Mac。
- `Codex-Remaining-<version>.dmg.sha256`：用于验证下载完整性。
- GitHub 自动生成的 Release Notes。

DMG 内包含 `Codex Remaining.app` 和指向 `/Applications` 的快捷方式。应用的版本号来自 Git Tag，CI 运行编号写入 `CFBundleVersion`。

## 本地验证

发布前在 macOS 上执行：

```bash
make test
make dmg
```

默认版本来自 `Resources/AppInfo.plist`。也可以显式指定版本和构建编号：

```bash
VERSION=0.2.0 BUILD_NUMBER=2 ./Scripts/package-dmg.sh
```

检查生成结果：

```bash
(cd dist && shasum -a 256 -c Codex-Remaining-0.2.0.dmg.sha256)
lipo -archs "dist/Codex Remaining.app/Contents/MacOS/CodexRemainingMenuBar"
codesign --verify --deep --strict --verbose=2 "dist/Codex Remaining.app"
hdiutil verify "dist/Codex-Remaining-0.2.0.dmg"
```

架构输出必须同时包含 `arm64` 和 `x86_64`。`codesign -d --verbose=4` 显示 `Signature=adhoc` 是当前免费分发方案的预期结果。

## 创建 GitHub Release

1. 确认 `master` 上的测试通过且工作区干净。
2. 确认版本使用 `X.Y.Z` 三段数字格式。
3. 创建带说明的 Git Tag 并推送：

```bash
git tag -a v0.2.0 -m "Codex Remaining 0.2.0"
git push origin v0.2.0
```

`.github/workflows/release.yml` 会在 `vX.Y.Z` Tag 推送后自动：

1. 运行 Swift 测试。
2. 构建 `arm64` 和 `x86_64` 两个 release 二进制并合并。
3. 组装 `.app`、注入版本号并执行 ad-hoc 签名。
4. 创建并验证压缩 DMG。
5. 生成 SHA-256 文件。
6. 使用仓库的 `GITHUB_TOKEN` 创建 GitHub Release 并上传两个产物。

这个工作流不需要配置 Apple 账号、证书或额外 GitHub Secrets。

## Gatekeeper 与用户说明

未经 Developer ID 签名和 Apple Notarization 的应用会在第一次启动时被 Gatekeeper 阻止。Release Notes 和 README 必须明确告知用户：

1. 只从本项目的 GitHub Releases 下载。
2. 使用随 Release 提供的 SHA-256 文件验证 DMG。
3. 第一次启动失败后，前往“系统设置 → 隐私与安全性 → 安全性 → 仍要打开”。
4. 确认系统显示的应用名称正确后再输入密码放行。

不要建议用户全局关闭 Gatekeeper，也不要把删除 quarantine 属性作为常规安装步骤。受组织管理的 Mac 可能禁止手动放行。

## 失败处理

- 测试或构建失败：修复后创建新的提交，再重新运行失败的工作流；不要移动已经发布的 Tag。
- Release 尚未创建：可以在修复后删除远程 Tag，再从正确提交创建，但必须确认该 Tag 从未对外发布。
- Release 已经发布：递增补丁版本，例如从 `0.2.0` 发布 `0.2.1`，不要替换已有 DMG。
- 架构缺失：检查 GitHub runner 的 Xcode/Swift 工具链和 `Scripts/build-app.sh` 的交叉编译日志。
