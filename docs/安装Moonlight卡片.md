---
id: streaming.install-moonlight-cards
title: 用 6 张分辨率卡片代替在客户端反复改设置
summary: apps.json 加多张名字带分辨率的 Desktop 卡；Moonlight 按卡独立保存分辨率，点卡即用对应档位。
type: how-to
kind: standard
status: active
owner: "@simiely"
tier: normal
topics: [hardware, streaming]
source_type: code
source: payload/scripts/Install-Cards.ps1
last_reviewed: 2026-11-24
related:
  - streaming.moonlight-card-resolution:see-also
  - streaming.on-demand-vdd-choice:see-also
---
# 用 6 张分辨率卡片代替在客户端反复改设置

**TL;DR**：Moonlight 把分辨率/帧率/码率**按应用卡片分别保存**。在 Sunshine 的 `apps.json` 里放几张名字不同的 Desktop 卡，给每张设一次分辨率，之后点卡即用对应档位——不用每次进设置改。

## 装了什么

`安装分辨率卡片.cmd`（或 `Install-Cards.ps1`）会新增 6 张卡，保留原有 `Desktop` 与 `Steam Big Picture`。顺序按 **iOS → 安卓 → Switch → 电视 → 通用**：

| 卡片名 | 分辨率 | 用途 |
|---|---|---|
| `iPhone 17 Pro Max 2868x1320@60` | `2868x1320` | iOS 手机 |
| `iPad Pro 12.9 2732x2048@120` | `2732x2048@120` | iOS 平板 4:3 |
| `Find X9 Pro 2354x1080@120` | `2354x1080@120` | 安卓手机 |
| `Switch 底座 1920x1080@60` | `1920x1080` | Switch 主机 |
| `电视 4K 3840x2160@60` | `3840x2160` | 电视 4K |
| `通用 2560x1440@60` | `2560x1440` | 通用 2K |

脚本是**幂等**的：每次先移除自己生成过的卡（封面指向 `covers\res-*` 的那些），再按上表顺序重建——所以**删卡、改名、调顺序都会一次生效**，且不会碰 `Desktop` / `Steam Big Picture`。

## 每张卡有自己的封面

`payload/covers/` 下 6 张 600×800 PNG，由 `tools/build/Gen-Covers.py` 生成。版式固定三行、纯大字，没有图形：

- 第一行：设备名（自动缩放到不超边）
- 第二行：分辨率，最大号（96px 等宽字体）
- 第三行：刷新率，主色

安装时复制到 `C:\Program Files\Sunshine\assets\covers\`，`image-path` 写相对路径（`covers/res-1920x1080.png`）。Sunshine 先按安装目录的 `assets\` 找图，所以换机器也不会失效；写绝对路径则会。

改图后重生成：

```powershell
python tools/build/Gen-Covers.py
```

脚本里的 `CARDS` 列表就是唯一真源，改颜色/设备名后重跑即可，无需手工 P 图。

## 为什么卡片里不写分辨率

看起来应该在每张卡的 `prep-cmd` 里写"切到 1080p"，但 v2026.516 的源码否定了这条路：

- `nvhttp.cpp` 的 `make_launch_session()` 从客户端传来的 `mode=宽x高x帧率` 解析分辨率；
- `launch()` 顺序是 `configure_display` → `probe_encoders` → `proc::execute(appid)`（app prep 最后才跑）；
- 所以 **app prep 改不了显示模式**，那时编码器都探测完了。

分辨率切换只能由 `dd_resolution_option = auto` 完成，且前提是虚拟屏支持该模式——也就是模式必须在 `vdd-resolutions.txt` 里。详见 [Moonlight 卡片分辨率](Moonlight卡片分辨率.md)。

## Moonlight 侧要做一次的事

对**每个连接设备**：

1. 点开某张分辨率卡的设置（不是直接点卡连接）；
2. 把分辨率设成卡名对应档位，帧率按需；
3. **打开「优化游戏设置」**——不开的话 Sunshine 不改宿主分辨率，源码有明确警告；
4. 保存。之后点这张卡就会用该档位。

新设备接入先把它的原生分辨率加进 `vdd-resolutions.txt` 并重跑安装虚拟屏，否则选表外档位会静默失败、画面停在原档。

## 怎么验证

```powershell
$f = "$env:ProgramFiles\Sunshine\config\apps.json"
(Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json).apps.name
```

应看到 8 张卡。真机验证：点「桌面 · 2K」连接后，`dxgi-info` 里虚拟屏分辨率应为 `2560x1440`。

## 边界

- 卡片只是**入口名字**，分辨率存在 Moonlight 客户端里。换设备要重新设一遍。
- 本脚本不改 `sunshine.conf`，不动显示拓扑；按需切屏仍由 [按需虚拟屏](按需虚拟屏选型.md) 的 prep 命令负责。
