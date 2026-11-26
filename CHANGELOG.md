# CHANGELOG

## v0.8.1 — 2026-11-26

### 变更

- 包根只保留 3 个一键入口：`一键部署.cmd`、`一键部署-免登录面板.cmd`、`一键卸载.cmd`。
- 分步安装、恢复显示/基线、面板开关共 7 个 cmd 移入 `手动工具\`，根目录不再堆满脚本。
- `手动工具` 内的命令自动定位包根 `scripts\`；面板开关命令同时兼容包内和 ProgramData 两种布局。
- 使用说明、结果弹窗和脚本内的提权提示同步更新路径。

## v0.8.0 — 2026-11-26

### 变更

- 移除图形控制台（PySide6 / PyInstaller）及其构建脚本，默认交付恢复为纯脚本方案：`一键部署-免登录面板.cmd` / `一键部署.cmd` / `一键卸载.cmd`。
- 默认 zip 不再包含 `Sunshine控制台.exe` 与 `_internal` 运行库；解压后直接双击脚本，减少 UAC 启动、运行库体积和界面/脚本双维护。
- 面板逻辑不变：面板版部署仍安装到 ProgramData，并创建公共桌面「Sunshine 控制台」快捷方式。

## v0.7.7 — 2026-11-26

### 变更

- 恢复面板版部署创建公共桌面「Sunshine 控制台」快捷方式，与之前脚本行为一致；图形控制台的「启动免登录面板」按钮保留为第二入口。
- 这样面板版部署的效果与旧脚本完全相同：双击快捷方式即启动本地代理并免登录打开 Web UI。

## v0.7.6 — 2026-11-26

### 变更

- 免登录面板部署不再创建公共桌面快捷方式。面板仍复制到 ProgramData，从图形控制台「启动免登录面板」或 `panel\打开Sunshine面板.cmd` 打开；减少桌面污染和一个 COM 快捷方式失败点。
- 卸载仍会清理旧版本创建的「Sunshine 控制台」快捷方式。

## v0.7.5 — 2026-11-26

### 变更

- 图形控制台的「同时部署免登录面板」改为**默认勾选**，并从普通复选框改成整行高亮的选项卡（蓝色边框、加粗文字、下方说明），避免被忽略。
- `Build-Gui.ps1` 输出目录改为 `dist\gui-<版本>\`，避免上一版 GUI 正在运行时锁住 exe、导致重建失败。

## v0.7.4 — 2026-11-26

### 新增

- 图形控制台「一键部署」增加「同时部署免登录面板」勾选项：勾选后调用 `一键部署-免登录面板.cmd`，把面板安装到 ProgramData 并创建桌面快捷方式；不勾选保持标准部署。

### 优化

- 图形控制台由 PyInstaller `--onefile` 改为 `--onedir`：不再每次启动把约 46 MB 依赖解压到 Temp。实测 `--smoke-test` 启动从约 5.1 秒降到约 1.0 秒（含 0.3 秒自动退出）；真实启动主要剩 UAC 确认时间。
- 打包时排除未使用的 PyQt5 / PyQt6 / matplotlib / numpy / pandas / tkinter，减少无关依赖。

### 构建

- `Build-Gui.ps1` 输出 `dist\gui-onedir\Sunshine控制台\`；`Build-Package.ps1` 把 exe 和 `_internal\` 铺到离线包根目录，exe 仍可根级双击。

## v0.7.3 — 2026-11-26

### 新增

- **图形控制台**：`Sunshine控制台.exe`（PySide6）。暗色界面，入口自提升管理员权限；提供「一键部署」「启动免登录面板」「一键卸载」，以及「恢复显示（修复黑屏）」「恢复基线」「停止面板」「清空日志」。用户名/密码留空时沿用 admin / 随机密码。
- 日志区用 `QProcess` 异步捕获 stdout/stderr，GBK/UTF-8 自适应增量解码，中文实时滚动；所有外部脚本都不阻塞 UI。
- `OneClick.ps1` / `Uninstall.ps1` 支持 `SUNSHINE_GUI=1`：`Show-Result.ps1` 切到 `-PrintOnly`，只打印结果文本，不再弹内部窗口；成功/失败由图形界面统一提示。

### 构建

- 新增 `tools/gui/sunshine_gui.py`（源码）与 `tools/build/Build-Gui.ps1`（PyInstaller onefile 构建 + 冒烟测试）。
- `Build-Package.ps1` 把 `dist\gui\Sunshine控制台.exe` 放入离线包根目录，并在解压自检中校验。GUI exe 属于构建产物，不入 git。

## v0.7.2 — 2026-11-26

### 优化

- **安装过程中的长时间黑屏**：`devcon install` 创建虚拟屏设备后，Windows 会异步套用显示数据库里上一次保存的“仅 VDD”拓扑，物理屏全部掉出活动拓扑；原脚本要等到末尾 `Hide-Vdd.ps1` 才恢复，中间还要经过 device_id 复算、DXGI 等待与服务重启，黑屏可持续数十秒。
- `Install-Vdd.ps1` 新增 `Restore-PhysicalLayout`：安装前记录已接入桌面的物理屏；设备创建后立即检测并执行 `DisplaySwitch /extend`（最多 4 次，每次间隔 700ms），并在 PnP 复算、DXGI 等待、写基线前、隐藏虚拟屏前逐点复查。物理屏恢复不再依赖末尾的 `Hide-Vdd.ps1`。
- `Hide-Vdd.ps1` 中 3 × 4 秒的物理屏兜底保留；安装阶段物理屏已提前恢复，正常流程不会再触发这段等待。

### 验证

- 4070S 实机重装虚拟屏：设备创建后物理屏掉线（DXGI 只剩虚拟屏），约 0.7 秒后脚本检测并执行 `extend`，再约 0.5 秒两块物理屏恢复，**黑屏约 1.2 秒**；安装 20 秒内结束，结束状态物理屏 `2/2`、位置仍为 `0,0` / `-2560,0`，`Hide-Vdd` 返回 `action=hidden`，`output_name` 仍为 VDD 的 GUID。

## v0.7.1 — 2026-11-26

### 修正

- **一键入口 cmd 解析报错**：`一键部署-免登录面板.cmd`、`打开Sunshine面板.cmd`、`停止Sunshine面板.cmd` 原先使用 LF 换行并含中文注释，cmd.exe 在部分环境会把行拆断，启动时出现 `'al'`、`'Sunshine'`、`'ame'` 不是内部或外部命令。三个文件已改为纯 ASCII + CRLF，功能不变。

## v0.7.0 — 2026-11-26

### 新增

- **按需免登录面板**：`Open-WebUI.ps1` 在 `127.0.0.1:47991` 起一个回环转发器，自动注入 Basic 凭据并重写 `Origin/Referer` 通过 CSRF，浏览器打开即进入 Web UI；空闲 10 分钟自动退出，不注册服务、不开机自启、不写防火墙。
- **两个一键入口**：`一键部署.cmd` 保持标准部署；`一键部署-免登录面板.cmd` 额外把面板脚本复制到 `C:\ProgramData\sunshine-lan-streaming\panel`，并在公共桌面创建「Sunshine 控制台」快捷方式。结果弹窗会显示面板状态。
- **卸载清理**：结束代理进程、删除 `%LOCALAPPDATA%\SunshinePanel`、公共桌面快捷方式与面板目录。

### 验证

- 模拟服务实测：GET/POST 均自动注入认证，`Origin` 被重写为 Sunshine 允许的来源，POST 不再触发 CSRF 拒绝。
- 代理工作集约 75MB，空闲 CPU 接近 0；不经过 Moonlight 的 47984/47989 与 UDP 音视频端口。

## v0.6.11 — 2026-11-26

### 优化

- **卸载清理非present虚拟屏记录**：历次重装会在设备管理器留下没有硬件、也没有驱动包的监视器条目。新增公共函数 `Remove-VddPhantomMonitors`（`pnputil /remove-device`），一键卸载和 `Install-Vdd.ps1 -Uninstall` 都会调用；4070S 实测 9 → 0，个别失败会提示重启后重试。

## v0.6.10 — 2026-11-26

### 优化

- **device_id 直接复算，不再依赖 DISPLAYn 识别**：按 libdisplaydevice `getDeviceId` 的源码算法（EDID + 实例 ID 稳定片段 + 结尾 NUL → UUIDv5/SHA1 空命名空间）在安装时就地算出虚拟屏 GUID。已用 Sunshine verbose 日志的 324 字节转储逐字节交叉验证，4070S 复算结果与日志中的 `{5eb52002-…}` 完全一致。
- 命中复算时跳过 DXGI 激活等待、编号识别和日志解析：4070S 实测 **18 秒**完成（原先最长 60 秒以上）；复算失败仍自动回退到原流程。
- **修正状态快照**：旧快照缺少 `physical_output` 字段时，不再拿当前 `output_name`（可能已是虚拟屏 GUID）顶上，改为取安装前真实存在的物理输出，保证卸载能还原到物理屏。

## v0.6.9 — 2026-11-26

### 修正

- **重装 VDD 后无法识别虚拟屏**：设备与监视器对象都 OK，但 Windows 按显示数据库把它保持为“不接入”，DXGI 只有物理屏，`Install-Vdd` 以退出码 4 中止。等待循环现在按顺序尝试 CCD 接回（`Hide-Vdd.ps1 -Show`，第 3 秒）→ `DisplaySwitch /extend`（第 8 秒）→ 再试一次 CCD（第 14 秒）。
- 删除“设备存在且 DXGI 有输出就视为就绪”的快捷判断：虚拟屏未接入时物理屏也有输出，该条件会提前放行，导致识别必然失败（4070S 实测）。
- 新增踩坑页 [重装 VDD 后不接入](docs/虚拟屏重装后不接入.md)，与单屏笔记本缺 extend 的案例区分。

## v0.6.8 — 2026-11-26

### 修正

- **ViGEmBus 被误判“已安装”**：手工卸载会残留卸载表登记（ViGEm Bus Driver），安装器据此返回 0 却不创建服务。`Install.ps1` 在服务缺失时先静默 `msiexec /x` 清掉旧登记再安装，等待上限 60 → 90 秒。实机验证：清登记后 1 秒内服务 Running。
- **一键步骤值被日志污染**：`OneClick.ps1` 的 `Invoke-Step` 把子脚本输出留在了管道里，`$steps.install` 实际是字符串数组而非退出码，导致步骤显示为空、成功也被判失败并跳过虚拟屏/卡片。改为 `2>&1 | Out-Host`，函数只返回 Int32；已用退出码 7 的测试子脚本验证。
- 宿主有失败项但服务与配置已就绪时（例如仅 ViGEmBus 失败），一键部署继续执行虚拟屏与卡片，不再整体跳过。

## v0.6.7 — 2026-11-26

### 新增

- **一键部署可自定义 Web UI 凭据**：`OneClick.ps1` 新增 `-Username` / `-Password`，运行时交互询问。用户名直接回车用 `admin`，密码直接回车保持随机 16 位。
- 凭据以参数数组传给 `Install.ps1`，不经过 cmd 拼接，含空格或特殊字符也不会被解析；结果弹窗与 `credentials.txt` 照常显示最终值。
- 使用说明补充交互提示。分步 `安装.cmd` 仍是随机密码，需要自定义时用一键入口或直接给 `Install.ps1 -Password`。

## v0.6.6 — 2026-11-26

### 修正

- **一键部署成功却被判“未完成”**：与 v0.6.5 卸载同源，结果弹窗直接关闭时 `Show-Result.ps1` 返回 3，`一键部署.cmd` 把它当成失败并暂停。`OneClick.ps1` 改为只按三步退出码决定结果：全部为 0 即返回 0（保存或关闭弹窗都算完成），有失败项才返回 1 并保留控制台。
- 至此一键部署与一键卸载的退出码语义一致：业务结果决定退出码，弹窗操作不影响判定。

## v0.6.5 — 2026-11-26

### 修正

- **卸载成功却被判“未完成”**：结果弹窗直接关闭时 `Show-Result.ps1` 返回 3（保存 TXT 才返回 0），`一键卸载.cmd` 把它当成失败并暂停。卸载路径改为只按失败项决定退出码：0 项失败即返回 0，保存或关闭都算完成；有失败项才返回 1 并保留控制台。
- 4070S 实机卸载已跑通：虚拟屏移除、Sunshine MSI 卸载、快捷方式/防火墙/状态目录清理，0 失败 0 警告。

## v0.6.4 — 2026-11-26

### 修正

- **一键卸载第一步即中止**：`Uninstall.ps1` 调用了 `Get-VddAdapter`，但该函数只定义在 `Install-Vdd.ps1` 内，未点源时直接 `CommandNotFoundException`。改为 CIM 查询（`friendly_name` 匹配 `VDD by MTT` 或 HardwareID 含 `MttVDD`）加 `C:\VirtualDisplayDriver` 目录双重判断，不再依赖子脚本内部函数。
- 卸载检测已验证能识别隐藏状态的虚拟屏（`ROOT\DISPLAY\0001`，Status OK）。

## v0.6.3 — 2026-11-26

### 新增

- **一键卸载**：包根新增 `一键卸载.cmd` 与 `scripts\Uninstall.ps1`。顺序固定为：虚拟屏（`Install-Vdd.ps1 -Uninstall`，恢复物理屏）→ Sunshine（停服务、按清单产品码 `msiexec /x`、清目录）→ ViGEmBus（设备节点→停服务→删服务→删驱动包，避免 StopPending）→ 防火墙/快捷方式/自启动/状态目录。
- 卸载支持 `-KeepViGEmBus`（其他手柄工具在用）与 `-KeepState`（保留记录）；只删本方案写入的内容，不动个人文件与 Oray/RayLink。
- `manifest.components.sunshine` 补 `product_code`，卸载使用版本锁定的 MSI 产品码；`Show-Result.ps1` 支持 `mode=uninstall` 与 `-ResultFile`，卸载结果同样深色弹窗、可保存 TXT。
- 出包自检清单、使用说明、出包流程补卸载入口。

## v0.6.2 — 2026-11-26

### 新增

- **一键部署入口**：包根新增 `一键部署.cmd` 与 `scripts\OneClick.ps1`，按“安装宿主 → 启用虚拟屏 → 分辨率卡片”顺序调用现有分步脚本；宿主失败时跳过后续，虚拟屏/卡片失败不影响其它步骤完成。
- 各步退出码合并进 `install-result.json` 的 `steps` 字段，结果弹窗统一展示，并在标题区分“一键部署 / 分步部署”；保存 TXT 后仍会自动关闭全部窗口。
- 分步入口（安装、安装虚拟屏、安装分辨率卡片）保持不变。
- 出包自检清单与使用说明补一键部署入口。

## v0.6.1 — 2026-11-26

### 修正

- **断开后物理屏不自动恢复**：虚拟屏基线缺少 `dd_config_revert_on_disconnect = enabled`，而 Sunshine 缺省是 `disabled`，客户端断开只在“应用关闭 / 最后会话终止”时回滚。2026-11-26 09:04 日志实测只有 `CLIENT DISCONNECTED`、没有 `Trying to revert applied display device settings`，桌面停在虚拟屏仍在拓扑的状态。`_Baseline.ps1` 的 vdd 配置档已固定写入该键；配置清单新增 E-06，[虚拟屏待机隐藏](docs/虚拟屏待机隐藏.md) 补充“必须显式打开”一节。
- **ViGEmBus 残留提示**：`Install.ps1` 的 StopPending 提示不再直接要求重启，改为按 [ViGEmBus 卸载残留不必重启](docs/ViGEmBus卸载残留不必重启.md) 的顺序清理后重跑。
- 4070S 报告追加 2026-11-26 补充说明，明确断开回滚缺口，并修正“ViGEmBus 只能重启”的表述。

### 说明

- 合并 2026-11-26 远端文档：ViGEmBus 清理顺序实测与 redmibookpro15x 全新安装报告；本轮代码改动使随包 zip 变为 v0.6.1。

## 文档更新 — 2026-11-26（v0.6.0 包内容未变）

### 新增

- **全新安装验证报告**：[2026-11-26 redmibookpro15x 全新安装验证](docs/reports/2026-11-26-redmibookpro15x-全新安装验证.md)——干净机上宿主 / 虚拟屏 / 卡片三步全绿，独立复核服务、端口、Web UI 认证、VDD 与配置全部到位；补齐 4070S 报告遗留的 ViGEmBus 干净机器复测项。
- **踩坑页**：[ViGEmBus 卸载残留不必重启](docs/ViGEmBus卸载残留不必重启.md)——纠正"只能重启"的结论，给出可当天重装的清理顺序，并记录中文 PnP 输出让英文正则漏判的坑。

### 说明

- 本轮只更新文档与索引，未改任何脚本或随包资产，zip 仍为 v0.6.0；真机串流与局域网广播域验证仍未闭环，报告保持 `status: active`，不作为发布依据。
- 与 [4070S 部署验证](docs/reports/2026-11-25-4070s-部署验证.md) 的关系标为 `contradicts`：后者"必须重启"的表述被本次实测限定为"那个残局下才需要重启"。

## v0.6.0 — 2026-11-25

### 新增

- **ViGEmBus 自适应安装**：`Install.ps1` 在定位安装目录后检查 `ViGEmBus` 服务；缺失时运行 Sunshine MSI 自带的 `scripts\vigembus_installer.exe /exenoui /qn /norestart`（实测退出码 0、服务 Running），最多等 60 秒，失败记入结果并提示重启。检测同时看服务与注册表，兼容删除挂起状态。
- **深色结果弹窗**：新增 `scripts\Show-Result.ps1`。安装结束显示 Web UI 地址（本地 + 默认路由网卡）、账号密码、服务/端口、ViGEmBus 状态与警告；「保存为 TXT…」成功后连同控制台窗口一起自动退出。
- **待机隐藏虚拟屏**：新增 `scripts\Hide-Vdd.ps1`，走 CCD 只停用虚拟屏的 path，物理屏布局不动；`Install-Vdd.ps1` 装完自动调用。物理屏数量为 0 时先 `DisplaySwitch /extend` 恢复再隐藏，并校验数据库当前条目与"仅 VDD"快路径。
- **4070s 设备档案**：新增 `payload/conf/devices/4070s.json`；`manifest/components.json` 的 `device_profiles.known` 补 `4070s`，`deferred.vigembus` 已实现，安装方式改记到 `notes.vigembus`。
- 文档：新增 [虚拟屏待机隐藏](docs/虚拟屏待机隐藏.md) 与 [4070s 部署验证](docs/reports/2026-11-25-4070s-部署验证.md)；设备矩阵补 `4070s` 行；虚拟显示器方案改指向 CCD 隐藏。

### 修正

- `Get-Baseline.ps1` A-04 改为"服务优先、卸载表兜底"：ViGEmBus 1.21 实测没有卸载登记项，只认卸载表会误判"未安装"。

### 说明

- `安装.cmd` 在安装结束后调用结果弹窗；未保存结果时保留控制台便于看日志，保存成功才整体关闭。
- 结果 JSON 增加 `password`、`web_ui_local`、`web_ui_lan`、`vigem_service`、`vigem_installed_now`；凭据仍同时写入设备状态目录的 `credentials.txt`。

## v0.5.8 — 2026-11-25

### 修正（严格审核发现）

- **体检判据**：`Get-Baseline.ps1` 的 E-03 原先把 `ensure_only_display` 判为偏离，与现行虚拟屏方案冲突。现按方案区分——`disabled`（物理屏）与 `ensure_only_display`（虚拟屏）都合格，只有 `ensure_active` / `ensure_primary` / `verify_only` 才算偏离。E-02 新增 GUID / `\\.\DISPLAYn` 识别：编号绑定标 ⚠️ 并提示"重启后可能静默回退物理屏"。
- **配置清单** E-02 / E-03 的期望值与说明同步改判；补记"`disabled` 不等于完全不碰显示，它会触发后台回滚"。
- **虚拟显示器方案** 页重写切屏分工：从"外部脚本在连接前切"改为"Sunshine 自己 `ensure_only_display`"，并交代 prep 方案被否决的原因；失效场景表补 `device_id` 的容错说明。
- **设备矩阵**：锚点分辨率与 `DISPLAYn` 启发式两条从"待确认"改为本机实测结论。
- **使用说明**与 `Install-Cards.ps1` 的提示语清理旧卡名（「桌面 · xxx」→ 分辨率卡）。

### 说明

- 体检从 13 合格 / 7 偏离 / 16 待测 → **17 合格 / 6 偏离 / 13 待测**，主要来自 E-02/E-03 判据纠正与连接成功的日志证据。
- 剩余偏离仍是环境项（第三方 IDD、网卡、RayLink、电源策略），文档明确不自动处置。

## v0.5.7 — 2026-11-25

### 变更

- 卡片按 **iOS → 安卓 → Switch → 电视 → 通用** 排序；OPPO 档位改为实测可用的 `2354x1080@120`（原写屏幕原生 `2772x1272`，实际不生效）；移除 `通用 1280x720@60` 与 `通用 1440x900@60`。现共 6 张分辨率卡（含桌面总 8 张）。
- `vdd-resolutions.txt` 同步：`Find X9 Pro|2354x1080|120`，删除 `1280x720`、`1440x900`；虚拟屏模式表实测已生效（`vdd_settings.xml` 7 个模式）。
- 封面改为**固定版式纯大字**：设备名上移并与分辨率拉开间距、分辨率 96px 最大、刷新率主色，移除屏幕轮廓方块。`Gen-Covers.py` 的 `CARDS` 同时是顺序与内容的唯一真源。
- `Install-Cards.ps1` 改为"先移除自己生成过的卡、再按列表重建"：删卡、改名、调顺序一次生效，且不碰 `Desktop` / `Steam Big Picture`；同时清理安装目录里已废弃的旧封面。
- `Install-Vdd.ps1`：`output_name` 已绑定 `device_id` 时跳过 `DISPLAYn` 识别，不再因此 `exit 4`（本次实测退出码 0）。

### 说明

- 用户实测确认虚拟屏可正确加载（`ensure_only_display` + GUID 生效）。真机串流分辨率仍待逐档验证。

## v0.5.6 — 2026-11-25

### 新增

- 分辨率卡片封面：`tools/build/Gen-Covers.py` 生成 8 张 600×800 PNG（`payload/covers/`），按各自宽高比画屏幕轮廓 + 大号分辨率 + 刷新率徽章，16:9 / 4:3 / 手机宽屏一眼可辨。
- `Install-Cards.ps1` 部署封面到 `Sunshine\assets\covers\`，`image-path` 写相对路径 `covers/res-<宽>x<高>.png`（Sunshine 按 `assets\` 解析，跨机器有效）；已有卡只补封面、不动其他字段。
- `Build-Package.ps1` 自检新增 `covers\res-1920x1080.png`（17 项）。

### 说明

- 本机已应用：10 张卡各自指向对应封面，服务重启无 `Couldn't find app image` 警告。真机串流仍未验证。
- 封面是程序绘制而非 AI 配图——分辨率数字必须准确，且要统一风格、可一键重生成。

## v0.5.5 — 2026-11-25

### 修正（重要）

- **否决 prep-cmd 切屏方案**：`global_prep_cmd` 在 `configure_display` 与 `probe_encoders` 之后才执行，且 `dd_configuration_option = disabled` 会触发 `revert_configuration()` 后台回滚，两者叠加导致 launch 卡在编码器探测、客户端连接失败。证据与源码依据见新踩坑页 `docs/prep命令改不了捕获屏.md`。
- vdd profile 改回 Sunshine 原生 `ensure_only_display` + `output_name` 指向虚拟屏；虚拟屏设备常驻启用（probe 必须能枚举），桌面拓扑平时只留物理屏。`Restore-Baseline -Profile vdd` 会主动清理历史遗留的 `global_prep_cmd`。
- **`output_name` 改用 `device_id`（GUID）而非 `\\.\DISPLAYn`**：编号在设备重新启用后会变（实测出现 52/53/54），Sunshine 找不到就静默回退物理屏，表现为"连接成功但分辨率怎么选都不变"。`Install-Vdd.ps1` 装完驱动会重启服务并从启动日志解析 VDD 的 GUID，取不到才退回编号并告警。
- 新增架构图 `docs/assets/vdd-call-chain.svg`，嵌在踩坑页里说明平时状态、连接时序与两种绑定方式的差异。
- 移除已否决方案的入口：`安装按需虚拟屏.cmd`、`Install-OnDemand.ps1`、`Switch-Vdd.ps1`。`docs/按需虚拟屏选型.md` 与实测报告同步改判。

### 变更

- 分辨率卡片改名：从「桌面 · 1080p」改为「设备名 + 分辨率@刷新率」，如 `Find X9 Pro 2772x1272@60`、`电视 4K 3840x2160@60`、`通用 2560x1440@60`。`Install-Cards.ps1` 会清理旧命名卡，卡片数 10（含原有 2 张）。
- `Build-Package.ps1` 关键文件清单同步移除三个入口（17 项）；使用说明改回单一虚拟屏路线。

### 说明

- 本机当前状态：虚拟屏 `ROOT\DISPLAY\0001` 常驻启用，`DISPLAY54` 为 `output_name`，桌面只显示物理屏 `DISPLAY1`。`ensure_only_display` 的连接—断开循环仍**未验证**（无客户端配对，2026.516 无 launch API）。zip 不发布。

## v0.5.4 — 2026-11-24

### 新增

- 分辨率卡片：`payload/scripts/Install-Cards.ps1` + `安装分辨率卡片.cmd`，在 `apps.json` 新增 6 张名字带分辨率的 Desktop 卡（720p / 1080p / 2K / 4K / 手机 / 平板）。Moonlight 按卡独立保存分辨率，点卡即用对应档位。脚本幂等，不覆盖已有同名卡。新页 `docs/安装Moonlight卡片.md`。
- 本机实测：卡片数从 2 变 8，服务与常驻端口正常，显示仍在物理屏（平时状态）。

### 说明

- 卡片本身不写 prep 命令：v2026.516 的 `mode` 参数来自客户端，app prep 在 `configure_display` 与 `probe_encoders` 之后才跑，改不了显示模式。分辨率仍靠 `dd_resolution_option = auto` 切换，静态表是候选集。
- 卡片分辨率存在 Moonlight 客户端侧，换设备要重设一遍；每个设备都要开「优化游戏设置」。真机验证未完成。

## v0.5.3 — 2026-11-24

### 新增

- `docs/Moonlight卡片分辨率.md`：澄清"分辨率配置"指 Moonlight 每张应用卡片自带的分辨率选项。Sunshine 源码实证（`nvhttp.cpp` 的 `launch()` → `display_device.cpp` 的 `parse_resolution_option()`）表明：客户端请求的分辨率由 `dd_resolution_option = auto` 切到虚拟屏，且发生在 app 的 prep 命令之前、编码器探测之前——所以不能靠 app prep 切分辨率。

### 变更

- vdd profile 的 `dd_resolution_option` / `dd_refresh_rate_option` 从 `disabled` 恢复为 `auto`；`dd_configuration_option` 仍为 `disabled`（拓扑交给 prep 脚本）。静态表 `vdd-resolutions.txt` 是 auto 的候选集，两者缺一不可。
- 本机 `sunshine.conf` 同步更新，`locale = zh` 与 `global_prep_cmd` 保留。

### 说明

- 客户端必须开「优化游戏设置」，否则源码明确警告"Resolution will not be changed"。表外档位会静默失败，画面停在原档——新客户端接入时先补表。仍未配对真机验证。

## v0.5.2 — 2026-11-24

### 新增

- 按需虚拟屏：`payload/scripts/Switch-Vdd.ps1` + `Install-OnDemand.ps1` + `安装按需虚拟屏.cmd`。平时禁用虚拟屏设备、物理屏工作；Moonlight 连接时由 `global_prep_cmd` 的 `do` 启用虚拟屏并 `DisplaySwitch /external` 只留虚拟屏，断开时 `undo` 恢复物理屏并重新禁用虚拟屏。切屏权留在 Sunshine 之外，避开 `ensure_only_display` 的回滚阻塞。
- `Get-BaselineProfile -Name vdd -SwitchScript` 生成 `global_prep_cmd`（JSON **数组**，`elevated=true`）并清空 `output_name`，让 Sunshine 捕获 `do` 切好后的主屏。
- 决策页 `docs/按需虚拟屏选型.md`：对比 MTT VDD + 外部脚本与 vdisplay/SudoVDA，结论是先用已验证的驱动、不换栈；报告 `docs/reports/2026-11-24-redmibookpro15x-按需虚拟屏.md` 记录实测。
- `vdd-resolutions.txt` 补 720p 与 1440x900 / 1920x1200（16:10 常用档）。

### 变更

- `dd_configuration_option` 在 vdd profile 改回 `disabled`，`dd_resolution_option` / `dd_refresh_rate_option` 同步改为 `disabled`（静态表方案，不让 Sunshine 动态改模式）。
- `Build-Package.ps1` 解压自检新增两个脚本与 `安装按需虚拟屏.cmd`（16 项）；使用说明改为 A/B 两种虚拟屏模式。
- 新脚本统一带 UTF-8 BOM——PS 5.1 读无 BOM 的中文注释会按 GBK 解析并报 `unexpected token`。

### 说明

- 本机实测：connect（提权）设备启用 → `DISPLAY52` 出现 → 只剩虚拟屏，退出码 0；disconnect（提权）恢复物理屏并禁用设备，退出码 0；非提权 connect 快速失败、物理屏保持。**未验证 Sunshine 会话触发**——2026.516 Web API 无 launch 端点，本机也无 Moonlight 配对，无法模拟连接。zip 仍不发布。

## v0.5.1 — 2026-11-24

### 新增

- 「装完即用」：`Get-BaselineProfile` 两套 profile 都写入 `locale = zh`，Web UI 打开即中文；`Install.ps1` 改为写共享 profile 的完整键集（7 项），不再本地复制三键清单。第二台设备实测确认中文与完整配置落盘、无 BOM。
- 单屏虚拟屏自动接入：`Install-Vdd.ps1` 在轮询 3 轮仍无新输出时自动执行一次 `DisplaySwitch.exe /extend`（可逆、不改配置），解决 AMD 780M 单屏笔记本上「设备节点 OK 但 DXGI 不枚举」的问题。新踩坑页 `docs/单屏装虚拟屏不枚举.md` + 报告 `docs/reports/2026-11-24-redmibookpro15x-虚拟屏安装.md`。

### 变更

- `Install-Vdd.ps1` 与 `Restore-Baseline.ps1` 写入 `output_name` 前剥掉首尾单/双引号——经 cmd / `Start-Process -ArgumentList` 传参时引号会变成字面量，导致 Sunshine 认不出输出屏。
- `Build-Package.ps1` 的使用说明改为写明「装完即中文、配置写全、单屏自动 extend」。

### 说明

- 第二台设备已装好虚拟屏（`ROOT\DISPLAY\0001` OK，`\\.\DISPLAY36` 已接入桌面），配置切到 vdd 基线并保留 `locale = zh`。体检 13 合格 / 7 偏离 / 16 待测——合格数下降是 A-03 新增虚拟适配器与 E-03 切到 `ensure_only_display` 所致，属预期。仍未配对客户端，串流与局域网拓扑未验证，zip 不发布。

## v0.5.0 — 2026-11-24

### 新增

- 设备维度：`payload/conf/devices/defaults.json` + `<device_id>.json` 覆盖层，把原先写死在第一台机器上的锚点分辨率、网卡正则、冲突服务、GPU 白名单、第三方 IDD 名单与虚拟屏识别策略外置。优先级为「命令行显式 > 设备专属 > defaults > 脚本兜底」。
- `Get-DeviceId` / `Get-DeviceFingerprint` / `Get-DeviceStateRoot`（`_Baseline.ps1`）：设备 ID 取小写 `COMPUTERNAME`；指纹记录 UUID / 机型 / CPU / OS build / GPU；`Get-Baseline.ps1 -Json` 输出带 `device_id` 与 `fingerprint`，并支持 `-OutFile` 落盘快照。
- 按设备隔离状态：`install-result.json` / `credentials.txt` / `display-state.json` / `install-vdd.log` 移到 `C:\ProgramData\sunshine-lan-streaming\devices\<device_id>\`，多机不再互相覆盖。
- 文档三件套：`docs/设备硬件标准.md`、`docs/设备矩阵.md` 与第二台设备实测 `docs/reports/2026-11-24-redmibookpro15x-本机基线.md`（AMD 780M / 3200×2000 / 7 合格 8 偏离 21 待测）。`schema/taxonomy.json` 新增 `hardware` topic。
- `manifest/components.json` 新增 `device_profiles` 顶层段；`package.version` → 0.5.0。

### 变更

- `Install-Vdd.ps1` 不再硬编码 VDD 的 SHA256 与 size，改为从 manifest 读取，恢复单一真源；删除「虚拟屏恒 800x600」的跨机无效断言。
- `_Baseline.ps1` 的 `Find-VddOutput` 默认关闭 `DISPLAYn >= 10` 启发式，仅当设备显式声明 `vdd_output_strategy = display-number` 才启用。
- `Build-Package.ps1` 的使用说明与解压自检不再硬编码 Moonlight 版本和许可证文件名，改为从 manifest 派生；自检新增 `conf\devices\defaults.json`。
- 四个 `.cmd` 提权时透传 `%*`，此前从非管理员启动会丢失 `-DryRun` / `-Profile` / `-Uninstall`。
- `docs/_template.md` 删除空 `defines:`（照抄会触发 `SCHEMA ERROR`）；`docs/配置清单.md` 明确状态列只记最近一次摘要，多机结论以设备报告为准。

### 说明

- 当前 zip 仍不发布：局域网拓扑尚未在任一台设备上验证；第二台设备仅完成装机前基线，未装 Sunshine。

## v0.4.0 — 2026-11-24

### 新增

- 虚拟显示器落地：`payload/scripts/Install-Vdd.ps1` + `payload/安装虚拟屏.cmd`，从随包 zip 本地安装 MTT VDD（零网络），安装后把 Sunshine 切到 `vdd` 基线——`ensure_only_display`（连上即禁用其余屏）+ `dd_configuration_option` 配套 + 断流自动回滚。
- 多设备分辨率预设 `payload/conf/vdd-resolutions.txt`：按设备名列出 `2772x1272`(Find X9 Pro) / `2868x1320`(iPhone 17 Pro Max) / `2732x2048@120`(iPad Pro M1) / `1920x1080`(Switch 底座) / `3840x2160`(电视 4K)，安装时并入 `vdd_settings.xml`，不在列表里的分辨率会被清理。
- 救援脚本 `payload/scripts/Restore-Display.ps1` + `payload/恢复显示.cmd`：虚拟屏异常时强制 `Enable-PnpDevice` 并 `DisplaySwitch /extend`，不改配置、可反复执行。
- 踩坑页 `docs/虚拟屏配置不生效.md`：BOM 导致 XmlLite 解析失败 → 虚拟屏恒为 800x600；含三个"看起来该有效、实际全无效"的假象与管道诊断手段。
- 构建链路 `tools/build/Fetch-Vendor.ps1` + `tools/build/Build-Package.ps1`：按 manifest 拉取并校验随包资产（Sunshine msi / Moonlight 便携版 / VDD 驱动 / 许可证全文），组装成自包含离线 zip。带断点续传与多轮重试，应对 GitHub CDN 的间歇 502。
- 文档 `docs/出包流程.md`：两条命令出包、产物验证判据、断流与 `NativeCommandError` 的坑。

### 变更

- `_Baseline.ps1` 抽出共享层：两套 profile、合并写回、服务重启、`dxgi-info` 解析、虚拟屏识别、分辨率同步。
- 虚拟屏识别改为五级判定（显式指定 → 已记录 → 品牌黑名单过滤后的严格匹配 → 差集 → Moonlight 档位兜底），遇到歧义一律中止，不写 `sunshine.conf`。刻意排除 `raylink` / `oray` 等第三方 IDD，本机三者并存。
- 设备存在性判定从 `Get-PnpDevice` 改为直接读注册表 `Enum\ROOT\DISPLAY\*` 的 `HardwareID`——实测 `Get-PnpDevice` 在提权会话里会静默返回空集，导致误判"未安装"而重复装驱动，多生成一块虚拟屏。
- `manifest/components.json`：新增 `vdd` 组件（25.7.23 / SHA256 / 71,225,903 字节 / MIT），`package.version` → 0.4.0。

### 说明

- 本版首次产出完整离线包 `dist/sunshine-lan-streaming-0.4.0.zip`（125.47 MB，SHA256 `d5495429…`），自包含 Sunshine msi、Moonlight 便携版、VDD 驱动包与 GPL-3.0/MIT 许可证全文。已实测：解压后 `Install.ps1 -DryRun` 能在包内找到 msi 与 manifest，13 项关键文件齐全，中文文件名正常。
- 仍不对外发布：真机串流成立，但局域网拓扑（业务网段 `10.4.240.0/23`）尚未验证，按 `DEVELOPMENT.md` 的规则 zip 不可发布。
- 虚拟屏配置生效依赖两点已固化：写入必须无 BOM；配置变更后必须重建 PnP 设备节点才能让驱动重读（`disable/enable` 不够）。
- `payload/vendor/*.zip|msi|exe` 与 `dist/` 不入 git；`payload/licenses/*.txt` 入库，因为 GPL-3.0 再分发要求随附全文。

## v0.3.0 — 2026-11-24

### 新增

- 修复脚本 `payload/scripts/Restore-Baseline.ps1` 与 `payload/恢复基线.cmd`：对 `sunshine.conf` 做「读全量 → 覆盖基线键 → 合并写回」，自动备份、回读校验、重启服务并轮询三个常驻端口。非管理员时提前退出并给出提权指引，不留半截状态。
- 证据层 `docs/reports/2026-11-24-安卓真机验证.md`：手机真机首次串流记录。`moonlight-axixi` 构建 `261107` 配官方 Sunshine `2026.516`，HEVC / `2560x1440` / 60fps / Opus / 触屏 + 手柄全部正常。
- 踩坑页 `docs/配置写入覆盖.md`：`POST /api/config` 是整体替换，单键写入会静默抹掉其余键并把 `upnp` 改回 `enabled`。

### 变更

- `Get-Baseline.ps1`：`E-05` HAGS 改为「注册表缺失时按 Win11 缺省视为开启」并与日志交叉验证；`F-01`/`F-03`/`F-04` 改为从最后一次串流会话的日志自动提取，不再依赖 Web UI。合格数 12 → 15。
- `docs/配置清单.md`：更新 D/E/F/I 组状态与判据；补两条易错点——`Offset` 相对虚拟桌面而非绝对坐标、捕获面 `R16G16B16A16_FLOAT` 不等于传输色彩空间。
- `DEVELOPMENT.md`：把"通过"的判据收紧为「真机 + 同广播域 + 无遗留 `⚠️`」；说明 `reports/` 的 `active` / `archived` 用法。
- `manifest/components.json`：`package.version` 与 CHANGELOG 对齐。

### 说明

- 本版仍不含可安装产物。真机串流成立，但链路是宿主自带移动热点（`192.168.137.0/24`），与业务网段 `10.4.240.0/23` 不同，局域网拓扑尚未验证，按 `DEVELOPMENT.md` 的规则 zip 不可发布。

## v0.2.0 — 2026-11-24

### 新增

- 锁定层 `manifest/components.json`：锁定 Sunshine `2026.516.143833` 与 Moonlight `6.2.0` 的版本、官方 URL、SHA256 与许可证，作为唯一真源；构建脚本不得硬编码版本。
- 状态层 `docs/配置清单.md`：10 组 36 项配置基线，每项含期望值、取法、合格线、偏离处置与状态符号；只写"怎么取"，不写会漂移的当前值。
- 证据层 `docs/reports/2026-11-24-本机基线.md`：首次实测，4 项合格、7 项偏离、25 项待测；记录两处关键结论——本机非干净环境，单屏退路不成立。
- 目录骨架 `payload/`（进包内容）与 `tools/build/`（构建脚本）。

### 变更

- DEVELOPMENT.md 从"纯文档仓"改为"知识库 + 发行源"，补 `manifest/` `payload/` `tools/build/` `docs/reports/` 四层职责与"无报告不发布"的绑定规则。
- `docs/index.md` 新增「配置与记录」分组；`docs/部署清单.md` 第六步改为链接到配置清单 J 组，不再重复列举快照内容。

### 说明

- 本版不含可安装产物：`payload/` 与 `tools/build/` 仅有骨架，zip 在 M3 产出。
- 首版不引入 VDD 与 ViGEmBus，理由记在 `manifest/components.json` 的 `deferred` 字段。

## v0.1.0 — 2026-11-24

### 新增

- 从 knowledge-base 新项目模板（`knowledge` profile，repo-kit `2.9.1`）初始化。
- 建立四个主题页：分支选型、版本矩阵、虚拟显示器方案、部署清单，以及首个踩坑页「显示拓扑卡死」。
- README 改为场景化说明：一台 Windows 主机、仅内网、长期免维护。
- DEVELOPMENT.md 补项目概览、三层结构与两条关键问题。
