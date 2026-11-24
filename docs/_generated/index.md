---
id: docs.generated.index
title: 生成索引
summary: 从 frontmatter 自动生成的导航；勿手改。
type: reference
kind: index
status: active
owner: "@platform"
source_type: doc
source: schema/taxonomy.json
last_reviewed: 2026-11-11
related: []
---

# 生成索引

> 生成文件，勿手改。运行 `python tools/repo-kit/generate.py --root . --write` 重建。

## 按 type

### how-to

| 页面 | kind | status | owner | tier | source |
|---|---|---|---|---|---|
| [局域网串流上线前要过的六道检查](../部署清单.md) | standard | active | @simiely | critical | `AGENTS.md` |
| [出包只有两步：先拉资产，再打 zip](../出包流程.md) | standard | active | @simiely | critical | `tools/build/Build-Package.ps1` |

### reference

| 页面 | kind | status | owner | tier | source |
|---|---|---|---|---|---|
| [文档索引](../index.md) | index | active | @simiely | normal | `README.md` |
| [36 项对得上，才叫装好了](../配置清单.md) | standard | active | @simiely | critical | `docs/部署清单.md` |
| [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | note | active | @simiely | critical | `https://github.com/LizardByte/Sunshine/releases` |

### explanation

| 页面 | kind | status | owner | tier | source |
|---|---|---|---|---|---|
| [局域网串流优先留在官方分支，只有需要虚拟显示器才换分支](../分支选型.md) | decision | active | @simiely | critical | `https://github.com/LizardByte/Sunshine/releases` |
| [虚拟屏要"先切屏再连接"，且切换权不能交给 Sunshine](../虚拟显示器方案.md) | standard | active | @simiely | critical | `https://github.com/VirtualDrivers/Virtual-Display-Driver` |

## Reports

| 页面 | status | owner | tier | source |
|---|---|---|---|---|
| [真机通了，但不是走局域网通的](../reports/2026-11-24-安卓真机验证.md) | active | @simiely | normal | `docs/配置清单.md` |
| [本机基线：4 项合格、7 项不合格、25 项待测](../reports/2026-11-24-本机基线.md) | archived | @simiely | normal | `docs/配置清单.md` |
| [L1 通过：三项配置生效，一条判据被证伪](../reports/2026-11-24-安装验证.md) | archived | @simiely | normal | `docs/配置清单.md` |

## Pitfalls

| 坑 | severity | 症状 | applies_to | status |
|---|---|---|---|---|
| [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | high | sunshine.conf 突然只剩两三行，先前写入的基线键消失；体检测试的合格数无故下降（本机从 14 掉到 12），upnp 与 origin_web_ui_allowed 同时回落到默认值。 | `streaming.config-inventory`, `streaming.deploy-checklist` | active |
| [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | high | 退出串流后主机冻结约两分钟，Sunshine 不再接受新连接，随后服务自行重启；期间鼠标键盘可能无响应，显示器分辨率停在串流时的值。 | `streaming.version-matrix`, `streaming.virtual-display` | active |
| [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | high | vdd_settings.xml 里的分辨率列表已经按设备改好，sunshine.conf 也指向了虚拟屏，但 DXGI 里那块屏始终是 800x600。驱动日志没有任何报错，甚至明确打印 "Using vdd_settings.xml"。 | `streaming.config-inventory`, `streaming.virtual-display` | active |

## 全部页面

| id | 标题 | type | kind | status |
|---|---|---|---|---|
| `docs.index` | [文档索引](../index.md) | reference | index | active |
| `streaming.android-verify-20261124` | [真机通了，但不是走局域网通的](../reports/2026-11-24-安卓真机验证.md) | reference | report | active |
| `streaming.baseline-20261124` | [本机基线：4 项合格、7 项不合格、25 项待测](../reports/2026-11-24-本机基线.md) | reference | report | archived |
| `streaming.branch-selection` | [局域网串流优先留在官方分支，只有需要虚拟显示器才换分支](../分支选型.md) | explanation | decision | active |
| `streaming.config-clobber` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | explanation | pitfall | active |
| `streaming.config-inventory` | [36 项对得上，才叫装好了](../配置清单.md) | reference | standard | active |
| `streaming.deploy-checklist` | [局域网串流上线前要过的六道检查](../部署清单.md) | how-to | standard | active |
| `streaming.display-topology-freeze` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | explanation | pitfall | active |
| `streaming.install-verify-20261124` | [L1 通过：三项配置生效，一条判据被证伪](../reports/2026-11-24-安装验证.md) | reference | report | archived |
| `streaming.package-build` | [出包只有两步：先拉资产，再打 zip](../出包流程.md) | how-to | standard | active |
| `streaming.vdd-config-silent-ignore` | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | explanation | pitfall | active |
| `streaming.version-matrix` | [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | reference | note | active |
| `streaming.virtual-display` | [虚拟屏要"先切屏再连接"，且切换权不能交给 Sunshine](../虚拟显示器方案.md) | explanation | standard | active |
