# Codex Remaining

一个轻量的原生 macOS 菜单栏应用，通过本机 `codex app-server` 展示 ChatGPT 账户中的 Codex 剩余额度。无需反复打开 Usage 页面，即可在菜单栏快速确认当前最紧张的额度窗口和重置时间。

<p align="center">
  <img src="./assets/screenshot.png" alt="Codex Remaining 菜单栏应用界面" width="360">
</p>

## 功能亮点

- 在菜单栏直接显示最紧张额度窗口的剩余百分比
- 支持“图标 + 百分比”“仅图标”“仅百分比”三种菜单栏展示方式
- 弹窗展示所有 `rateLimitsByLimitId` 额度桶
- 展示已用/剩余比例、窗口长度和重置时间
- 复用 Codex App Server 管理的 ChatGPT 登录状态
- 未登录时发起官方 ChatGPT 浏览器登录
- 每 5 分钟自动刷新，并监听额度变化通知
- 缓存最后一次成功结果，断网时保留展示
- 支持登录时启动和打开完整 Usage 页面

## 环境要求

- macOS 13 或更高版本
- Xcode Command Line Tools
- Swift 6.0 或更高版本
- 已安装支持 `app-server` 的 Codex CLI
- 已登录 ChatGPT/Codex；未登录时也可从应用内发起登录

可以先确认本地工具链：

```bash
xcode-select -p
swift --version
codex --version
```

GUI 应用继承的 `PATH` 通常比交互式 Shell 短。应用会自动检查 Homebrew、`~/.local/bin`、Volta、pnpm 和 NVM 的常见安装位置；如仍无法发现 Codex CLI，可在开发环境中设置 `CODEX_EXECUTABLE` 为 `codex` 可执行文件的绝对路径。

## 本地构建

克隆仓库并运行测试：

```bash
git clone git@github.com:tanjuntao/codex-remaining-menubar.git
cd codex-remaining-menubar
make test
```

构建可运行的 macOS 应用：

```bash
make app
open "dist/Codex Remaining.app"
```

`make app` 默认执行 release 构建。`Scripts/build-app.sh` 会使用 SwiftPM 编译可执行文件，在 `dist/` 下组装标准 `.app` Bundle，并使用临时签名（ad-hoc signing）完成本机开发构建。整个流程只需要 Xcode Command Line Tools，不要求安装完整 Xcode。

如需调试构建，可显式指定配置：

```bash
CONFIGURATION=debug ./Scripts/build-app.sh
```

## 本地安装

构建完成后，可以直接从 `dist/` 启动，也可以复制到 `/Applications`：

```bash
ditto "dist/Codex Remaining.app" "/Applications/Codex Remaining.app"
open "/Applications/Codex Remaining.app"
```

应用属于菜单栏应用，启动后不会在 Dock 中显示。若要卸载，先退出应用，再移除 `/Applications/Codex Remaining.app`；应用缓存位于自己的 Application Support 目录，删除应用本体不会自动清理缓存。

## 常用开发命令

```bash
make build  # SwiftPM debug 构建
make test   # 运行测试
make app    # 组装 release .app
make run    # 构建并启动应用
make clean  # 清理 SwiftPM 构建产物
```

`Scripts/test.sh` 兼容仅安装 Command Line Tools 时 Swift Testing framework 不在默认搜索路径的问题。

## 分发说明

本地构建使用临时签名，仅适合开发和本机使用。正式向第三方分发前，需要：

1. 将 `Resources/AppInfo.plist` 中的 Bundle ID 改为自己的反向域名。
2. 使用 Developer ID Application 证书签名。
3. 提交 Apple Notarization，并对产物执行 stapling。

## 数据与隐私

应用不会读取 ChatGPT Cookie、不会提取 Keychain Token，也不会保存访问令牌。登录、Token 刷新和 Usage 请求都由本机 Codex App Server 负责。应用只缓存渲染所需的额度结果，缓存位于自己的 Application Support 目录。

## 已知边界

- 这里只展示 Codex App Server 返回的 Codex/ChatGPT rate-limit 数据，不代表 OpenAI Platform API 组织用量。
- App Server 协议会随 Codex CLI 版本演进；解析器会忽略未知字段，但重大协议升级可能需要适配。
- Mac App Store 沙箱会限制启动外部 CLI 和复用 `~/.codex`，当前发行方式面向 Developer ID 公证后的直接下载。
