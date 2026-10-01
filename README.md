**English** | [简体中文](README.zh-CN.md)

# NetTrail

See which domains every app on your Mac connects to — when, how often, and how much data.

NetTrail is a native macOS menu bar app. It uses a monitor-only Network Extension content filter to record each app's network connections and shows them by app and domain. It **never blocks, modifies or forwards** any traffic, and all data stays on your Mac.

## Features

- **Per-app domain tracking** — browse every domain an app contacted, with first/last seen time, connection count and upload/download bytes.
- **Menu bar + main window** — the menu bar shows the last 5 minutes of activity and live traffic rates; the main window gives you the app list, domain table and a 7-day hourly chart.
- **Domain sources** — domains are resolved from TLS SNI, HTTP Host, the system DNS cache, or system-provided hostnames, and the source is shown for each record.
- **Launch origin** — see which app, process chain (e.g. `zsh ← login ← ghostty`) and script started a connection, so `node`/`python` traffic is traceable.
- **Helper merging** — helper processes (Chrome Helper, Slack Helper, …) are grouped under their main app.
- **Copy as proxy rules** — export an app's connections (LAN excluded, collapsed to main domains) as Clash / Mihomo, Surge / Loon, sing-box rules, or a plain list.
- **Private by design** — local SQLite storage, hourly buckets, history kept for 1–365 days (configurable), one-click clear.
- **Fail-safe** — if the extension crashes, your network keeps working; records missed while the app was closed are backfilled on relaunch.
- Localized in English and 简体中文.

## Requirements

- macOS 14 (Sonoma) or later
- To build from source: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an Apple Developer team with the Network Extension (content filter) capability

## Getting Started

1. Open NetTrail. The onboarding flow walks you through three steps:
   1. **Install** the system extension
   2. **Approve** it in System Settings → General → Login Items & Extensions
   3. **Enable** the content filter
2. The menu bar icon shows **Monitoring** once everything is running. Open the main window to browse apps and domains.

## Build from Source

```sh
# 1. Set your team ID and bundle ID
$EDITOR Config/Base.xcconfig      # TRACE_TEAM_ID, TRACE_BUNDLE_ID

# 2. Build, sign, and install to /Applications, then launch
scripts/install-dev.sh
```

System extensions only activate from `/Applications`, which is why the script installs there. Every install uses a fresh build number so the app replaces the previously running extension.

Run the unit tests:

```sh
swift test --package-path Packages/TraceCore
```

For the manual integration checklist, see [docs/TESTING.md](docs/TESTING.md) (Chinese).

## Architecture

```
NetTrail.app (user space)                 TraceFilter.systemextension (root)
 ├─ MenuBarExtra / main window  ◄─ XPC ─► ├─ FilterDataProvider (allow all, observe only)
 ├─ Aggregator → SQLite store             ├─ SNI / HTTP Host / DNS parsing
 └─ Extension lifecycle management        └─ in-memory event ring buffer
```

| Path | Purpose |
|---|---|
| `Trace/` | SwiftUI app: menu bar, main window, onboarding, settings |
| `TraceFilter/` | System extension: the content filter provider and XPC server |
| `Packages/TraceCore/TraceCore` | Pure parsing logic (TLS SNI, HTTP Host, DNS, event ring, XPC protocol) |
| `Packages/TraceCore/TraceKit` | Aggregation, SQLite storage (GRDB), app identity resolution, proxy rules |

Design and plan documents are in [docs/superpowers](docs/superpowers) (Chinese).

## Limitations

- Apps that use their own encrypted DNS together with TLS ECH can only be shown by IP address.
- Inline scripts (e.g. `node -e`) are not captured; script files are.
- Monitoring only: NetTrail is not a firewall and does not prompt for or block connections.

## License

[MIT](LICENSE)
