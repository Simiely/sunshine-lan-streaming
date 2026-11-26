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
| `hardware.baseline-redmibookpro15x-20261124` | [780M 核显机装上了 Sunshine：15 项合格，但还没接客户端](../reports/2026-11-24-redmibookpro15x-安装验证.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-安装验证.md` |
| `hardware.device-matrix` | [780M 核显单屏机：Sunshine 未装，八项偏离全来自既有环境](../reports/2026-11-24-redmibookpro15x-本机基线.md) | see-also | `docs/reports/2026-11-24-redmibookpro15x-本机基线.md` |
| `hardware.device-matrix` | [按需虚拟屏用 Sunshine 原生 ensure_only_display，prep 方案已实测否决](../按需虚拟屏选型.md) | see-also | `docs/按需虚拟屏选型.md` |
| `hardware.device-matrix` | [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/单屏装虚拟屏不枚举.md` |
| `hardware.device-matrix` | [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | see-also | `docs/单屏装虚拟屏不枚举.md` |
| `hardware.device-matrix` | [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/虚拟屏重装后不接入.md` |
| `hardware.device-standard` | [本机跑通不等于换机可复现：两台实测设备的差异](../设备矩阵.md) | see-also | `docs/设备矩阵.md` |
| `hardware.device-standard` | [卡片选分辨率靠 dd_resolution_option=auto，静态表是它的候选集](../Moonlight卡片分辨率.md) | see-also | `docs/Moonlight卡片分辨率.md` |
| `hardware.install-redmibookpro15x-20261124` | [780M 单屏机装上了虚拟屏：需要手动 extend 一次](../reports/2026-11-24-redmibookpro15x-虚拟屏安装.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-虚拟屏安装.md` |
| `hardware.vdd-install-redmibookpro15x-20261124` | [按需虚拟屏第一次尝试失败：prep 切屏卡死连接，改用原生 ensure_only_display](../reports/2026-11-24-redmibookpro15x-按需虚拟屏.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-按需虚拟屏.md` |
| `streaming.4070s-deploy-20261125` | [干净机器上三步全绿：ViGEmBus 自动安装闭环，无需重启即可全新部署](../reports/2026-11-26-redmibookpro15x-全新安装验证.md) | see-also | `docs/reports/2026-11-26-redmibookpro15x-全新安装验证.md` |
| `streaming.4070s-deploy-20261125` | [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/ViGEmBus卸载残留不必重启.md` |
| `streaming.4070s-deploy-20261125` | [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md) | contradicts | `docs/ViGEmBus卸载残留不必重启.md` |
| `streaming.branch-selection` | [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | see-also | `docs/版本矩阵.md` |
| `streaming.config-inventory` | [780M 核显单屏机：Sunshine 未装，八项偏离全来自既有环境](../reports/2026-11-24-redmibookpro15x-本机基线.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-本机基线.md` |
| `streaming.config-inventory` | [多设备部署前先固定设备 ID 与硬件画像](../设备硬件标准.md) | see-also | `docs/设备硬件标准.md` |
| `streaming.config-inventory` | [780M 核显机装上了 Sunshine：15 项合格，但还没接客户端](../reports/2026-11-24-redmibookpro15x-安装验证.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-安装验证.md` |
| `streaming.config-inventory` | [真机通了，但不是走局域网通的](../reports/2026-11-24-安卓真机验证.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-安卓真机验证.md` |
| `streaming.config-inventory` | [本机基线：4 项合格、7 项不合格、25 项待测](../reports/2026-11-24-本机基线.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-本机基线.md` |
| `streaming.config-inventory` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/配置写入覆盖.md` |
| `streaming.config-inventory` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | see-also | `docs/配置写入覆盖.md` |
| `streaming.config-inventory` | [局域网串流上线前要过的六道检查](../部署清单.md) | see-also | `docs/部署清单.md` |
| `streaming.config-inventory` | [L1 通过：三项配置生效，一条判据被证伪](../reports/2026-11-24-安装验证.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-安装验证.md` |
| `streaming.config-inventory` | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/虚拟屏配置不生效.md` |
| `streaming.deploy-checklist` | [多设备部署前先固定设备 ID 与硬件画像](../设备硬件标准.md) | see-also | `docs/设备硬件标准.md` |
| `streaming.deploy-checklist` | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/配置写入覆盖.md` |
| `streaming.display-topology-freeze` | [局域网串流优先留在官方分支，只有需要虚拟显示器才换分支](../分支选型.md) | see-also | `docs/分支选型.md` |
| `streaming.display-topology-freeze` | [待机时虚拟屏必须离开桌面拓扑，连接时再交给 Sunshine 拉起](../虚拟屏待机隐藏.md) | depends-on（反向：depended-on-by） | `docs/虚拟屏待机隐藏.md` |
| `streaming.display-topology-freeze` | [官方只有一个版本适合长期停留：2026.516](../版本矩阵.md) | depends-on（反向：depended-on-by） | `docs/版本矩阵.md` |
| `streaming.display-topology-freeze` | [虚拟屏要"先切屏再连接"，且切换权不能交给 Sunshine](../虚拟显示器方案.md) | depends-on（反向：depended-on-by） | `docs/虚拟显示器方案.md` |
| `streaming.fresh-install-redmibookpro15x-20261126` | [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md) | see-also | `docs/ViGEmBus卸载残留不必重启.md` |
| `streaming.moonlight-card-resolution` | [用 6 张分辨率卡片代替在客户端反复改设置](../安装Moonlight卡片.md) | see-also | `docs/安装Moonlight卡片.md` |
| `streaming.moonlight-card-resolution` | [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | see-also | `docs/prep命令改不了捕获屏.md` |
| `streaming.no-login-panel` | [待机时虚拟屏必须离开桌面拓扑，连接时再交给 Sunshine 拉起](../虚拟屏待机隐藏.md) | see-also | `docs/虚拟屏待机隐藏.md` |
| `streaming.on-demand-vdd-choice` | [用 6 张分辨率卡片代替在客户端反复改设置](../安装Moonlight卡片.md) | see-also | `docs/安装Moonlight卡片.md` |
| `streaming.on-demand-vdd-choice` | [卡片选分辨率靠 dd_resolution_option=auto，静态表是它的候选集](../Moonlight卡片分辨率.md) | see-also | `docs/Moonlight卡片分辨率.md` |
| `streaming.on-demand-vdd-choice` | [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/prep命令改不了捕获屏.md` |
| `streaming.on-demand-vdd-choice` | [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | see-also | `docs/prep命令改不了捕获屏.md` |
| `streaming.prep-cmd-cannot-switch-capture` | [按需虚拟屏第一次尝试失败：prep 切屏卡死连接，改用原生 ensure_only_display](../reports/2026-11-24-redmibookpro15x-按需虚拟屏.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-按需虚拟屏.md` |
| `streaming.single-display-vdd-no-enumerate` | [780M 单屏机装上了虚拟屏：需要手动 extend 一次](../reports/2026-11-24-redmibookpro15x-虚拟屏安装.md) | spawned-from（反向：spawned） | `docs/reports/2026-11-24-redmibookpro15x-虚拟屏安装.md` |
| `streaming.single-display-vdd-no-enumerate` | [按需虚拟屏用 Sunshine 原生 ensure_only_display，prep 方案已实测否决](../按需虚拟屏选型.md) | see-also | `docs/按需虚拟屏选型.md` |
| `streaming.single-display-vdd-no-enumerate` | [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md) | see-also | `docs/虚拟屏重装后不接入.md` |
| `streaming.vdd-config-silent-ignore` | [出包只有两步：先拉资产，再打 zip](../出包流程.md) | see-also | `docs/出包流程.md` |
| `streaming.vdd-idle-hide` | [4070S 从零部署闭环：装完即可串流，断开回到隐藏态](../reports/2026-11-25-4070s-部署验证.md) | see-also | `docs/reports/2026-11-25-4070s-部署验证.md` |
| `streaming.vdd-idle-hide` | [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md) | see-also | `docs/虚拟屏重装后不接入.md` |
| `streaming.version-matrix` | [局域网串流上线前要过的六道检查](../部署清单.md) | depends-on（反向：depended-on-by） | `docs/部署清单.md` |
| `streaming.version-matrix` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/显示拓扑卡死.md` |
| `streaming.version-matrix` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | see-also | `docs/显示拓扑卡死.md` |
| `streaming.version-matrix` | [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/ViGEmBus卸载残留不必重启.md` |
| `streaming.virtual-display` | [局域网串流上线前要过的六道检查](../部署清单.md) | see-also | `docs/部署清单.md` |
| `streaming.virtual-display` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/显示拓扑卡死.md` |
| `streaming.virtual-display` | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | see-also | `docs/显示拓扑卡死.md` |
| `streaming.virtual-display` | [按需虚拟屏用 Sunshine 原生 ensure_only_display，prep 方案已实测否决](../按需虚拟屏选型.md) | see-also | `docs/按需虚拟屏选型.md` |
| `streaming.virtual-display` | [出包只有两步：先拉资产，再打 zip](../出包流程.md) | see-also | `docs/出包流程.md` |
| `streaming.virtual-display` | [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/prep命令改不了捕获屏.md` |
| `streaming.virtual-display` | [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/单屏装虚拟屏不枚举.md` |
| `streaming.virtual-display` | [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | see-also | `docs/单屏装虚拟屏不枚举.md` |
| `streaming.virtual-display` | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/虚拟屏配置不生效.md` |
| `streaming.virtual-display` | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | see-also | `docs/虚拟屏配置不生效.md` |
| `streaming.virtual-display` | [待机时虚拟屏必须离开桌面拓扑，连接时再交给 Sunshine 拉起](../虚拟屏待机隐藏.md) | see-also | `docs/虚拟屏待机隐藏.md` |
| `streaming.virtual-display` | [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md) | applies-to（反向：has-pitfall；来自 applies_to 字段） | `docs/虚拟屏重装后不接入.md` |
| `streaming.virtual-display` | [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md) | see-also | `docs/虚拟屏重装后不接入.md` |
