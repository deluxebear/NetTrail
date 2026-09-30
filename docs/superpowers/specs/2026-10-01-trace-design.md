# Trace — macOS 按 App 追踪网络域名 设计文档

日期：2026-10-01
状态：待评审

## 1. 目标与范围

### 目标
让用户方便地知道 macOS 上每个 App 访问了哪些网络域名，以及访问的时间、次数和流量。

### 已确认的需求
- 平台：macOS 原生 App，Developer ID 签名，官网 / GitHub 分发（不上 Mac App Store）。
- 功能：第一版**只监控**，不拦截、不阻断任何连接。
- 形态：常驻菜单栏（最近活动）+ 主窗口（按 App 浏览域名与历史）。
- 技术栈：纯 Swift（SwiftUI + Network Extension），最低 macOS 14。

### 假设（已在讨论中提出，未被否定）
- 记录维度：App、域名、首次/最近访问时间、连接数、上下行字节数。
- 历史按小时汇总保留 30 天（可在设置中修改）；数据仅存本机，不上传。

### 成功标准
安装并批准扩展后，打开浏览器 / Slack 等 App，数秒内可在界面上看到其访问的域名；监控开启前后网络可用性与吞吐无明显差异。

### 非目标（v1 不做）
- 阻断 / 防火墙规则 / 连接弹窗询问。
- DNS Proxy、透明代理、TLS 解密。
- 云同步、多设备、导出（后续可加）。
- 按注册域名（eTLD+1）分组。

## 2. 方案选择

对比过的方案：

| 方案 | 结论 |
|---|---|
| **A. NEFilterDataProvider 系统扩展，全部放行只观察** | **采用**。App 归属准确（audit token）、可得域名与流量、不转发数据，扩展故障不影响上网。 |
| B. NEDNSProxyProvider | 否。无流量、查询≠连接、自己转发 DNS 有断网风险、DoH 绕过。 |
| C. 轮询 nettop / lsof | 否。只有 IP，无法满足“按域名”。 |
| PKTAP + BPF（参考 RustNet） | 否。依赖半私有接口、需 root daemon、需自行 TCP 重组；可见域名并不多于 A。 |
| 内核扩展 / DTrace / Endpoint Security | 不可行或不适用。 |

参考项目：LuLu（Objective-See，NEFilterDataProvider，最接近本方案）、Apple 示例 “Filtering Network Traffic”（SimpleFirewall）、RustNet（SNI/DNS 解析参考）。

已知局限：App 使用自带加密 DNS 且 TLS 启用 ECH 时，只能显示 IP。

## 3. 架构

```
┌──────────────── Trace.app（用户态，登录项）──────────────────────┐
│  MenuBarExtra（最近活动）      主窗口（App → 域名 → 历史）         │
│              └──────────┬──────────┘                            │
│                     ViewModels                                  │
│                         │                                       │
│   Aggregator ──► Store（SQLite / GRDB，                          │
│       ▲                ~/Library/Application Support/Trace）     │
│   ExtensionClient（XPC 客户端 + 扩展安装 / 状态管理）              │
└───────┼─────────────────────────────────────────────────────────┘
        │ XPC（NEMachServiceName）
┌───────┼──────── TraceFilter.systemextension（root）─────────────┐
│   EventServer（XPC 服务端 + 内存环形缓冲 ~10k 事件）               │
│       ▲                                                         │
│   FlowObserver：NEFilterDataProvider，全部 allow                  │
│     ├─ 新连接：audit token → pid、签名 ID、team ID、路径            │
│     ├─ 域名：remoteHostname → 窥探首包 SNI / HTTP Host → DNS 缓存  │
│     ├─ UDP 53 入站：解析 DNS 响应，更新 IP→域名 缓存               │
│     └─ 连接关闭报告：上下行字节数                                  │
└─────────────────────────────────────────────────────────────────┘

TraceCore（Swift Package，App 与扩展共用，纯逻辑、可单测）：
  事件模型、SNI 解析器、HTTP Host 解析器、DNS 响应解析器、IP→域名 TTL 缓存
```

### 组件职责

| 单元 | 职责 | 依赖 |
|---|---|---|
| `TraceCore` | 事件模型（Codable）、协议解析器、IP→域名缓存 | Foundation |
| `FlowObserver`（扩展） | 处理新连接 / 数据窥探 / 关闭报告，产出事件；任何异常一律 allow | NetworkExtension, TraceCore |
| `EventServer`（扩展） | 环形缓冲、XPC 服务、客户端签名校验、丢弃计数 | TraceCore |
| `ExtensionClient`（App） | 安装/激活扩展、启用 NEFilterManager 配置、XPC 连接与重连、状态发布 | SystemExtensions, NetworkExtension |
| `Aggregator`（App） | 维护未关闭连接表，每秒批量写入 Store，维护内存中“最近 5 分钟”视图 | TraceCore, Store |
| `Store`（App） | SQLite schema、upsert、查询、30 天清理、损坏恢复 | GRDB |
| `AppIdentityResolver`（App） | 签名 ID / 路径 → 显示名、图标 | AppKit (NSWorkspace) |
| UI（App） | MenuBarExtra、主窗口、引导、设置 | SwiftUI, Swift Charts |

### 关键决定
1. **扩展只采集不存储**；数据库由 App 持有。App 未运行时事件留在扩展环形缓冲区，重连后补发。
2. **尽早放行**：每个连接最多窥探前 ~2 KB 出站数据，拿到 SNI / Host 或超时（2 秒）即返回 allow 并停止检查。
3. **App 身份以代码签名 ID 为准**；无签名进程退化为可执行文件路径。优先使用 `sourceAppAuditToken`，使 `nsurlsessiond` 等代理进程发起的连接归属到原始 App。
4. **域名来源分级并记录**：`.system`（remoteHostname）> `.sni` > `.httpHost` > `.dnsCache` > `.none`（用 IP 字符串）。

## 4. 数据模型

### XPC 事件（每 500 ms 一批）

```swift
struct AppIdentity: Codable, Hashable {
    let signingID: String?
    let teamID: String?
    let bundleID: String?
    let executablePath: String
    let pid: Int32
}

struct Endpoint: Codable, Hashable {
    let ip: String
    let port: UInt16
    let proto: TransportProtocol   // .tcp / .udp
}

enum HostSource: String, Codable { case system, sni, httpHost, dnsCache, none }

struct FlowOpened: Codable {
    let flowID: UUID
    let time: Date
    let app: AppIdentity
    let remote: Endpoint
    let host: String?              // 规范化：小写、去掉末尾的点
    let hostSource: HostSource
}

struct FlowClosed: Codable {
    let flowID: UUID
    let time: Date
    let bytesIn: UInt64
    let bytesOut: UInt64
}

struct EventBatch: Codable {
    let opened: [FlowOpened]
    let closed: [FlowClosed]
    let droppedSinceLastBatch: UInt64
}
```

### SQLite 表

```sql
CREATE TABLE app (
  id INTEGER PRIMARY KEY,
  identity_key TEXT NOT NULL UNIQUE,   -- signingID，缺失时为可执行文件路径
  bundle_id TEXT, display_name TEXT, path TEXT, team_id TEXT,
  first_seen REAL NOT NULL, last_seen REAL NOT NULL
);

CREATE TABLE app_domain (
  app_id INTEGER NOT NULL REFERENCES app(id),
  domain TEXT NOT NULL,                -- 域名或 IP 字符串
  resolved INTEGER NOT NULL,           -- 0 = 仅 IP
  last_source TEXT NOT NULL,
  first_seen REAL NOT NULL, last_seen REAL NOT NULL,
  conn_count INTEGER NOT NULL DEFAULT 0,
  bytes_in INTEGER NOT NULL DEFAULT 0, bytes_out INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (app_id, domain)
);

CREATE TABLE app_domain_hourly (
  app_id INTEGER NOT NULL, domain TEXT NOT NULL,
  hour INTEGER NOT NULL,               -- Unix 时间 / 3600
  conn_count INTEGER NOT NULL DEFAULT 0,
  bytes_in INTEGER NOT NULL DEFAULT 0, bytes_out INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (app_id, domain, hour)
);
```

### 聚合规则
- 不存单个连接明细。
- `FlowOpened`：连接数 +1（计入打开时刻所在小时），同时放入未关闭连接表。
- `FlowClosed`：字节数计入关闭时刻所在小时及 `app_domain` 累计；找不到对应 `FlowOpened` 时丢弃。
- 未关闭连接表中超过 24 小时的条目被清除。
- Aggregator 每秒一个事务批量 upsert；每日清理早于保留期的 `app_domain_hourly` 行。
- 菜单栏“最近 5 分钟”来自内存实时事件，不查询数据库。
- `droppedSinceLastBatch > 0` 时在 UI 显示“有 N 条事件丢失”。

## 5. 界面

### 菜单栏（MenuBarExtra，window 样式）
- 顶部状态：● 监控中 / ⏸ 已暂停 / ⚠ 扩展未批准或未连接（点击进入修复引导）。
- 最近 5 分钟有活动的 App（按最近活动排序，最多 8 个），显示域名数；点击展开最近域名或跳转主窗口。
- 底部：打开主窗口、暂停记录（仅 App 侧不写库，扩展仍全部放行）、退出。

### 主窗口（NavigationSplitView 三栏）
- 左：App 列表（搜索、按最近 / 流量排序），顶部“全部 App”入口用于按域名反查。
- 中：所选 App 的域名 Table（域名、连接数、↓流量、↑流量、最近访问，可排序）；未解析 IP 标记 ⚠；时间范围 今天 / 7 天 / 30 天 / 全部，由小时表汇总。
- 右：域名详情——首次 / 最近访问、来源、Swift Charts 按小时柱状图。

### 首次启动引导
单页三步：① 安装系统扩展 ② 在系统设置中批准 ③ 启用 content filter。实时显示每步状态并提供跳转按钮。

### 设置（主窗口内）
登录时启动、历史保留天数（默认 30）、清空数据、卸载扩展。

## 6. 错误处理

| 场景 | 处理 |
|---|---|
| 扩展未安装 / 未批准 / filter 被关闭 | 监听 `OSSystemExtensionRequest` 结果与 `NEFilterManager` 配置变化，状态置 ⚠，引导修复 |
| 扩展崩溃 / 被系统重启 | 系统自动拉起；App XPC 断线后指数退避重连（1s → 30s）；崩溃时未关闭连接缺失字节数，接受误差 |
| App 未运行 | 扩展环形缓冲暂存，满则丢最旧并计数 |
| 扩展内部任何异常 / 解析失败 | 一律 allow（fail-open）；解析器对畸形输入返回 nil，不抛异常、不崩溃 |
| 首包迟迟不来 | 窥探 2 秒超时后放行，域名退回 DNS 缓存或 IP |
| 数据库打开失败 / 损坏 | 旧库改名备份，新建空库并提示用户 |
| XPC 安全 | 扩展仅接受 team ID 与自身相同的客户端（通过 audit token 校验代码签名） |

## 7. 测试

1. **TraceCore 单元测试（重点）**
   - SNI：真实 ClientHello 字节夹具，覆盖 TLS 1.2 / 1.3、截断、多扩展、GREASE、无 SNI。
   - HTTP Host：正常请求、大小写、带端口、截断。
   - DNS 响应：A / AAAA / CNAME 链、名称压缩、指针循环等畸形包。
   - IP→域名缓存：TTL 过期、容量淘汰。
   - SNI / DNS 解析器随机字节 fuzz：不崩溃。
2. **Aggregator + Store**：内存 SQLite，喂事件序列断言汇总；覆盖跨小时连接、关闭先于打开、过期清理。
3. **XPC 协议**：`EventBatch` 编解码往返。
4. **手动集成清单**（扩展无法在 CI 运行）：
   - `curl https://example.com`、Safari、`dig` 数秒内出现正确 App 与域名。
   - `kill` 扩展进程后网络不中断，系统自动恢复，App 自动重连。
   - `networkQuality` 开启前后吞吐对比无明显下降。

## 8. 前置条件

- 付费 Apple Developer 账号；App ID 开启 Network Extensions（Content Filter Provider）与 System Extension 能力；Developer ID 分发需使用 `content-filter-provider-systemextension` entitlement 并公证。
- 开发调试：Development 签名 + `systemextensionsctl developer on`。

## 9. 工程结构（初步）

```
Trace/
  Trace.xcodeproj
  Trace/                    # App target（SwiftUI）
  TraceFilter/              # System Extension target
  Packages/TraceCore/       # Swift Package（模型、解析器、缓存）+ Tests
  docs/superpowers/specs/
```
