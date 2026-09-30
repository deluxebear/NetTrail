# Trace 测试

## 自动化

    swift test --package-path Packages/TraceCore

## 手动集成清单（每次改动扩展后执行）

准备：`scripts/install-dev.sh`，按引导完成 安装扩展 → 系统设置批准 → 启用内容过滤。

1. 扩展状态：`systemextensionsctl list` 显示 `com.xiongyanlin.trace.filter` 为 `[activated enabled]`；菜单栏显示“监控中”。
2. curl：`curl -s https://example.com >/dev/null`，5 秒内菜单栏“最近 5 分钟”出现 curl → example.com；主窗口来源为“TLS SNI”或“系统提供”，↓流量 > 0。
3. 浏览器：Safari 打开 https://www.apple.com，Safari 出现 www.apple.com。
4. HTTP：`curl -s http://neverssl.com >/dev/null`，来源为“HTTP Host”或“系统提供”。
5. DNS 缓存：`dig example.org` 后 `nc -z $(dig +short example.org | head -1) 443`，nc 的记录显示 example.org（来源“DNS 缓存”）。若显示为 IP，说明过滤器看不到 mDNSResponder 的 DNS 流量——记录此结论。
6. Helper 归并：打开 Slack 或 Chrome，其 Helper 进程的连接显示在主 App 名下。
7. 容错：`sudo pkill -f com.xiongyanlin.trace.filter`，网络保持可用（curl 仍成功），系统自动拉起扩展，App 在 30 秒内恢复“监控中”。
8. App 未运行：退出 Trace，curl 几个站点，重新打开 Trace，这些记录被补上。
9. 性能：分别在关闭/开启过滤时运行 `networkQuality -s`，吞吐差异 < 10%。
10. 日志：`log stream --predicate 'subsystem == "com.xiongyanlin.trace.filter"'` 无持续错误。
