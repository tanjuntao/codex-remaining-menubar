# Codex Remaining

一个原生 macOS 菜单栏应用，通过本机 `codex app-server` 展示 ChatGPT 账户中的 Codex 剩余额度。

## 当前功能

- 在菜单栏直接显示最紧张额度窗口的剩余百分比
- 支持“图标 + 百分比”“仅图标”“仅百分比”三种菜单栏展示方式
- 弹窗展示所有 `rateLimitsByLimitId` 额度桶
- 展示已用/剩余比例、窗口长度和重置时间
- 复用 Codex App Server 管理的 ChatGPT 登录状态
- 未登录时发起官方 ChatGPT 浏览器登录
- 每 5 分钟自动刷新，并监听额度变化通知
- 缓存最后一次成功结果，断网时保留展示
- 支持登录时启动和打开完整 Usage 页面

## 要求

- macOS 13 或更高版本
- 已安装支持 `app-server` 的 Codex CLI
- 已登录 ChatGPT/Codex；未登录时可从应用内发起登录

GUI 应用的 `PATH` 通常很短。应用会自动检查 Homebrew、`~/.local/bin`、Volta、pnpm 和 NVM 的常见安装位置。也可以在开发环境中设置 `CODEX_EXECUTABLE` 指向 Codex 可执行文件。

## 开发

```bash
make test
make app
open "dist/Codex Remaining.app"
```

当前环境只需要 Command Line Tools；`Scripts/build-app.sh` 会用 SwiftPM 编译，并在 `dist/` 下组装、临时签名一个标准 `.app`。
`Scripts/test.sh` 会兼容只安装 Command Line Tools 时 Swift Testing framework 不在默认搜索路径的问题。

正式分发前需要：

1. 将 `Resources/AppInfo.plist` 中的 Bundle ID 改成自己的反向域名。
2. 使用 Developer ID Application 证书签名。
3. 对应用执行 Apple Notarization。

## 数据与隐私

应用不会读取 ChatGPT Cookie、不会提取 Keychain Token，也不会保存访问令牌。登录、Token 刷新和 Usage 请求都由本机 Codex App Server 负责。应用只缓存渲染所需的额度结果，缓存位于自己的 Application Support 目录。

## 已知边界

- 这里只展示 Codex App Server 返回的 Codex/ChatGPT rate-limit 数据，不代表 OpenAI Platform API 组织用量。
- App Server 协议会随 Codex CLI 版本演进；解析器会忽略未知字段，但重大协议升级可能需要适配。
- Mac App Store 沙箱会限制启动外部 CLI 和复用 `~/.codex`，当前发行方式面向 Developer ID 公证后的直接下载。
