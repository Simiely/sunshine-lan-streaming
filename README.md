# sunshine-lan-streaming

Sunshine + Moonlight 局域网串流的选型、部署与排障笔记，以及由此产出的可分发安装包。

面向的场景很窄：**一台 Windows 主机、只在内网用、客户端是 Moonlight、希望长期不用管**。广域网串流、云主机、Docker 方案不在范围内。

最终形态是一个 zip：下载、解压、跑一个脚本，宿主就绪；客户端只剩输一次配对码。版本、哈希与许可证锁在 [manifest/components.json](manifest/components.json)，不靠文档里的口头约定。

## 三条结论

1. **不需要虚拟显示器就别换分支**。官方 2026.516 组件最少，是长期停留的最优解。见 [版本矩阵](docs/版本矩阵.md)。
2. **需要虚拟显示屏时，切换权要放在 Sunshine 外面**。它内置的 `ensure_only_display` 会在回滚失败后阻塞重试，卡死约两分钟。见 [显示拓扑卡死](docs/显示拓扑卡死.md)。
3. **"不需要维护"的正确实现是能回滚**，不是不出问题。上线前存好配置、显示配置与版本清单。见 [部署清单](docs/部署清单.md)。

## 文档

- [docs/index.md](docs/index.md) — 全部页面的导航入口
- [docs/配置清单.md](docs/配置清单.md) — 10 组 36 项配置基线，装完照着对
- [docs/reports/](docs/reports/) — 每次实测的归档记录
- [AGENTS.md](AGENTS.md) — AI / 维护者入口：约定、命令、当前规模（生成物）
- [DEVELOPMENT.md](DEVELOPMENT.md) — 仓库结构与关键问题
- [CHANGELOG.md](CHANGELOG.md) — 版本历史

## 快速开始

```bash
python -m pip install -r requirements.txt
python tools/repo-kit/check_repo.py --root .
python tools/repo-kit/generate.py --root . --check
powershell -File tools/update-repo-kit.ps1 -Check
```

四项全绿才算仓库健康：`REPO CHECK` / `GENERATE CHECK` / `KIT LOCK` / CI。

没有 `pwsh` 7 时用 `powershell -File` 代替上面前置命令；CI 里是 Linux + `pwsh`，别把本地写法抄进工作流。

## 边界

- 本仓库记录**可复现的步骤与有依据的判断**；一次性实测归档在 `docs/reports/`，结论提炼进主题页，不把流水账写进标准页。
- 版本号与 issue 编号都标了取数日期（2026-11-24），过期的判断请连同 `last_reviewed` 一起更新。
- 机器层只保结构、链接、真源与新鲜度；内容对不对靠人审。
- **没有一份通过的真机报告，不发布 zip**——"解压即用"只能靠真机兑现。
