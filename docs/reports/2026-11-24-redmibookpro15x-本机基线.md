---
id: hardware.baseline-redmibookpro15x-20261124
title: 780M 核显单屏机：Sunshine 未装，八项偏离全来自既有环境
summary: 2026-11-24 第二台设备的装机前基线：AMD Radeon 780M、3200x2000 单屏、7 项合格 / 8 项偏离 / 21 项待测。
type: reference
kind: report
status: active
owner: "@simiely"
tier: normal
topics: [hardware, streaming]
source_type: doc
source: docs/配置清单.md
last_reviewed: 2026-11-24
related:
  - hardware.device-matrix:see-also
  - streaming.config-inventory:spawned-from
---
# 780M 核显单屏机：Sunshine 未装，八项偏离全来自既有环境

**TL;DR**：这是库里第二台设备，硬件与第一台完全不同——AMD Radeon 780M 核显、3200×2000 单屏、笔记本 WLAN。36 项体检结果 7 合格 / 8 偏离 / 21 待测；8 项偏离没有一项是"装错了"，全部是既有环境。**它证明了第一台的数值不能照抄**：编码器不会是 `nvenc`，锚点分辨率要重新确认。

> 装机前快照，`status: active`。清单项定义见 [配置清单](../配置清单.md)，跨机对照见 [设备矩阵](../设备矩阵.md)。

## 设备身份

| 字段 | 实测值 |
|---|---|
| `device_id` | `redmibookpro15x` |
| `COMPUTERNAME` | `REDMIBOOKPRO15X` |
| `uuid` | `23200829-5CC3-36F3-BF39-5CC336F3BF3A` |
| `vendor` / `model` | XIAOMI / Redmi Book Pro 15 2023 |
| `cpu` | AMD Ryzen 7 7840HS w/ Radeon 780M（8 核 / 16 线程） |
| 内存 | 14,685,163,520 字节（约 13.7 GB） |
| OS | Windows 11 IoT 企业版 LTSC `10.0.26100`，64 位 |
| Sunshine | 未安装 |
| 磁盘 | C: 1.1 TB，可用 924 GB |

## 环境快照

| 项 | 实测值 | 取值方式 |
|---|---|---|
| GPU | AMD Radeon 780M Graphics `31.0.23013.1023` | `Win32_VideoController` |
| 第三方虚拟显示适配器 | `OrayIddDriver Device` `17.50.19.949X`、`RayLink Virtual Display Adapter` `1.0.2.0X` | 同上 |
| 活动显示器 | 1 个：`TL156MDMP31-0`，3200×2000 | `WmiMonitorID` |
| 业务网卡 | WLAN `192.168.2.179/24` | `Get-NetIPAddress` |
| 其它接口 | `vgate0` `172.30.226.1/32` | 同上 |
| 电源 | 睡眠 / 快速启动均可用 | `powercfg /a` |
| 智能应用控制 | `0`（关闭） | `CI\Policy` |
| HAGS | 注册表未设，且无串流日志可判 | `GraphicsDrivers` |

## 七项合格

A-05 显卡驱动已记录、E-01 单活动输出、E-02 输出屏未绑定、E-03 内置切屏默认关闭、G-01 向日葵已停、G-03 ToDesk 已停、H-03 智能应用控制关闭。

## 八项偏离

| 编号 | 项 | 实测 | 性质 |
|---|---|---|---|
| A-03 | 虚拟显示适配器 | 2 个（期望 0） | 既有环境，与安装无关 |
| C-02 | 防火墙规则 | 无 Sunshine 规则 | 未安装，属预期 |
| D-02 | Web UI 来源 | 未设置（默认 `wan`） | 待安装时写入基线 |
| D-03 | UPnP | 未设置（默认开启） | 待安装时写入基线，属安全暴露 |
| D-04 | 干扰网卡 | 2 个接口 | 既有环境 |
| G-02 | RayLinkService | `Running` | 既有环境，串流前须停 |
| H-01 | 睡眠 / 休眠 | 可用 | 既有环境 |
| H-02 | 快速启动 | 可用 | 既有环境 |

## 与第一台的关键差异

- **编码器**：第一台日志是 `hevc_nvenc`；这台是 AMD，预期走 `amf`，F-01 的合格线不能写死 `nvenc`。未串流前一律记 `unknown`。
- **分辨率**：第一台物理屏 2560×1440，把 1920×1080 当虚拟屏识别锚点；这台原生 3200×2000，锚点仍可用但必须实测确认，且客户端可请求的档位表里没有 3200×2000。
- **屏幕数量**：第一台是 2 个活动实例，这台是 1 个。单屏机器切屏失败就没有退路——装 VDD 前必须先准备救援通道。
- **网络**：第一台业务口在 `10.4.240.0/23`，这台只有 WLAN `192.168.2.0/24`；两者都不是"手机连宿主热点"的拓扑。

## 尚未证明什么

- 没有装 Sunshine，没有验证任何串流行为、端口、服务与配置写入。
- 没有确认 AMF 在这台机器上能否正常编码，也没有记录码率与色彩。
- 没有验证局域网拓扑：客户端侧数据缺失。

## 怎么验证

```powershell
# 重跑同一份体检，与本页逐项对比；只有发生过变更的项应当不同
powershell -ExecutionPolicy Bypass -File payload\scripts\Get-Baseline.ps1 -Json
```

判断标准：若 `device_id` 变了而 UUID 没变，说明主机名被改过，需要决定是否合并两份报告；若 UUID 也变了，就是第三台设备。
