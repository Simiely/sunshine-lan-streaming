---
id: hardware.vdd-install-redmibookpro15x-20261124
title: 780M 单屏机装上了虚拟屏：需要手动 extend 一次
summary: 2026-11-24 第二台设备装 MTT VDD 的记录：驱动节点 OK 但 DXGI 不枚举，DisplaySwitch /extend 后出现 DISPLAY36；配置已切 vdd 基线并保留中文。
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
  - hardware.install-redmibookpro15x-20261124:spawned-from
  - streaming.single-display-vdd-no-enumerate:spawned-from
---
# 780M 单屏机装上了虚拟屏：需要手动 extend 一次

**TL;DR**：MTT VDD `25.7.23` 装上了，`ROOT\DISPLAY\0001` 状态 OK，但单屏笔记本上 DXGI 一直只报物理屏；执行一次 `DisplaySwitch.exe /extend` 后才出现 `\\.\DISPLAY36`（1920×1080）。现已切到 vdd 基线，`locale = zh` 保留，体检 13 合格 / 7 偏离 / 16 待测。**仍未接客户端，串流与局域网拓扑未验证。**

> 一次性记录，`status: active`。安装 Sunshine 的过程见 [安装验证](2026-11-24-redmibookpro15x-安装验证.md)，新坑的通用解法见 [单屏装虚拟屏不枚举](../单屏装虚拟屏不枚举.md)。

## 安装结果

| 项 | 实测 |
|---|---|
| 驱动包 | `VDD.Control.25.7.23.zip`，SHA256 与 manifest 一致 |
| INF | `SignedDrivers\x86\VDD\MttVDD.inf`（Class=Display） |
| 设备节点 | `ROOT\DISPLAY\0001`，HardwareID `Root\MttVDD`，Status=OK |
| 虚拟屏输出 | `\\.\DISPLAY36`，1920×1080，`AttachedToDesktop=yes` |
| 驱动配置 | `C:\VirtualDisplayDriver\vdd_settings.xml`，2842 字节，无 BOM |
| 支持模式 | 1920×1080 / 2772×1272 / 2868×1320 / 2732×2048@120 / 3840×2160 / 2560×1440 |

## 关键阻碍：拓扑不枚举

第一次安装走到等待激活阶段，60 秒内 DXGI 始终只有 `\\.\DISPLAY1`（3200×2000），脚本报 `FAIL 无法唯一确定虚拟屏对应的 \\.\DISPLAYn` 并中止，`sunshine.conf` 未被改动。

诊断三条同时成立：设备节点 OK、设备管理器无感叹号、DXGI 只有一条输出——判定为"缺 extend"而非驱动装失败。执行 `DisplaySwitch.exe /extend` 后 3 秒，`DISPLAY36` 出现。

这个动作已固化进 `Install-Vdd.ps1`：轮询 3 轮无新输出时自动 extend 一次。

## 第二个坑：引号字面量

带 `-OutputName '\\.\DISPLAY36'` 重跑后，`sunshine.conf` 写成了 `output_name = '\\.\DISPLAY36'`（带引号），Sunshine 无法识别。已在 `Install-Vdd.ps1` 与 `Restore-Baseline.ps1` 中加剥引号逻辑，重跑 `Restore-Baseline.ps1 -Profile vdd` 后纠正为干净值。

## 最终 sunshine.conf

```text
origin_web_ui_allowed = lan
upnp = disabled
dd_configuration_option = ensure_only_display
locale = zh
dd_resolution_option = auto
dd_refresh_rate_option = auto
dd_hdr_option = disabled
dd_config_revert_on_disconnect = enabled
output_name = \\.\DISPLAY36
```

`locale = zh` 让 Web UI 打开就是中文；`output_name` 指向虚拟屏；`ensure_only_display` 意味着连接时物理屏会息屏，断流后回滚。

## 体检变化

| 阶段 | 合格 | 偏离 | 待测 |
|---|---|---|---|
| 装 Sunshine 后（物理屏） | 15 | 5 | 16 |
| 装虚拟屏后（vdd 基线） | 13 | 7 | 16 |

合格数下降是预期：A-03 新增一块虚拟显示适配器（2 → 3），E-03 从 `disabled` 变成 `ensure_only_display`——两项按基线定义都记为偏离，但这是**主动切换到 vdd 方案**的结果，不是回归。

## 尚未验证

- 没有 Moonlight 客户端配对，没有串流会话：F 组仍为 `❓`，AMF 编码未证实。
- 没有验证 `ensure_only_display` 的连接—断开循环：这是单屏机器，切屏失败会黑屏，救援通道（RayLink）仍在跑但未被验证能救回。
- 手机端必须打开 Moonlight 的「优化游戏设置」，否则 `dd_resolution_option=auto` 静默失效。

## 怎么验证

```powershell
# 两块屏都在，虚拟屏 AttachedToDesktop=yes
& "$env:ProgramFiles\Sunshine\tools\dxgi-info.exe" |
  Select-String 'Output Name|AttachedToDesktop|Resolution'

# output_name 不带引号
Get-Content "$env:ProgramFiles\Sunshine\config\sunshine.conf" -Encoding UTF8 |
  Select-String 'output_name|locale'
```
