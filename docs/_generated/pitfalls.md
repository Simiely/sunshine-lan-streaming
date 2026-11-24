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

## 未解决（1）

| 严重度 | 坑 | 症状 | 检测 | 适用 | status |
|---|---|---|---|---|---|
| high | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | 退出串流后主机冻结约两分钟，Sunshine 不再接受新连接，随后服务自行重启；期间鼠标键盘可能无响应，显示器分辨率停在串流时的值。 | 在 sunshine.log 里搜 Trying to revert applied display device settings，若短时间内重复出现 5 次以上、且伴随 Device does not exist in the available path source data，即命中。 | `streaming.version-matrix`, `streaming.virtual-display` | active |

## 已解决（0）

（无）

## 按适用范围

### `streaming.version-matrix`

- [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md)（high）

### `streaming.virtual-display`

- [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md)（high）
