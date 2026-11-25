---
id: streaming.fresh-install-redmibookpro15x-20261126
title: 干净机器上三步全绿：ViGEmBus 自动安装闭环，无需重启即可全新部署
summary: 2026-11-26 在 redmibookpro15x 上先无重启清干净旧环境，再用 v0.6.0 一次跑通宿主、虚拟屏、分辨率卡片；独立复核服务、端口、Web UI、VDD 与配置全部到位，补齐 4070S 报告遗留的 ViGEmBus 复测项。
type: reference
kind: report
status: active
owner: "@simiely"
tier: normal
topics: [streaming, hardware]
source_type: doc
source: docs/部署清单.md
last_reviewed: 2026-11-26
related:
  - streaming.4070s-deploy-20261125:see-also
---
# 干净机器上三步全绿：ViGEmBus 自动安装闭环，无需重启即可全新部署

**TL;DR**：先把旧环境彻底清干净（含 ViGEmBus，且不产生重启挂起），再从 v0.6.0 包一次跑完三个入口：宿主、虚拟屏、分辨率卡片。三步都自报成功，独立复核也全部成立。**4070S 报告里"ViGEmBus 自动安装待干净机器复测"的缺口，在这台机器上补齐了。**

## 一、环境

| 项 | 值 |
|---|---|
| 宿主 | Redmi Book Pro 15，COMPUTERNAME `REDMIBOOKPRO15X`，device_id `redmibookpro15x` |
| 系统 | Windows 11 IoT 企业版 LTSC 10.0.26100 |
| 显卡 / 物理屏 | AMD Radeon 780M，单屏 3200×2000 |
| 安装包 | v0.6.0（`38753d9812ff77d4b8fca41f97616847c9025b36df076cffd4e24e9cfcbe6d93`），构建方式见 [出包流程](../出包流程.md) |
| 组件 | Sunshine `2026.516.143833`，MTT VDD `25.7.23`，Moonlight 便携包 `6.2.0`（客户端未在本轮验证） |

## 二、前置：无重启清空旧环境

清退顺序按 [ViGEmBus 卸载残留不必重启](../ViGEmBus卸载残留不必重启.md)：

1. Sunshine MSI 卸载：`msiexec /x {0B8229CA-...} /qn /norestart`，安装表随即无登记；`C:\Program Files\Sunshine` 的 `config\` 与 `assets\covers\` 由管理员脚本补删。
2. VDD：`Install-Vdd.ps1 -Uninstall` 移除 `ROOT\DISPLAY\0001` 与三个驱动包，向日葵 / RayLink 设备未动。
3. ViGEmBus：删设备节点 `ROOT\SYSTEM\0003` → `Stop-Service` → `sc delete` → `pnputil /delete-driver oem54.inf /force`；服务删除走的是正常路径，没有触发注册表兜底。

清完复核：`SunshineService`、ViGEmBus 服务、VDD 设备、驱动包、sys 文件、ProgramData 设备状态目录全为无；`PendingFileRenameOperations` 中 ViGEm / Sunshine 相关项为 0（系统原有 6410 条来自输入法等其他软件，与本次无关）。**全程未重启。**

## 三、部署：三个入口一次跑完

按 `Install.ps1` → `Install-Vdd.ps1` → `Install-Cards.ps1` → `Show-Result.ps1` 顺序串联，全过程无重启。

| 步骤 | 关键结果 |
|---|---|
| 宿主 | MSI 装好 2026.516.143833；**ViGEmBus 未安装 → 自动静默安装，服务 Running**；随机密码写入凭据；7 项基线落盘；自检 B-01/B-02/C-01/C-02/C-04 全过 |
| 虚拟屏 | 包内 VDD 25.7.23 SHA256 一致；`devcon install Root\MttVDD` 返回 0；单屏未枚举，自动 `DisplaySwitch /extend` 后出现 `\\.\DISPLAY57`；vdd profile 写入（`ensure_only_display` + `auto` + `auto` + 稳定 ID）；待机隐藏 `SUMMARY mode=single physical=1 virtual=0 action=hidden` |
| 卡片 | 6 张分辨率卡新增，连同 Desktop / Steam Big Picture 共 8 张；封面 6 张部署完成 |

结果弹窗给出 Web UI 地址（`https://localhost:47990`、`https://192.168.2.179:47990`）与账号密码，凭据同时落到设备状态目录的 `credentials.txt`。

## 四、独立复核（不看脚本自报）

脚本跑完后重新查询系统状态：

```
SunshineService    Running / Automatic
47984,47989,47990  0.0.0.0 监听，属主为 sunshine.exe
Web UI             https://localhost:47990  未认证 401；带 admin 凭据 200
防火墙             2 条 Sunshine 规则
ViGEmBus           服务存在
VDD                ROOT\DISPLAY\0001，Status=OK；桌面拓扑仍为 1 块物理屏
sunshine.conf      ensure_only_display / auto / auto / output_name={5eb52002-...}
apps.json          8 张卡
重启挂起           ViGEm / Sunshine 项 0
```

## 五、结论与仍缺的证据

- **成立**：干净环境下从零安装、ViGEmBus 自动安装、虚拟屏驱动与隐藏、卡片部署、凭据与基线落盘，且无需重启。4070S 报告里"ViGEmBus 干净机器复测"这一项到此闭环。
- **未闭环**：本轮未做 Moonlight 配对与真机串流，也未验证客户端与宿主同处一个广播域。按 [DEVELOPMENT.md](../../DEVELOPMENT.md) 的发布规则，本报告**不能单独作为发布 zip 的依据**，`status: active`，待串流证据补齐后归档。
- **环境项**：AweSunService（向日葵）运行中，会与 Sunshine 抢捕获；脚本按既定策略不停止它，避免切断远程通道。串流前需手动停用。
