# DEVELOPMENT.md · sunshine-lan-streaming

## 项目概览

- 目标读者：我自己，以及下次接手这个串流环境的 AI。
- 解决什么问题：把"Sunshine + Moonlight 局域网串流"这件事里会踩的坑、版本取舍、部署动作固化成可复现的文档，**并最终产出一个解压即可安装的 zip**，避免每次换版本或环境漂移后重新试错。
- 不做什么：不做广域网/穿透方案，不做 Linux 宿主，不做客户端魔改，不评估显卡性能。

## 架构说明

本仓库同时是知识库与发行源：文档说明"为什么"，`manifest/` 与 `payload/` 决定"装什么、怎么装"，`tools/build/` 负责把两者打成 zip。

```text
sunshine-lan-streaming/
├── README.md            人层：是什么、结论、快速开始
├── AGENTS.md            人层：AI 入口（生成物，勿手改）
├── DEVELOPMENT.md       人层：本文件，仓库结构与关键问题
├── CHANGELOG.md         人层：版本历史
├── manifest/
│   └── components.json  锁定层：上游版本 / URL / SHA256 / 许可证（唯一真源）
├── payload/             装配层：进 zip 的内容
│   ├── 安装.cmd         双击入口
│   ├── scripts/         Install / Uninstall / Repair / Get-Baseline / 显示快照
│   ├── conf/            预置配置片段
│   └── licenses/        GPL-3.0 原文
├── tools/
│   ├── repo-kit/        kit 锁管理，勿动
│   └── build/           构建脚本：下载→验哈希→组装→打 zip
├── docs/
│   ├── index.md         人工导航（新增页必须挂这里，否则 ORPHAN）
│   ├── _template.md     新页模板
│   ├── 配置清单.md      状态层：36 项基线，只写取法与判据
│   ├── reports/         证据层：一次性实测快照（archived）
│   └── _generated/      生成物：索引 / 反向链接 / 踩坑清单
├── schema/              机器层：taxonomy、frontmatter 契约、kit 锁
└── dist/                产物层：打好的 zip，不入 git
```

页面按主题分五组：**选型**（分支、版本）、**实施**（虚拟显示器、部署清单）、**配置与记录**（基线清单、实测报告）、**踩坑**（一坑一篇）。

职责边界：

| 层 | 负责 | 不负责 |
|---|---|---|
| 人层四文件 | 读者能直接照做 | 机器校验 |
| `docs/**` | 一个主题一页，用 `related` 建关系 | 复制别处已定义的结论 |
| `manifest/` | 版本与哈希的唯一真源 | 安装逻辑 |
| `payload/` | 装完能直接用 | 构建流程 |
| `tools/build/` | 产出可分发 zip | 判断内容对不对 |
| `docs/reports/` | 某天实测到什么 | 长期标准 |
| 机器层 | 结构、链接、生成物、新鲜度 | 内容是否正确 |

产物层与证据层的绑定规则：**没有一份通过的真机报告，不允许发布 zip**。Release 说明必须引用对应报告的日期。

## 关键问题与方案

### 问题：断开串流时主机卡死约两分钟

**TL;DR**：Sunshine 回滚显示拓扑失败后进入每 5 秒一次的阻塞重试，把会话拆除线程堵死。

- 问题：退出串流后主机冻结、无法重连，约两分钟后服务自行重启
- 根因：`ensure_only_display` 回滚时目标设备已不在拓扑里，重试发生在拆除线程上且无超时
- 解决：`dd_configuration_option = disabled`，切屏交给外部脚本或手动 `Win+P`；`output_name` 固定指向始终存在的屏
- 预防：每次改显示相关配置后跑一次完整连接—断开循环，日志里搜 `Trying to revert applied display device settings`

详见 [docs/显示拓扑卡死.md](docs/显示拓扑卡死.md)。

### 问题：分支越换越多，稳定性反而下降

**TL;DR**：虚拟屏、HDR、桌面面板都是"增加组件"，每加一个就多一个故障点；先确认真的需要，再换。

- 问题：为了手机铺满而换到魔改分支，结果遇到新的不稳定
- 根因：魔改分支把"客户端分辨率适配"和"会话生命周期管理"捆在一起，组件数与耦合度同时上升
- 解决：按"客户端分辨率是否标准"分流；需要虚拟屏时优先用官方 + 独立 VDD，把切换权放在宿主之外
- 预防：换分支前先写下"我要解决哪一个现象"，解决不了就不换

详见 [docs/分支选型.md](docs/分支选型.md)。

> 一坑一篇；跨项目复用的内容在项目收尾时提炼到 knowledge-base 用户库。
