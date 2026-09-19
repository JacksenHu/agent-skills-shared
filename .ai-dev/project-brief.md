# Project Brief — 项目概况

> 回答 “这是什么项目、由什么构成、怎么跑起来”。保持一页以内，细节交给架构文档和代码索引。

## 一句话定位

Windows 上的「统一技能库」管理方案：一套技能只装一次，通过 NTFS Junction 让所有 AI Agent（豆包 / Claude Code / Codex / Cursor / WorkBuddy / CodeBuddy / Trae / Marvis 等）共用同一份技能；配套 PowerShell 交互式控制台完成接入、验证、技能管理、更新检测。

## 用户与核心场景

- 目标用户：同时使用多个 AI 编程 / Agent 软件、厌倦重复安装维护技能的用户（本人）。
- 核心场景：双击桌面「统一技能库管理」→ [1] 快速搭建（或 [4]a 接入新 Agent）→ 建好 Junction 后所有 Agent 新会话自动看到共享库技能；[3] 管理技能（仓库安装 / 分类 / 总路由）；[6] 检查技能与项目自身更新。

## 技术栈（含版本，版本号必须真实，不确定就标 “待确认”）

| 层  | 选型 | 版本 | 备注 |
| -- | -- | -- | -- |
| 语言 | PowerShell 脚本 | 5.1+（Windows 自带） | 交互向导 + 各功能脚本；全脚本 UTF-8 带 BOM |
| 框架 | 无（纯脚本） | — | 可选依赖 git（项目自更时优先用） |
| 存储 | 文件系统 + JSON | — | 共享库 = `%USERPROFILE%\skills\shared`；配置 = `config\agents.json`（私有，不入库，模板为 agents.example.json） |
| 部署 | GitHub 公开仓库 | main 分支 | 用户以 ZIP 解压 / git clone 分发；`check-project-updates.ps1` 对比 VERSION |

## 顶层目录结构

- `scripts/` — 全部功能脚本（见 architecture.md 模块表）
- `config/` — agents.json（私有配置，gitignore 排除）与 agents.example.json（24 项预设模板）
- `docs/` — 01 架构 / 02 各 Agent 路径速查 / 03 搭建指南 / 04 日常 / 05 风险回滚 / 06 FAQ
- `diagrams/` — SVG 图解（架构、Junction 原理、搭建、日常、技能管理、更新检测、快速使用、回滚）
- `.ai-dev/` — devctx 统一上下文（本目录），不入库推送

## 常用命令（复制即可运行）

```text
# 主入口：交互式控制台（首次运行自动建桌面快捷方式）
.\scripts\setup-wizard.ps1

# 一键搭建 / 验证
.\scripts\setup.ps1 -WhatIf        # 试运行
.\scripts\setup.ps1                # 正式执行
.\scripts\verify.ps1               # 验证所有 Agent 联接与技能可见性

# 技能管理
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/repo"
.\scripts\generate-router-skill.ps1    # 生成/刷新总路由技能 skill-router

# 更新检测
.\scripts\check-updates.ps1        # 技能版本
.\scripts\check-project-updates.ps1 -Update   # 项目自更
```

## 环境与外部依赖

- 环境变量：可选 `GITHUB_TOKEN`（提高 GitHub API 配额，匿名 60 次/小时）
- 必需外部服务：GitHub（公开仓库 JacksenHu/agent-skills-shared）
- 密钥获取方式：GitHub → Settings → Developer settings → Personal access tokens (classic)

## 当前里程碑 / 边界

- 本期做：24 项 Agent 路径预设（含国际版）、skill-router 总路由技能、技能/项目双更新检测、豆包多根重复根治
- 明确不做：macOS/Linux 原生支持（文档给出 ln -s 等价思路）；不触碰各 Agent 的平台内置技能目录（如豆包 .skills 系统根）；`config\agents.json` 永不入库
