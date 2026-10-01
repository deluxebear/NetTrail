[English](README.md) | **简体中文**

# NetTrail

一眼看清 Mac 上每个 App 访问了哪些网络域名——访问时间、次数与流量。

NetTrail 是一款原生 macOS 菜单栏应用。它通过「只观察」的 Network Extension 内容过滤器记录每个 App 的网络连接，并按 App 与域名展示。它**不会拦截、修改或转发**任何流量，所有数据都只保存在本机。

## 功能

- **按 App 追踪域名**：查看某个 App 访问过的所有域名，包括首次/最近访问时间、连接数、上下行流量。
- **菜单栏 + 主窗口**：菜单栏显示最近 5 分钟的活动与实时速率；主窗口提供 App 列表、域名表格和 7 天按小时的趋势图。
- **域名来源**：域名来自 TLS SNI、HTTP Host、系统 DNS 缓存或系统提供的主机名，每条记录都会标明来源。
- **调用来源**：显示是哪个 App、哪条进程链（如 `zsh ← login ← ghostty`）、哪个脚本发起的连接，`node`、`python` 等命令行工具的流量也能追溯。
- **Helper 归并**：Chrome Helper、Slack Helper 等辅助进程的连接归入其主 App。
- **复制为代理规则**：将某个 App 的连接（排除局域网，合并为主域名）导出为 Clash / Mihomo、Surge / Loon、sing-box 规则或纯文本列表。
- **隐私优先**：数据存储在本地 SQLite，按小时汇总，历史保留 1–365 天（可设置），可一键清除。
- **故障安全**：扩展崩溃不影响上网；App 未运行期间漏掉的记录会在重新打开时补上。
- 支持 English 与简体中文界面。

## 系统要求

- macOS 14（Sonoma）或更高版本
- 从源码构建需要：Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)，以及具备 Network Extension（内容过滤）权限的 Apple 开发者团队

## 快速开始

1. 打开 NetTrail，按引导完成三步：
   1. **安装**系统扩展
   2. 在「系统设置 → 通用 → 登录项与扩展」中**批准**
   3. **启用**内容过滤
2. 一切就绪后，菜单栏会显示「监控中」。打开主窗口即可浏览 App 与域名。

## 从源码构建

```sh
# 1. 填写你的 Team ID 和 Bundle ID
$EDITOR Config/Base.xcconfig      # TRACE_TEAM_ID、TRACE_BUNDLE_ID

# 2. 构建、签名、安装到 /Applications 并启动
scripts/install-dev.sh
```

系统扩展只有在 `/Applications` 中才能激活，所以脚本会安装到该目录。每次安装都会使用新的构建号，使 App 能替换正在运行的旧扩展。

运行单元测试：

```sh
swift test --package-path Packages/TraceCore
```

手动集成测试清单见 [docs/TESTING.md](docs/TESTING.md)。

## 架构

```
NetTrail.app（用户态）                    TraceFilter.systemextension（root）
 ├─ 菜单栏 / 主窗口             ◄─ XPC ─► ├─ FilterDataProvider（全部放行，只观察）
 ├─ Aggregator → SQLite 存储              ├─ SNI / HTTP Host / DNS 解析
 └─ 扩展生命周期管理                       └─ 内存事件环形缓冲
```

| 路径 | 说明 |
|---|---|
| `Trace/` | SwiftUI 应用：菜单栏、主窗口、引导流程、设置 |
| `TraceFilter/` | 系统扩展：内容过滤 Provider 与 XPC 服务端 |
| `Packages/TraceCore/TraceCore` | 纯解析逻辑（TLS SNI、HTTP Host、DNS、事件环、XPC 协议） |
| `Packages/TraceCore/TraceKit` | 聚合、SQLite 存储（GRDB）、App 身份识别、代理规则 |

设计文档与实现计划见 [docs/superpowers](docs/superpowers)。

## 已知局限

- 若 App 自带加密 DNS 且 TLS 启用了 ECH，只能显示 IP 地址。
- 内联脚本（如 `node -e`）不会被采集，脚本文件会。
- 仅监控：NetTrail 不是防火墙，不会弹窗询问或阻断连接。

## 许可证

[MIT](LICENSE)
