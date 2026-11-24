---
id: docs.generated.backlinks
title: 反向链接
summary: 从 related 与 pitfall 的 applies_to 自动派生的反向链接；勿手改。
type: reference
kind: index
status: active
owner: "@platform"
source_type: doc
source: schema/taxonomy.json
last_reviewed: 2026-11-11
related: []
---

# 反向链接

> 生成文件，勿手改。方向性关系只存一侧，本页是派生结果；对称关系按规范边去重。
> `applies_to` 是 pitfall 的专用字段，可指向页面 id 或技能 name；技能没有页面可链，故只出现在目标列。

| 目标 id / 技能 | 来源 id | 关系 | 来源页面 |
|---|---|---|---|
| `streaming.branch-selection` | [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | see-also | `docs/版本矩阵.md` |
| `streaming.config-inventory` | [真机通了，但不是走局域网通的](../reports/2026-11-24-安卓真机验证.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-安卓真机验证.md` |
| `streaming.config-inventory` | [本机基线：4 项合格、7 项不合格、25 项待测](../reports/2026-11-24-本机基线.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-本机基线.md` |
| `streaming.config-inventory` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/配置写入覆盖.md` |
| `streaming.config-inventory` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | see-also | `docs/配置写入覆盖.md` |
| `streaming.config-inventory` | [局域网串流上线前要过的六道检查](../部署清单.md) | see-also | `docs/部署清单.md` |
| `streaming.config-inventory` | [L1 通过：三项配置生效，一条判据被证伪](../reports/2026-11-24-安装验证.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-安装验证.md` |
| `streaming.deploy-checklist` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/配置写入覆盖.md` |
| `streaming.display-topology-freeze` | [局域网串流优先留在官方分支，只有需要虚拟显示器才换分支](../分支选型.md) | see-also | `docs/分支选型.md` |
| `streaming.display-topology-freeze` | [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | depends-on（反向：depended-on-by） | `docs/版本矩阵.md` |
| `streaming.display-topology-freeze` | [虚拟屏要"先切屏再连接"，且切换权不能交给 Sunshine](../虚拟显示器方案.md) | depends-on（反向：depended-on-by） | `docs/虚拟显示器方案.md` |
| `streaming.version-matrix` | [局域网串流上线前要过的六道检查](../部署清单.md) | depends-on（反向：depended-on-by） | `docs/部署清单.md` |
| `streaming.version-matrix` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/显示拓扑卡死.md` |
| `streaming.version-matrix` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | see-also | `docs/显示拓扑卡死.md` |
| `streaming.virtual-display` | [局域网串流上线前要过的六道检查](../部署清单.md) | see-also | `docs/部署清单.md` |
| `streaming.virtual-display` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/显示拓扑卡死.md` |
| `streaming.virtual-display` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | see-also | `docs/显示拓扑卡死.md` |
