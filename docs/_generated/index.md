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
| [用 6 张分辨率卡片代替在客户端反复改设置](../安装Moonlight卡片.md) | standard | active | @simiely | normal | `payload/scripts/Install-Cards.ps1` |
| [出包只有两步：先拉资产，再打 zip](../出包流程.md) | standard | active | @simiely | critical | `tools/build/Build-Package.ps1` |

### reference

| 页面 | kind | status | owner | tier | source |
|---|---|---|---|---|---|
| [文档索引](../index.md) | index | active | @simiely | normal | `README.md` |
| [本机跑通不等于换机可复现：两台实测设备的差异](../设备矩阵.md) | note | active | @simiely | normal | `docs/设备硬件标准.md` |
| [多设备部署前先固定设备 ID 与硬件画像](../设备硬件标准.md) | standard | active | @simiely | critical | `payload/scripts/Get-Baseline.ps1` |
| [36 项对得上，才叫装好了](../配置清单.md) | standard | active | @simiely | critical | `docs/部署清单.md` |
| [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | note | active | @simiely | critical | `https://github.com/LizardByte/Sunshine/releases` |

### explanation

| 页面 | kind | status | owner | tier | source |
|---|---|---|---|---|---|
| [局域网串流优先留在官方分支，只有需要虚拟显示器才换分支](../分支选型.md) | decision | active | @simiely | critical | `https://github.com/LizardByte/Sunshine/releases` |
| [卡片选分辨率靠 dd_resolution_option=auto，静态表是它的候选集](../Moonlight卡片分辨率.md) | note | active | @simiely | critical | `https://github.com/LizardByte/Sunshine/tree/v2026.516.143833/src/display_device.cpp` |
| [按需虚拟屏用 Sunshine 原生 ensure_only_display，prep 方案已实测否决](../按需虚拟屏选型.md) | decision | active | @simiely | critical | `https://github.com/Zayrick/sunshine-vdisplay/` |
| [虚拟屏要"先切屏再连接"，且切换权不能交给 Sunshine](../虚拟显示器方案.md) | standard | active | @simiely | critical | `https://github.com/VirtualDrivers/Virtual-Display-Driver` |

## Reports

| 页面 | status | owner | tier | source |
|---|---|---|---|---|
| [780M 核显单屏机：Sunshine 未装，八项偏离全来自既有环境](../reports/2026-11-24-redmibookpro15x-本机基线.md) | active | @simiely | normal | `docs/配置清单.md` |
| [780M 核显机装上了 Sunshine：15 项合格，但还没接客户端](../reports/2026-11-24-redmibookpro15x-安装验证.md) | active | @simiely | normal | `docs/配置清单.md` |
| [按需虚拟屏第一次尝试失败：prep 切屏卡死连接，改用原生 ensure_only_display](../reports/2026-11-24-redmibookpro15x-按需虚拟屏.md) | active | @simiely | normal | `docs/prep命令改不了捕获屏.md` |
| [780M 单屏机装上了虚拟屏：需要手动 extend 一次](../reports/2026-11-24-redmibookpro15x-虚拟屏安装.md) | active | @simiely | normal | `docs/配置清单.md` |
| [真机通了，但不是走局域网通的](../reports/2026-11-24-安卓真机验证.md) | active | @simiely | normal | `docs/配置清单.md` |
| [本机基线：4 项合格、7 项不合格、25 项待测](../reports/2026-11-24-本机基线.md) | archived | @simiely | normal | `docs/配置清单.md` |
| [L1 通过：三项配置生效，一条判据被证伪](../reports/2026-11-24-安装验证.md) | archived | @simiely | normal | `docs/配置清单.md` |

## Pitfalls

| 坑 | severity | 症状 | applies_to | status |
|---|---|---|---|---|
| [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | high | sunshine.conf 突然只剩两三行，先前写入的基线键消失；体检测试的合格数无故下降（本机从 14 掉到 12），upnp 与 origin_web_ui_allowed 同时回落到默认值。 | `streaming.config-inventory`, `streaming.deploy-checklist` | active |
| [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | high | 退出串流后主机冻结约两分钟，Sunshine 不再接受新连接，随后服务自行重启；期间鼠标键盘可能无响应，显示器分辨率停在串流时的值。 | `streaming.version-matrix`, `streaming.virtual-display` | active |
| [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | high | 配好 global_prep_cmd（do 启用虚拟屏并 DisplaySwitch /external）后，Moonlight 点卡片连接失败。sunshine.log 停在编码器探测中途（最后一行是某个 encoder 的 AMF via D3D11），既没有 Executing Do Cmd，也没有 New streaming session started；Switch-Vdd 的日志里没有本次 connect 记录。 | `streaming.on-demand-vdd-choice`, `streaming.virtual-display` | active |
| [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | high | MTT VDD 驱动装好了（Get-PnpDevice 显示 ROOT\DISPLAY\0001，Status=OK），但 dxgi-info 只列出物理屏一块，等待 60 秒仍无新输出，安装脚本报「无法唯一确定虚拟屏对应的 DISPLAYn」而中止，sunshine.conf 未被改动。 | `hardware.device-matrix`, `streaming.virtual-display` | active |
| [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | high | vdd_settings.xml 里的分辨率列表已经按设备改好，sunshine.conf 也指向了虚拟屏，但 DXGI 里那块屏始终是 800x600。驱动日志没有任何报错，甚至明确打印 "Using vdd_settings.xml"。 | `streaming.config-inventory`, `streaming.virtual-display` | active |

## 全部页面

| id | 标题 | type | kind | status |
|---|---|---|---|---|
| `docs.index` | [文档索引](../index.md) | reference | index | active |
| `hardware.baseline-redmibookpro15x-20261124` | [780M 核显单屏机：Sunshine 未装，八项偏离全来自既有环境](../reports/2026-11-24-redmibookpro15x-本机基线.md) | reference | report | active |
| `hardware.device-matrix` | [本机跑通不等于换机可复现：两台实测设备的差异](../设备矩阵.md) | reference | note | active |
| `hardware.device-standard` | [多设备部署前先固定设备 ID 与硬件画像](../设备硬件标准.md) | reference | standard | active |
| `hardware.install-redmibookpro15x-20261124` | [780M 核显机装上了 Sunshine：15 项合格，但还没接客户端](../reports/2026-11-24-redmibookpro15x-安装验证.md) | reference | report | active |
| `hardware.ondemand-vdd-redmibookpro15x-20261124` | [按需虚拟屏第一次尝试失败：prep 切屏卡死连接，改用原生 ensure_only_display](../reports/2026-11-24-redmibookpro15x-按需虚拟屏.md) | reference | report | active |
| `hardware.vdd-install-redmibookpro15x-20261124` | [780M 单屏机装上了虚拟屏：需要手动 extend 一次](../reports/2026-11-24-redmibookpro15x-虚拟屏安装.md) | reference | report | active |
| `streaming.android-verify-20261124` | [真机通了，但不是走局域网通的](../reports/2026-11-24-安卓真机验证.md) | reference | report | active |
| `streaming.baseline-20261124` | [本机基线：4 项合格、7 项不合格、25 项待测](../reports/2026-11-24-本机基线.md) | reference | report | archived |
| `streaming.branch-selection` | [局域网串流优先留在官方分支，只有需要虚拟显示器才换分支](../分支选型.md) | explanation | decision | active |
| `streaming.config-clobber` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | explanation | pitfall | active |
| `streaming.config-inventory` | [36 项对得上，才叫装好了](../配置清单.md) | reference | standard | active |
| `streaming.deploy-checklist` | [局域网串流上线前要过的六道检查](../部署清单.md) | how-to | standard | active |
| `streaming.display-topology-freeze` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | explanation | pitfall | active |
| `streaming.install-moonlight-cards` | [用 6 张分辨率卡片代替在客户端反复改设置](../安装Moonlight卡片.md) | how-to | standard | active |
| `streaming.install-verify-20261124` | [L1 通过：三项配置生效，一条判据被证伪](../reports/2026-11-24-安装验证.md) | reference | report | archived |
| `streaming.moonlight-card-resolution` | [卡片选分辨率靠 dd_resolution_option=auto，静态表是它的候选集](../Moonlight卡片分辨率.md) | explanation | note | active |
| `streaming.on-demand-vdd-choice` | [按需虚拟屏用 Sunshine 原生 ensure_only_display，prep 方案已实测否决](../按需虚拟屏选型.md) | explanation | decision | active |
| `streaming.package-build` | [出包只有两步：先拉资产，再打 zip](../出包流程.md) | how-to | standard | active |
| `streaming.prep-cmd-cannot-switch-capture` | [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | explanation | pitfall | active |
| `streaming.single-display-vdd-no-enumerate` | [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | explanation | pitfall | active |
| `streaming.vdd-config-silent-ignore` | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | explanation | pitfall | active |
| `streaming.version-matrix` | [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | reference | note | active |
| `streaming.virtual-display` | [虚拟屏要"先切屏再连接"，且切换权不能交给 Sunshine](../虚拟显示器方案.md) | explanation | standard | active |
