# CHANGELOG

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
