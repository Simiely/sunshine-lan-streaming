---
id: streaming.moonlight-card-resolution
title: 卡片选分辨率靠 dd_resolution_option=auto，静态表是它的候选集
summary: Moonlight 每张应用卡片都有分辨率选项；Sunshine 按客户端请求切虚拟屏模式，前提是把模式声明在 vdd-resolutions.txt 里。
type: explanation
kind: note
status: active
owner: "@simiely"
tier: critical
topics: [hardware, streaming]
source_type: url
source: https://github.com/LizardByte/Sunshine/tree/v2026.516.143833/src/display_device.cpp
source_retrieved: 2026-11-24
last_reviewed: 2026-11-24
related:
  - streaming.on-demand-vdd-choice:see-also
  - hardware.device-standard:see-also
---
# 卡片选分辨率靠 dd_resolution_option=auto，静态表是它的候选集

**TL;DR**：用户说的"分辨率配置"不是给每张卡单独写 prep 命令，而是 Moonlight **每张应用卡片自带的分辨率/帧率选项**。Sunshine 收到请求后用 `dd_resolution_option = auto` 切虚拟屏模式——但只能切到 `vdd_settings.xml` 里声明过的模式。所以静态表是**候选集**，auto 是**选择器**，两者缺一不可。

## 三个组件的分工

| 组件 | 职责 | 位置 |
|---|---|---|
| Moonlight 应用卡片 | 用户选分辨率 / 帧率 / 码率 | 客户端，每张卡独立保存 |
| `dd_resolution_option = auto` | 按客户端请求切换虚拟屏显示模式 | `sunshine.conf` |
| `vdd-resolutions.txt` → `vdd_settings.xml` | 声明虚拟屏**支持哪些模式** | 包内配置，安装时写入 |

把 `dd_resolution_option` 设成 `disabled` 会让第 2 步停摆——客户端选了 1440p，虚拟屏仍停在初始档，表现为"选了没反应"。这正是按需虚拟屏 v0.5.2 引入的问题。

## 源码依据（v2026.516.143833）

`src/nvhttp.cpp` 的 `launch()`：

```text
display_device::configure_display(config::video, *launch_session);
video::probe_encoders();
proc::proc.execute(appid, launch_session);   // app 的 prep-cmd 在这里才跑
```

`src/display_device.cpp` 的 `parse_configuration()` 调用 `parse_resolution_option(video_config, session, config)`——**从 launch_session 取客户端请求的宽高帧率**。

顺序要点：`configure_display` 在 `probe_encoders` 之前；app 的 prep 命令在两者之后。所以**分辨率切换必须由 Sunshine 的 dd_* 机制完成，不能等 app 的 prep 命令**——那时编码器已经探测完了。

## 客户端侧必须开「优化游戏设置」

源码警告原文：

```text
Sunshine is configured to change resolution automatically,
but the "Optimize game settings" is not set in the client!
Resolution will not be changed.
```

所以 Moonlight 里每张要切分辨率的卡片，都得开「优化游戏设置 / Optimize game settings」。不开的话卡片选项只是改编码参数，不改宿主显示模式。

## 为什么仍用静态表（不是动态创建）

vdisplay/SudoVDA 能按 `SUNSHINE_CLIENT_*` 动态建任意分辨率的屏，但 [按需虚拟屏选型](按需虚拟屏选型.md) 的结论是先不换栈。静态表的代价是**表外档位不可用**——客户端选了表外值会静默失败，画面停在原档，日志无明显报错。因此表的维护就是"加卡片"的实际动作：新客户端接入时，先把它原生分辨率加进 `vdd-resolutions.txt`，重跑安装虚拟屏，再在 Moonlight 卡片里选那个值。

## 当前表覆盖的档位

`1920x1080`、`1280x720`、`2560x1440`、`3840x2160`、`1440x900`、`1920x1200`，以及各设备原生值 `2772x1272`（Find X9 Pro）、`2868x1320`（iPhone 17 Pro Max）、`2732x2048@120`（iPad Pro M1）。

**注意**：`redmibookpro15x` 物理屏是 `3200x2000`，虚拟屏初始档是 `1920x1080`；客户端选 3200x2000 时若表里没有，会停在当前档。需要时再加。

## 怎么验证

1. Moonlight 卡片设置里把分辨率改成 `2560x1440`，打开「优化游戏设置」。
2. 连接后跑 `dxgi-info`，虚拟屏 `Resolution` 应为 `2560x1440`。
3. `sunshine.log` 里搜 `Creating encoder`，其上一行应出现请求分辨率相关记录；不应出现 "Optimize game settings is not set" 警告。
