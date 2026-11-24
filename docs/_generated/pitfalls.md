---
id: docs.generated.pitfalls
title: 踩坑索引
summary: 从 kind=pitfall 页面自动生成的失败模式索引；勿手改。
type: reference
kind: index
status: active
owner: "@platform"
source_type: doc
source: schema/taxonomy.json
last_reviewed: 2026-11-11
related: []
---

# 踩坑索引

> 生成文件，勿手改。运行 `python tools/repo-kit/generate.py --root . --write` 重建。
> 每个坑的权威内容在它自己的页面；本页只做导航。

## 未解决（3）

| 严重度 | 坑 | 症状 | 检测 | 适用 | status |
|---|---|---|---|---|---|
| high | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | sunshine.conf 突然只剩两三行，先前写入的基线键消失；体检测试的合格数无故下降（本机从 14 掉到 12），upnp 与 origin_web_ui_allowed 同时回落到默认值。 | 看 sunshine.conf 的字节数——正常应包含全部已配置键，若只有二三十字节就是被清空了。也可对比 Get-Baseline.ps1 的合格数，D-02/D-03 同时退回 ⚠️ 即为典型信号。 | `streaming.config-inventory`, `streaming.deploy-checklist` | active |
| high | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | 退出串流后主机冻结约两分钟，Sunshine 不再接受新连接，随后服务自行重启；期间鼠标键盘可能无响应，显示器分辨率停在串流时的值。 | 在 sunshine.log 里搜 Trying to revert applied display device settings，若短时间内重复出现 5 次以上、且伴随 Device does not exist in the available path source data，即命中。 | `streaming.version-matrix`, `streaming.virtual-display` | active |
| high | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | vdd_settings.xml 里的分辨率列表已经按设备改好，sunshine.conf 也指向了虚拟屏，但 DXGI 里那块屏始终是 800x600。驱动日志没有任何报错，甚至明确打印 "Using vdd_settings.xml"。 | 三条都成立即可确认：一、看文件头三字节，EF BB BF 就是带 BOM；二、读 C:\VirtualDisplayDriver\Logs\log_YYYY-MM-DD.txt，出现 "Output target modes count: N" 且 N 与 XML 条目数不符；三、用管道发 LOG_DEBUG true 再 RELOAD_DRIVER，看有没有逐条的 "Added: 1920x1080 @ 60/1Hz"。若一条 Added 都没有就是解析失败。 | `streaming.config-inventory`, `streaming.virtual-display` | active |

## 已解决（0）

（无）

## 按适用范围

### `streaming.config-inventory`

- [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md)（high）
- [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md)（high）

### `streaming.deploy-checklist`

- [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md)（high）

### `streaming.version-matrix`

- [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md)（high）

### `streaming.virtual-display`

- [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md)（high）
- [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md)（high）
