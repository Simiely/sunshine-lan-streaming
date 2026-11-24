---
id: docs.index
title: 文档索引
summary: sunshine-lan-streaming 的人工导航；生成索引见 _generated/index.md。
type: reference
kind: index
status: active
owner: "@simiely"
topics: [governance]
source_type: doc
source: README.md
last_reviewed: 2026-11-24
related: []
---
# 文档索引

本页只做人工导航；完整页面索引、反向链接与踩坑清单由生成器产出：

- [生成索引](_generated/index.md)
- [反向链接](_generated/backlinks.md)
- [踩坑索引](_generated/pitfalls.md)

## 开始

- [README](../README.md) — 这个库是什么、怎么用
- [AGENTS](../AGENTS.md) — AI / 维护者入口与写作约定

## 主题

### 选型

- [分支选型](分支选型.md) — 什么时候该换分支，什么时候不该
- [版本矩阵](版本矩阵.md) — 官方稳定版时间线与各自的问题

### 实施

- [虚拟显示器方案](虚拟显示器方案.md) — 三条路线与切换时序
- [出包流程](出包流程.md) — 两条命令产出离线 zip：先拉资产，再打包
- [安装 Moonlight 卡片](安装Moonlight卡片.md) — 6 张分辨率卡，Moonlight 按卡记住分辨率，点卡即用
- [部署清单](部署清单.md) — 上线前要过的六道检查

### 设备与硬件

- [设备硬件标准](设备硬件标准.md) — 多设备部署前先固定设备 ID、硬件画像与配置覆盖
- [设备矩阵](设备矩阵.md) — 两台实测设备的差异：哪些结论跨机通用，哪些只属于某一台

### 配置与记录

- [配置清单](配置清单.md) — 10 组 36 项基线，每项带取法、合格线与偏离处置
- [本机基线（2026-11-24）](reports/2026-11-24-本机基线.md) — 4070S 宿主首次实测：4 项合格、7 项偏离、25 项待测
- [redmibookpro15x 本机基线（2026-11-24）](reports/2026-11-24-redmibookpro15x-本机基线.md) — 第二台设备：780M 核显、3200x2000 单屏，7 项合格、8 项偏离、21 项待测
- [redmibookpro15x 安装验证（2026-11-24）](reports/2026-11-24-redmibookpro15x-安装验证.md) — Sunshine 2026.516 装上，15 项合格；未配对客户端，串流与局域网拓扑尚未验证
- [redmibookpro15x 虚拟屏安装（2026-11-24）](reports/2026-11-24-redmibookpro15x-虚拟屏安装.md) — MTT VDD 装上，单屏需 extend；已切 vdd 基线，中文保留
- [redmibookpro15x 按需虚拟屏（2026-11-24）](reports/2026-11-24-redmibookpro15x-按需虚拟屏.md) — 改成连接才拉起：connect/disconnect 实测通过，会话触发待真机
- [安装验证（2026-11-24）](reports/2026-11-24-安装验证.md) — L1 通过；一条判据被证伪，以及 `0.0.0.0` 绑定带出的暴露面
- [安卓真机验证（2026-11-24）](reports/2026-11-24-安卓真机验证.md) — 真机跑通 HEVC/1440p/60fps，但链路是宿主热点而非局域网

### 踩坑

- [显示拓扑卡死](显示拓扑卡死.md) — `ensure_only_display` 阻塞两分钟的根因与规避
- [配置写入覆盖](配置写入覆盖.md) — `POST /api/config` 整体替换，会把 `upnp` 悄悄改回 `enabled`
- [虚拟屏配置不生效](虚拟屏配置不生效.md) — `vdd_settings.xml` 带 BOM 即解析失败，虚拟屏恒为 800x600
- [单屏装虚拟屏不枚举](单屏装虚拟屏不枚举.md) — 驱动 OK 但 DXGI 只有物理屏；`DisplaySwitch /extend` 一次解决
- [按需虚拟屏选型](按需虚拟屏选型.md) — 不换驱动；切屏用原生 ensure_only_display，prep 方案已否决
- [prep 命令改不了捕获屏](prep命令改不了捕获屏.md) — 用 global_prep_cmd 切屏会卡在编码器探测，连接失败
- [Moonlight 卡片分辨率](Moonlight卡片分辨率.md) — 卡片选分辨率靠 dd_resolution_option=auto，静态表是候选集

## 边界

不要在这里复制完整页面清单；那三份文件是生成物，手改会被覆盖。
