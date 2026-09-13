# Agent Skills 共享方案（统一目录 + 目录联接）

> **一个技能，只装一次，所有 Agent 共用。**
>
> 用 Windows 目录联接（NTFS Junction）把每个 Agent 的技能根目录指向同一个共享技能库，
> 解决「N 个 Agent × M 个技能 = N×M 次安装」的重复劳动问题。

![架构图](diagrams/architecture.svg)

## 痛点

同时使用多个 Agent 软件（Doubao、Claude Code、Codex、Cursor、Windsurf、OpenClaw……）时，
每个 Agent 都从各自的固定目录加载技能：

| Agent | 技能根目录（用户级） |
| --- | --- |
| Doubao（豆包） | `%USERPROFILE%\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills` |
| Claude Code | `%USERPROFILE%\.claude\skills\` |
| Codex / Cursor | `%USERPROFILE%\.agents\skills\` |
| Cursor | `%USERPROFILE%\.cursor\skills\` |
| OpenClaw | `%USERPROFILE%\.openclaw\workspace\skills\` |

装一个技能就要复制到每个目录；更新一个技能就要逐个覆盖。重复、易漏、版本漂移。

## 方案核心

1. **一个共享技能库**（唯一数据源）：`C:\Users\<you>\skills\shared`
2. **每个 Agent 的技能根目录 → 目录联接（Junction）指向共享库**
3. 读写穿透、实时共享：在共享库新增/更新/删除一个技能，**所有 Agent 的新会话同时生效**

### 为什么用 Junction 而不是复制 / 符号链接

| 方式 | 一次安装处处生效 | 需管理员权限 | 改动即时同步 | 跨卷 | 风险 |
| --- | :-: | :-: | :-: | :-: | --- |
| 复制到各目录 | ❌ | ❌ | ❌ | ✅ | 版本漂移 |
| 符号链接 `mklink /D` | ✅ | ✅（或开开发者模式） | ✅ | ✅ | 权限门槛高 |
| **目录联接 `mklink /J`（本方案）** | ✅ | ❌ | ✅ | ✅ | 删除语义需注意（见下文） |

## 快速开始

**方式 A（推荐）· 交互式控制台，全程只需选择：**

```powershell
.\scripts\setup-wizard.ps1
```

打开**首页主菜单**：快速搭建 / 验证 / 技能管理（列出、从 GitHub 仓库链接安装、移除）/
接入移除 Agent / 帮助。搭建时**预设 11 个常见 Agent 技能路径**（Doubao、Claude Code、
Codex、Cursor、Windsurf、OpenClaw、Trae、Trae CN、GitHub Copilot、Zed 等，均来自官方文档），
自动探测本机哪些已安装 → 输入 `d` **一键全选已检测到的**，或按编号勾选 → 回车确认，
自动完成：生成配置 → 迁移已有技能（**内容一致自动去重、内容不同提示冲突**）
→ 建立联接 → 验证，无需手写任何 JSON。

**从仓库链接一键装技能（含在其他终端/脚本中）：**

```powershell
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/skill-repo"
```

**方式 B · 手动配置：**

```powershell
# 1. 复制配置模板并填写你的 Agent 路径
copy config\agents.example.json config\agents.json
notepad config\agents.json

# 2. 试运行（只看会做什么，不真正执行）
.\scripts\setup.ps1 -WhatIf

# 3. 正式执行
.\scripts\setup.ps1

# 4. 验证所有 Agent 的技能可见性
.\scripts\verify.ps1

# 5. 重启各 Agent 会话，技能生效
```

> ⚠️ 脚本会自动把各 Agent 目录里**已有的技能迁移**进共享库（同名冲突会保留原文件并生成报告，不会覆盖）。
> 脚本只处理你写入 `agents.json` 的路径，**不会**触碰 Doubao 的 `.skills` 系统技能目录。

## 目录结构

```
agent-skills-shared/
├── README.md                      # 本文件（总览）
├── docs/
│   ├── 01-architecture.md         # 方案详解：机制、原理、对比
│   ├── 02-agent-path-reference.md # 各 Agent 技能目录速查表（带官方来源）
│   ├── 03-setup-guide.md          # 完整搭建指南（迁移/验证/生效）
│   ├── 04-day-to-day.md           # 日常使用：新增/更新/删除技能、增删 Agent
│   ├── 05-safety-and-rollback.md  # 风险清单与回滚流程
│   └── 06-faq.md                  # 常见问题
├── diagrams/                      # 图解（SVG，GitHub 可直接渲染）
│   ├── architecture.svg           # 整体架构图
│   ├── junction-mechanism.svg     # Junction 机制原理图
│   ├── setup-flow.svg             # 搭建流程
│   ├── update-flow.svg            # 日常更新流程
│   └── rollback-flow.svg          # 回滚流程
├── config/
│   └── agents.example.json        # Agent 路径配置模板（含 11 项预设）
└── scripts/
    ├── setup-wizard.ps1            # 交互式控制台：首页菜单（搭建/验证/技能管理/仓库安装）
    ├── setup.ps1                   # 一键搭建：迁移（智能去重）+ 建联接 + 验证
    ├── install-skill.ps1           # 从 GitHub 仓库链接一键安装技能到共享库
    ├── add-agent.ps1               # 为单个 Agent 建立联接（含去重/冲突处理）
    ├── remove-agent.ps1            # 移除单个 Agent 的联接（回滚）
    └── verify.ps1                  # 验证所有联接与技能可见性
```

## 文档导航

- 想理解原理 → [`docs/01-architecture.md`](docs/01-architecture.md)（含机制图解）
- 想核对你的 Agent 路径 → [`docs/02-agent-path-reference.md`](docs/02-agent-path-reference.md)
- 想完整搭建 → [`docs/03-setup-guide.md`](docs/03-setup-guide.md)
- 想日常维护 → [`docs/04-day-to-day.md`](docs/04-day-to-day.md)
- 想了解风险 → [`docs/05-safety-and-rollback.md`](docs/05-safety-and-rollback.md)
- 有问题先看 → [`docs/06-faq.md`](docs/06-faq.md)

## 环境要求

- Windows 10 / 11（NTFS 分区）
- PowerShell 5.1+（Windows 自带）
- **不需要管理员权限**（Junction 无需提权）

## 已知边界

- **内容共享 ≠ 行为通用**：Agent 平台专属语法（Claude Code 的斜杠命令、OpenClaw 的插件配置等）不会跨平台生效，共享的是通用 Prompt 型技能。
- **共享命运**：在一个 Agent 里删改技能会影响所有 Agent——这是特性，也是风险（见风险文档）。
- **索引时机**：绝大多数 Agent 在会话启动时扫描技能，改动后需重启会话。
- 本项目面向 Windows；macOS / Linux 用户可用符号链接（`ln -s`）实现同一思路。

## License

[MIT](LICENSE)
