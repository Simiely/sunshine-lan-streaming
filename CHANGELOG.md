# CHANGELOG

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
