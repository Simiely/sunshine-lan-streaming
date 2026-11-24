---
id: hardware.install-redmibookpro15x-20261124
title: 780M 核显机装上了 Sunshine：15 项合格，但还没接客户端
summary: 2026-11-24 第二台设备安装 2026.516.143833 的验证记录：服务、端口、配置、按设备状态目录全部成立；未做串流与局域网拓扑验证。
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
  - hardware.baseline-redmibookpro15x-20261124:spawned-from
  - streaming.config-inventory:spawned-from
---
# 780M 核显机装上了 Sunshine：15 项合格，但还没接客户端

**TL;DR**：`redmibookpro15x`（AMD 780M）用离线包装上了官方 Sunshine `2026.516.143833`，服务、自启、账户、防火墙、常驻端口、四项基线配置全部符合预期；状态文件按设备落到了 `ProgramData\...\devices\redmibookpro15x\`，没有与第一台机器混在一起。体检从装机前 7/8/21 变为 15 合格 / 5 偏离 / 16 待测。**局域网串流仍未验证**——没有配对客户端，按仓库规则 zip 不发布。

> 一次性记录，`status: active`。装机前快照见 [本机基线](2026-11-24-redmibookpro15x-本机基线.md)，清单项定义见 [配置清单](../配置清单.md)。

## 安装结果

| 项 | 实测 |
|---|---|
| 安装包 | `Sunshine-Windows-AMD64-installer.msi`，SHA256 与 manifest `e7208b11…` 一致 |
| 宿主版本 | `2026.516.143833` |
| 服务 | `SunshineService` · `Running` · `Automatic` · `LocalSystem` |
| 常驻端口 | `47984` / `47989` / `47990`，均由同一进程监听，`0.0.0.0` |
| 防火墙 | 2 条 Sunshine 入站 Allow，`Enabled=True` |
| 安装结果 | `install-result.json`：`device_id=redmibookpro15x`、`failures=0`、`warnings=1` |
| 提权方式 | `Start-Process -Verb RunAs` 调 `Install.ps1`，退出码 0 |

## 四项基线配置

`C:\Program Files\Sunshine\config\sunshine.conf` 无 BOM，三行：

```text
origin_web_ui_allowed = lan
upnp = disabled
dd_configuration_option = disabled
```

`upnp = disabled` 与 `origin_web_ui_allowed = lan` 从装机前的"未设置（默认不安全）"变成了显式值——D-02 / D-03 由偏离转合格。

## 按设备状态目录

`C:\ProgramData\sunshine-lan-streaming\devices\redmibookpro15x\` 下：

| 文件 | 说明 |
|---|---|
| `baseline-before-install.json` | 安装前 36 项快照（11,194 字节） |
| `install-result.json` | 版本、设备 ID、警告与失败列表 |
| `credentials.txt` | Web UI 凭据 |

这正是多设备标准化的落点：文件名与目录都带 `device_id`，换一台机器不会覆盖这里的证据。

## 体检变化

| 阶段 | 合格 | 偏离 | 待测 |
|---|---|---|---|
| 装机前 | 7 | 8 | 21 |
| 装机后 | 15 | 5 | 16 |

转正的 8 项：A-01 版本、B-01/02/03 服务三件套、C-01 常驻端口、C-02 防火墙、D-02 Web UI 来源、D-03 UPnP。

**剩余 5 项偏离**（全部是既有环境，与安装无关）：A-03 两个第三方 IDD、D-04 两个网卡接口、G-02 RayLink 仍在跑、H-01 睡眠可用、H-02 快速启动可用。

## 这一版验证到的设备适配

- `Get-Baseline.ps1 -Json` 输出 `device_id=redmibookpro15x` 与完整指纹（UUID `23200829-…`、Redmi Book Pro 15 2023、AMD Ryzen 7 7840HS、OS build 26100、GPU 只列真实显卡，排除了 Oray / RayLink 虚拟适配器）。
- `conf/devices/redmibookpro15x.json` 被自动加载：`gpu_vendor_pattern` 收敛为 AMD/Radeon，A-05 正确取到 `31.0.23013.1023`。
- `Install-Vdd.ps1` 的 SHA/size 不再写死，从随包 manifest 读取。
- 四个 `.cmd` 的提权分支透传了参数；本次安装走的是提权后的 `Install.ps1`。

## 尚未验证

- 没有 Moonlight 客户端配对，没有串流会话：F 组（编码器 / 码率 / 帧率 / 色彩）仍是 `❓`。**AMF 能否在这颗 780M 上正常编码，尚未证实。**
- 没有连到业务网段：`192.168.2.0/24` 只是宿主侧 WLAN 地址，客户端侧数据缺失，D-01 / I-03 不成立。
- 没有装 VDD：单屏笔记本切屏失败没有退路，按 [本机基线](2026-11-24-redmibookpro15x-本机基线.md) 的限制，不启用虚拟屏。
- 没有做完整连接—断开循环。

## 怎么验证

```powershell
$sd = Join-Path $env:ProgramData 'sunshine-lan-streaming\devices\redmibookpro15x'
Get-Content (Join-Path $sd 'install-result.json') -Raw -Encoding UTF8 | ConvertFrom-Json |
  Select-Object device_id, version, failures, warnings
```

合格数应为 15；若 D-02 / D-03 掉回偏离，说明配置又被整体替换写回，见 [配置写入覆盖](../配置写入覆盖.md)。
