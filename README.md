# agent-skills-shared · 跨 Agent 技能共享方案

> 一套技能 · 只装一次 · 所有 Agent 共用

在同一台 Windows 电脑上运行多个 AI Agent（Doubao、Claude Code、Codex、Cursor、Trae、WorkBuddy 等）时，每个 Agent 都有各自的技能目录，同一技能常常要重复安装、重复维护。本项目用 **NTFS 目录联接（Junction）** 让所有 Agent 的技能根目录指向同一个「统一技能库」——**技能只装一次，处处生效**。

## 功能总览

| 功能 | 说明 | 入口 |
| --- | --- | --- |
| 统一共享技能库 | NTFS Junction 指向单一共享库，一套技能处处可见 | 核心机制 |
| 专业终端控制台 | 交互式向导：真彩渐变标题、双线框、状态栏、16 色降级 | 双击桌面「统一技能库管理」 |
| 一键搭建 | 自动迁移已有技能、智能去重、建立联接 | 向导 [1] / `setup.ps1` |
| 12 项预设 Agent 路径 | Doubao / Claude Code / Codex / Cursor / Windsurf / OpenClaw / Trae / Copilot / WorkBuddy 等，自动探测本机状态 | 向导 [1] 步骤 2 |
| 技能自动分类管理 | 9 类关键词词典自动归类，含中文简介（_meta.json） | 向导 [3]a / [3]d |
| 一键安装技能 | 支持 GitHub 仓库链接与 skills.sh 链接，自动识别仓库类型 | 向导 [3]b / `install-skill.ps1` |
| 扫描已装技能 | 随时检测各 Agent 中未进共享库的技能并迁移 | 向导 [5] / `scan-agents.ps1` |
| 双重更新检测 | 技能版本更新检测 + 项目（工具）自身版本更新检测，均可一键升级 | 向导 [6]a / [6]b |
| 桌面快捷方式 | 首次启动自动创建「统一技能库管理.lnk」 | 首次启动 |
| 全程中文 | 界面、文档、报错提示均为中文 | — |

## 为什么用 Junction？

Windows 的 NTFS **目录联接（Junction）** 是一个指向另一个目录的「指针」：

```
C:\Users\me\.claude\skills  ──(mklink /J)──▶  C:\Users\me\skills\shared
C:\Users\me\.codex\skills   ──(mklink /J)──▶  C:\Users\me\skills\shared
C:\Users\me\.cursor\skills  ──(mklink /J)──▶  C:\Users\me\skills\shared
```

- 对 Agent 而言，它「看到」的是自己的技能目录，行为无感知；
- 对使用者而言，**新增 / 更新 / 删除技能只需在共享库做一次**；
- 无需管理员权限（Junction 不像符号链接需要提权）；
- 不复制文件、不占双份磁盘，Agent 看到的技能与共享库实时一致。

> 图解：`diagrams/architecture.svg`（整体架构）、`diagrams/junction-mechanism.svg`（联接机制）。

## 快速上手（终端方式）

```powershell
# 1. 下载并解压（任选）
#    a) 浏览器打开仓库 → 绿色 Code 按钮 → Download ZIP → 解压到任意目录
#    b) 或 git clone https://github.com/JacksenHu/agent-skills-shared.git
# 2. 打开 PowerShell，进入项目目录
cd <解压目录>
# 3. 启动管理控制台（全程选择即可，无需手写 JSON）
.\scripts\setup-wizard.ps1
```

> 图解：`diagrams/quickstart-flow.svg`（快速上手流程）。

首次启动会自动在桌面创建「统一技能库管理」快捷方式，之后双击即可打开控制台。

## 管理控制台主菜单

| 选项 | 功能 |
| --- | --- |
| [1] 快速搭建 | 配置共享库与 Agent、自动迁移已有技能、建立联接 |
| [2] 验证联接 | 检查所有 Agent 的技能可见性 |
| [3] 技能管理 | 分类清单 / GitHub、skills.sh 仓库安装 / 移除 / 分类浏览 |
| [4] 接入 / 移除 Agent | 新增或拆除 Agent 联接 |
| [5] 扫描已装技能 | 发现各 Agent 中未进共享库的技能 |
| [6] 检查更新 | **a** 技能版本更新 / **b** 项目（工具）版本更新 |
| [7] 帮助与文档 | docs 导航与常用命令 |
| [0] 退出 | 结束会话 |

## 控制台界面特性

- **VT 真彩色渐变**：Windows 10+ 虚拟终端下，标题采用亮蓝→深蓝渐变，支持 24 位真彩色；
- **双线框面板**：所有菜单、提示、确认框统一双线框风格（╔═║╚）；
- **语义配色**：主蓝 / 成功绿 / 警告琥珀 / 错误红 / 金高亮，操作反馈一眼可辨；
- **状态栏**：主菜单底部实时显示 共享库路径 · 技能数 · Agent 数；
- **16 色降级**：终端不支持 ANSI 时自动降级为 16 色输出，功能不受影响；
- **中文兼容**：全部脚本以 UTF-8 BOM 保存，Windows PowerShell 5.1 下中文不乱码。

## 检测技能版本更新

```powershell
# 对比各技能的 GitHub 来源仓库版本（只有仓库链接安装的技能可检测）
.\scripts\check-updates.ps1
# 自动升级检测到的「有更新」仓库
.\scripts\check-updates.ps1 -Update
```

也可在向导主菜单选 [6] → **a**。升级完成后重启各 Agent 会话生效。

## 检测本项目（工具）自身更新（新版本推送）

```powershell
# 只检测：对比本地 VERSION 与 GitHub 仓库远程 VERSION（公开仓库，匿名即可）
.\scripts\check-project-updates.ps1
# 检测并一键升级（git clone 或下载 ZIP，自动排除 config\agents.json）
.\scripts\check-project-updates.ps1 -Update
# 可选：设置 GitHub Token 提高 API 配额（匿名限速 60 次/小时）
.\scripts\check-project-updates.ps1 -Token ghp_xxx
```

也可在向导主菜单选 [6] → **b**。升级完成后新版本立即生效（无需重启 Agent）。
Token 可选：GitHub → Settings → Developer settings → Personal access tokens →
Generate new token (classic)；也可设置环境变量 `GITHUB_TOKEN` 自动使用，
Token 无效时脚本会自动降级为匿名访问。

> 图解：`diagrams/check-project-updates-flow.svg`（项目更新检测流程）。

## 目录结构

```
agent-skills-shared/
├─ config/
│   ├─ agents.example.json      # 示例配置（12 项预设 Agent 路径）
│   └─ agents.json              # 本机真实配置（安装时自动生成，勿提交）
├─ scripts/
│   ├─ setup-wizard.ps1         # ★ 管理控制台（交互式向导，主入口）
│   ├─ setup.ps1                # 一键搭建（迁移 + 去重 + 建立联接）
│   ├─ verify.ps1               # 验证所有联接
│   ├─ add-agent.ps1            # 接入单个 Agent
│   ├─ remove-agent.ps1         # 移除单个 Agent
│   ├─ scan-agents.ps1          # 扫描各 Agent 已装技能
│   ├─ install-skill.ps1        # 从 GitHub / skills.sh 链接安装技能
│   ├─ check-updates.ps1        # 技能版本更新检测（含 -Update）
│   └─ check-project-updates.ps1# 项目（工具）自身更新检测（含 -Update）
├─ diagrams/                    # 图解（SVG）
├─ docs/                        # 文档（01-06）
├─ VERSION                      # 项目版本基准（更新检测用）
└─ README.md
```

## 文档与图解

| 文档 | 内容 |
| --- | --- |
| docs/01-architecture.md | 方案原理（Junction、目录结构） |
| docs/02-agent-path-reference.md | 各 Agent 技能目录速查 |
| docs/03-setup-guide.md | 搭建指南 |
| docs/04-day-to-day.md | 日常使用（增删技能、增删 Agent、更新检测） |
| docs/05-safety-and-rollback.md | 风险与回滚 |
| docs/06-faq.md | 常见问题 |

| 图解 | 内容 |
| --- | --- |
| diagrams/architecture.svg | 整体架构 |
| diagrams/junction-mechanism.svg | Junction 联接机制 |
| diagrams/setup-flow.svg | 搭建流程 |
| diagrams/update-flow.svg | 技能更新流程 |
| diagrams/rollback-flow.svg | 回滚流程 |
| diagrams/skills-management.svg | 技能管理流程 |
| diagrams/check-updates-flow.svg | 技能版本检测流程 |
| diagrams/quickstart-flow.svg | 快速上手流程 |
| diagrams/check-project-updates-flow.svg | 项目（工具）更新检测流程 |

## 环境要求

- Windows 10 / 11（NTFS）
- PowerShell 5.1+（系统自带）
- **不需要管理员权限**（Junction 无需提权）
- 可选依赖：`git`（项目自身更新检测 -Update 时优先使用，未安装则自动改用下载 ZIP）；`GitHub Token`（可选，用于提高 GitHub API 配额，匿名限速 60 次/小时）

## 已知边界

- **Junction 与备份/同步**：部分网盘或备份工具可能不跟随 Junction；备份共享库目录本身即可。
- **索引时机**：绝大多数 Agent 在会话启动时扫描技能，改动后需重启会话。
- **API 配额**：技能更新检测（`check-updates.ps1`）与项目更新检测（`check-project-updates.ps1`）匿名访问 GitHub API 限速 60 次/小时，多技能/频繁检测时可设置 Token 提高配额。
- **Junction 会「挡住」同目录已有内容**：将 Agent 技能目录联接为共享库时，若该目录已有技能，迁移脚本会先复制进共享库并自动去重，再建立联接；不会丢数据。

## License

MIT
