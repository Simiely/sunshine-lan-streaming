---
id: streaming.vigem-uninstall-no-reboot
title: ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装
summary: 4070S 上"StopPending 只能重启"的结论来自删错了顺序；按设备节点→服务→驱动包→文件的顺序清理，可以在不重启的机器上当天重装并自动建起 ViGEmBus。
type: explanation
kind: pitfall
status: active
owner: "@simiely"
tier: critical
topics: [streaming]
source_type: doc
source: docs/reports/2026-11-26-redmibookpro15x-全新安装验证.md
last_reviewed: 2026-11-26
symptom: '重装 v0.6.0 时 Install.ps1 报 ViGEmBus 服务处于 StopPending，安装器退出 0 但服务起不来，提示"请重启 Windows 后重新运行"。'
cause: '先删了正在运行的内核驱动文件，SCM 里的服务对象卡在删除挂起；注册表已无、服务对象仍在。这是清理顺序错误造成的人为残局，不是 ViGEmBus 本身要求重启。'
detect: 'Get-Service ViGEmBus 显示 StopPending，或 sc query 返回 1061/1072；同时 HKLM\SYSTEM\CurrentControlSet\Services\ViGEmBus 已不存在。'
avoid: '清理顺序必须是：删设备节点 → 停服务 → 删除服务 → 删驱动包 → 删 sys 文件。不要先动 sys 文件或先删服务键。'
recover: '按上述顺序重做一次即可；本次实测 Stop-Service 成功、sc delete 成功、pnputil 删驱动包成功，全程未重启，随后同机重装 ViGEmBus 自动安装并 Running。'
applies_to:
  - streaming.4070s-deploy-20261125
  - streaming.version-matrix
severity: medium
related:
  - streaming.4070s-deploy-20261125:contradicts
  - streaming.fresh-install-redmibookpro15x-20261126:see-also
---
# ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装

**TL;DR**：[4070S 报告](reports/2026-11-25-4070s-部署验证.md)写"只能重启"是被一次错误顺序制造出来的残局骗了。按正确顺序清理，内核驱动可以当场卸载、当场重装，不需要重启。

## 现象

重装时 `Install.ps1` 在第 6 步停下：

```
WARN  ViGEmBus 服务处于删除挂起状态（StopPending），请重启 Windows 后重新运行
```

安装器返回 0，服务却始终起不来——看起来只能重启。

## 根因

4070S 那次是先手工删掉了正在运行的 `ViGEmBus.sys`，再从 SCM 删服务。内核驱动已加载、文件却没了，服务对象卡在 `StopPending`，`sc stop` 报 1061、`sc delete` 报 1072。**这个状态是清理顺序造成的，不是驱动本身的约束。**

结论应改为：*"在那个残局下只能重启"*，而不是*"ViGEmBus 卸载必须重启"*。

## 正确顺序

```powershell
# 1. 删设备节点（先做，卸载驱动后它就不阻碍服务停止）
pnputil /remove-device "ROOT\SYSTEM\0003"

# 2. 停服务；停不下来就别往下走，避免制造 StopPending
Stop-Service ViGEmBus -Force

# 3. 删服务：sc delete 成功即无重启挂起
sc.exe delete ViGEmBus

# 4. 删驱动包（发布名从 pnputil /enum-drivers 里按 vigembus.inf 定位）
pnputil /delete-driver oem54.inf /force

# 5. 最后才处理 sys 文件；驱动包删掉后通常已不存在
```

本机实测：设备节点 `ROOT\SYSTEM\0003` 删除成功、`Stop-Service` 成功、`sc delete` 成功、`oem54.inf` 删除成功、`sys` 文件已不在；`PendingFileRenameOperations` 中 ViGEm 项为 0。随后同机全新安装，`Install.ps1` 自动重装 ViGEmBus，服务 Running。

## 两个会让人误判的坑

**中文 PnP 输出**。官方卸载脚本和仿写脚本常用英文正则 `Instance ID:` / `Published Name:` / `Original Name:`。中文 Windows 上 `pnputil` 输出的是 `实例 ID:` / `发布名称:` / `原始名称:`，正则一个都匹配不到，于是脚本认为"没有设备和驱动包"，服务自然停不下来——看起来又像"必须重启"。兼容写法是把中英标签都放进正则，并按空行分块解析驱动包，避免跨块误取到别的 `oemNN.inf`。

**系统原有重启挂起项**。本机 `PendingFileRenameOperations` 有 6410 条来自输入法等软件的历史项。判断本次清理是否引入重启需求，只能看新增的 ViGEm / Sunshine 相关项，不能看总数。

## 怎么验证

```powershell
# 清完后应该是：服务不存在、无设备节点、驱动库无 vigembus.inf、sys 文件不在
Get-Service ViGEmBus
pnputil /enum-devices /deviceid "Nefarius\ViGEmBus\Gen1"
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' PendingFileRenameOperations) |
  Where-Object { $_ -match '(?i)vigem' }

# 重装后应该自动回来
Get-Service ViGEmBus   # Running
```

完整实测证据见 [2026-11-26 全新安装验证](reports/2026-11-26-redmibookpro15x-全新安装验证.md)。
