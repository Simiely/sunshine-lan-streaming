---
id: docs.generated.pitfalls
title: 踩坑索引
summary: 从 kind=pitfall 页面自动生成的失败模式索引；勿手改。
type: reference
kind: index
status: active
owner: "@platform"
source_type: doc
source: schema/taxonomy.json
last_reviewed: 2026-11-11
related: []
---

# 踩坑索引

> 生成文件，勿手改。运行 `python tools/repo-kit/generate.py --root . --write` 重建。
> 每个坑的权威内容在它自己的页面；本页只做导航。

## 未解决（7）

| 严重度 | 坑 | 症状 | 检测 | 适用 | status |
|---|---|---|---|---|---|
| high | [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md) | sunshine.conf 突然只剩两三行，先前写入的基线键消失；体检测试的合格数无故下降（本机从 14 掉到 12），upnp 与 origin_web_ui_allowed 同时回落到默认值。 | 看 sunshine.conf 的字节数——正常应包含全部已配置键，若只有二三十字节就是被清空了。也可对比 Get-Baseline.ps1 的合格数，D-02/D-03 同时退回 ⚠️ 即为典型信号。 | `streaming.config-inventory`, `streaming.deploy-checklist` | active |
| high | [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md) | 退出串流后主机冻结约两分钟，Sunshine 不再接受新连接，随后服务自行重启；期间鼠标键盘可能无响应，显示器分辨率停在串流时的值。 | 在 sunshine.log 里搜 Trying to revert applied display device settings，若短时间内重复出现 5 次以上、且伴随 Device does not exist in the available path source data，即命中。 | `streaming.version-matrix`, `streaming.virtual-display` | active |
| high | [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md) | 配好 global_prep_cmd（do 启用虚拟屏并 DisplaySwitch /external）后，Moonlight 点卡片连接失败。sunshine.log 停在编码器探测中途（最后一行是某个 encoder 的 AMF via D3D11），既没有 Executing Do Cmd，也没有 New streaming session started；Switch-Vdd 的日志里没有本次 connect 记录。 | 同时成立即判定：sunshine.log 无 Executing Do Cmd；有 Encoder reenumeration is required 但探测序列没有收尾的 Found H.264 encoder；Switch-Vdd/switch-vdd.log 无本次记录；客户端报连接失败而非黑屏。 | `streaming.on-demand-vdd-choice`, `streaming.virtual-display` | active |
| high | [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md) | MTT VDD 驱动装好了（Get-PnpDevice 显示 ROOT\DISPLAY\0001，Status=OK），但 dxgi-info 只列出物理屏一块，等待 60 秒仍无新输出，安装脚本报「无法唯一确定虚拟屏对应的 DISPLAYn」而中止，sunshine.conf 未被改动。 | 同时成立三点：Get-VddAdapter 返回 Status=OK；dxgi-info 的 Output Name 只有物理屏一条；设备管理器里 Virtual Display Driver 无感叹号。三条都成立即可判定「缺 extend」，不是驱动装失败。 | `hardware.device-matrix`, `streaming.virtual-display` | active |
| high | [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md) | vdd_settings.xml 里的分辨率列表已经按设备改好，sunshine.conf 也指向了虚拟屏，但 DXGI 里那块屏始终是 800x600。驱动日志没有任何报错，甚至明确打印 "Using vdd_settings.xml"。 | 三条都成立即可确认：一、看文件头三字节，EF BB BF 就是带 BOM；二、读 C:\VirtualDisplayDriver\Logs\log_YYYY-MM-DD.txt，出现 "Output target modes count: N" 且 N 与 XML 条目数不符；三、用管道发 LOG_DEBUG true 再 RELOAD_DRIVER，看有没有逐条的 "Added: 1920x1080 @ 60/1Hz"。若一条 Added 都没有就是解析失败。 | `streaming.config-inventory`, `streaming.virtual-display` | active |
| high | [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md) | 重装 VDD 后 devcon 返回 0、设备 ROOT\DISPLAY\0001 与显示器对象 MTT1337 都是 OK，但 DXGI 始终只有两块物理屏；Install-Vdd 等待 60 秒后报「无法唯一确定虚拟屏对应的 DISPLAYn」并以退出码 4 中止。 | 三条同时成立：Get-VddAdapter 返回 Status=OK；Get-PnpDevice 里 Generic Monitor (VDD by MTT) 有 CM_PROB_NONE 的实例；dxgi-info 只有物理屏输出。此时不要反复重装驱动。 | `streaming.virtual-display`, `hardware.device-matrix` | active |
| medium | [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md) | 重装 v0.6.0 时 Install.ps1 报 ViGEmBus 服务处于 StopPending，安装器退出 0 但服务起不来，提示"请重启 Windows 后重新运行"。 | Get-Service ViGEmBus 显示 StopPending，或 sc query 返回 1061/1072；同时 HKLM\SYSTEM\CurrentControlSet\Services\ViGEmBus 已不存在。 | `streaming.4070s-deploy-20261125`, `streaming.version-matrix` | active |

## 已解决（0）

（无）

## 按适用范围

### `hardware.device-matrix`

- [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md)（high）
- [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md)（high）

### `streaming.4070s-deploy-20261125`

- [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md)（medium）

### `streaming.config-inventory`

- [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md)（high）
- [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md)（high）

### `streaming.deploy-checklist`

- [用 API 改一个键，会把其余键一起清空](../配置写入覆盖.md)（high）

### `streaming.on-demand-vdd-choice`

- [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md)（high）

### `streaming.version-matrix`

- [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md)（high）
- [ViGEmBus 卸载残留不必重启：先删设备节点再停服务就能当天重装](../ViGEmBus卸载残留不必重启.md)（medium）

### `streaming.virtual-display`

- [用 ensure_only_display 会让断开串流时卡死两分钟](../显示拓扑卡死.md)（high）
- [虚拟屏没被调用有两个坑：prep 时序，和绑了 DISPLAY 编号](../prep命令改不了捕获屏.md)（high）
- [单屏机器装完 VDD，DXGI 里没有虚拟屏](../单屏装虚拟屏不枚举.md)（high）
- [改了 vdd_settings.xml 却不生效，虚拟屏永远停在 800x600](../虚拟屏配置不生效.md)（high）
- [重装 VDD 后设备一切正常，Windows 却不把虚拟屏接回桌面](../虚拟屏重装后不接入.md)（high）
