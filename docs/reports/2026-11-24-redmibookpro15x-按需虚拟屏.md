---
id: hardware.ondemand-vdd-redmibookpro15x-20261124
title: 按需虚拟屏第一次尝试失败：prep 切屏卡死连接，改用原生 ensure_only_display
summary: 2026-11-24 在 redmibookpro15x 上用 global_prep_cmd 切虚拟屏，连接卡在编码器探测；改回 Sunshine 原生 ensure_only_display，待真机复测。
type: reference
kind: report
status: active
owner: "@simiely"
tier: normal
topics: [hardware, streaming]
source_type: doc
source: docs/prep命令改不了捕获屏.md
last_reviewed: 2026-11-24
related:
  - hardware.vdd-install-redmibookpro15x-20261124:spawned-from
  - streaming.prep-cmd-cannot-switch-capture:spawned-from
---
# 按需虚拟屏第一次尝试失败：prep 切屏卡死连接，改用原生 ensure_only_display

**TL;DR**：目标是"平时只有物理屏，Moonlight 连上才切虚拟屏"。先用 `global_prep_cmd` + 外部脚本实现，脚本单独跑能成功，但**真实连接失败**——Sunshine 的 prep 在编码器探测之后才执行，且 `dd_configuration_option = disabled` 会触发后台回滚，两者叠加把 launch 卡死。已改回原生 `ensure_only_display` + 虚拟屏设备常驻启用，等待真机复测。

> 一次性记录，`status: active`。失败机理见 [prep 命令改不了捕获屏](../prep命令改不了捕获屏.md)，方案对比见 [按需虚拟屏选型](../按需虚拟屏选型.md)。

## 失败现场

配置：

```text
dd_configuration_option = disabled
output_name =
global_prep_cmd = [{"do":"powershell ... Switch-Vdd.ps1 -Mode connect","undo":"... -Mode disconnect","elevated":true}]
```

Moonlight 点卡片后连接失败。`sunshine.log`：

```text
[00:05:24.995] Info: Encoder reenumeration is required
[00:05:25.116] Info: Desktop resolution [3200x2000]
[00:05:25.588] Info: [D3D11VA @ ...] AMF via D3D11.
（此后无输出）
```

- 无 `Executing Do Cmd`；
- 无 `New streaming session started`；
- `switch-vdd.log` 无本次 connect 记录。

即：prep 一次都没跑，卡在 `probe_encoders()` 中途。

## 两个根因

1. **顺序**：`nvhttp.cpp` 的 `launch()` 是 `configure_display` → `probe_encoders` → `proc::execute(appid)`。prep 最后执行，此时捕获屏和编码器已按物理屏初始化，再切拓扑无效。
2. **回滚冲突**：`display_device.cpp` 里 `dd_configuration_option = disabled` 会调用 `revert_configuration()`（`try_indefinitely_with_delay`，默认 3 秒延迟）。它在后台反复回滚显示配置，与 `probe_encoders` 抢 DXGI 设备，把探测卡住。

**结论**：`disabled` 不等于"Sunshine 完全不碰显示"，它仍会主动回滚。

## 现行配置

```text
dd_configuration_option = ensure_only_display
dd_resolution_option = auto
dd_refresh_rate_option = auto
dd_hdr_option = disabled
output_name = \\.\DISPLAY54
# 不写 global_prep_cmd
```

配套状态：

- 虚拟屏设备常驻启用（`ConfigFlags=0`），保证 probe 能枚举；
- 桌面拓扑平时只留物理屏（`DisplaySwitch /internal`）；
- 连接时 Sunshine 切到虚拟屏，断开回滚。

## 代价

- 做不到"设备级禁用虚拟屏"，只能做到"不占桌面"。这是 `probe_encoders` 的硬约束。
- `output_name` 记的是 `\\.\DISPLAYn`，重启或重新启用设备后编号可能变；连不上时先跑 `dxgi-info` 核对。

## 未验证

- `ensure_only_display` 的真实连接—断开循环：本机未配对客户端，2026.516 的 Web API 也没有 launch 端点（`confighttp.cpp` 只有 `GET/POST /api/apps`、`DELETE`、`/api/apps/close`）。
- 断开回滚是否会出现 [显示拓扑卡死](../显示拓扑卡死.md) 记录的两分钟阻塞——设备常驻启用理论上能避免，但无真机证据。

## 怎么验证

1. 连接后 `sunshine.log` 应有 `New streaming session started` 与 `CLIENT CONNECTED`。
2. 虚拟屏 `Resolution` 等于客户端请求值（`dxgi-info`）。
3. 断开后 10 秒内物理屏恢复，虚拟屏回到 `Attached=no`。
