# 03 · 完整搭建指南

## 0. 前置条件

- Windows 10 / 11，技能目录所在分区为 **NTFS**；
- PowerShell 5.1+（系统自带）；
- **无需管理员权限**；
- 阅读 [`01-architecture.md`](01-architecture.md) 理解机制，先看 [`05-safety-and-rollback.md`](05-safety-and-rollback.md) 了解风险。

## 0.5 获取项目（还没下载的话）

```text
方式一（无需 git）：
  仓库首页 → Code → Download ZIP → 解压到任意目录（如 C:\agent-skills-shared）
  注意：ZIP 解压后目录名通常带 -main 后缀，进入该目录操作

方式二（推荐，更新方便）：
  git clone https://github.com/JacksenHu/agent-skills-shared.git
```

首次运行脚本前，若 PowerShell 提示"禁止运行脚本"，先放行（只影响当前用户）：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

然后进入项目目录启动向导（全程选择即可，无需手写 JSON）：

```powershell
cd C:\agent-skills-shared        # 换成你的实际目录
.\scripts\setup-wizard.ps1
```

**首次启动会自动创建桌面快捷方式**：桌面出现「统一技能库管理」图标，
以后**双击它即可打开管理控制台**（等同运行向导）；不需要可自行删除。
若移动/删除了项目文件夹导致快捷方式失效，删掉旧快捷方式、再启动一次向导即可自动重建。

> 更新项目：git 方式 `git pull`；ZIP 方式重新下载解压后，**不要覆盖**你生成的 `config\agents.json`。

## 1. 准备配置文件

**方式 A（推荐）· 交互式引导**，无需手写 JSON：

```powershell
.\scripts\setup-wizard.ps1
# 首次运行后，也可以直接双击桌面「统一技能库管理」打开
```

流程：脚本自动探测本机常见 Agent 技能目录（Doubao / Claude Code / Codex / Cursor…，
已检测到的会标注）→ 按提示输入编号勾选要接入的 Agent（可自定义添加其他路径）→
选择共享库位置（默认 `%USERPROFILE%\skills\shared`）→ 确认后自动完成
「生成 `config\agents.json` → 搭建 → 验证」三步。

若 `config\agents.json` 已存在，脚本会询问是否直接沿用现有配置。

**方式 B · 手动编辑 JSON：**

```powershell
# 复制模板
copy config\agents.example.json config\agents.json

# 编辑：把 <你的用户名> 替换为真实用户名，并增删你实际使用的 Agent
notepad config\agents.json
```

示例（已按常见情况填好）：

```json
{
  "sharedRoot": "C:\\Users\\24664\\skills\\shared",
  "agents": {
    "doubao-user-skills": "C:\\Users\\24664\\AppData\\Local\\Doubao\\User Data\\Default\\.doubao\\agent_mode\\workspace\\.user_skills",
    "claude-code": "C:\\Users\\24664\\.claude\\skills",
    "codex-agents-skills": "C:\\Users\\24664\\.agents\\skills",
    "cursor": "C:\\Users\\24664\\.cursor\\skills"
  }
}
```

要点：

- JSON 中 Windows 路径的反斜杠要写成 `\\`；
- `agents` 里的键名只是备注（如 `claude-code`），可随意命名；
- 只写**确实存在且想共享**的目录；**不要**把 Doubao 的 `.skills`（系统技能目录，110+ 个内置技能）写进去；
- 不同 Agent 指向同一路径（如 `.agents\skills` 被 Codex 和 Cursor 共用）时写一次即可，脚本自动去重。

## 2. 试运行（不真正执行）

```powershell
.\scripts\setup.ps1 -WhatIf
```

输出会列出脚本**将要做**的每一步：哪些目录会被迁移、哪些会建联接。确认无误再继续。

## 3. 正式执行

```powershell
.\scripts\setup.ps1
```

脚本做的事（按 [`01-architecture.md`](01-architecture.md) 第 4 节语义）：

1. 创建共享库目录；
2. 逐个 Agent 根目录：
   - 不存在 → 建 Junction；
   - 已是 Junction → 校验目标，跳过；
   - 真实目录且有内容 → **迁移进共享库**（冲突保留并报告）→ 删空目录 → 建 Junction；
3. 末尾自动跑一遍验证，输出结果表。

## 4. 验证

```powershell
.\scripts\verify.ps1
```

期望输出（每行一个 Agent）：

```text
[OK]   doubao-user-skills  →  C:\Users\24664\skills\shared   (35 个 SKILL.md)
[OK]   claude-code         →  C:\Users\24664\skills\shared   (35 个 SKILL.md)
[FAIL] cursor              →  目录不存在或不是联接
```

出现 `[FAIL]` 时按提示处理（常见：路径写错、目录还是真实目录）。

## 5. 让技能生效

重启各 Agent（新开会话）。绝大多数 Agent 在启动时扫描技能目录：

- Doubao：新开一个对话；
- Claude Code：重启会话，或 `--add-dir` 场景下热加载；
- Codex / Cursor：重启会话或重载窗口。

## 6. 图解

![搭建流程](setup-flow.svg)

![快速使用流程（含桌面快捷方式）](quickstart-flow.svg)

## 6.1 从 GitHub / skills.sh 仓库一键安装技能

搭建完成后，遇到想装的技能仓库，直接一条命令装进共享库（所有 Agent 生效）：

```powershell
# GitHub 仓库
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/skill-repo"

# skills.sh 技能市场（Vercel，底层仍是 GitHub 仓库）
.\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/owner/repo"

# 指定仓库里的某个技能
.\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/owner/repo/skill-name"
```

- 自动下载（zip，无需 git），自动识别技能结构：仓库根有 `SKILL.md` → 单技能；否则每个含 `SKILL.md` 的子目录都是一个技能；链接指定技能名时只装该技能；
- 同名冲突默认**跳过**并报告，`-Replace` 强制替换旧版本；
- 安装后自动生成 `_meta.json`（中文简介），技能管理列表显示；
- 检测到 `package.json` / `requirements.txt` 等依赖清单会给出提示。
- 也可在交互控制台 `setup-wizard.ps1` → [3] 技能管理 → [b] 输入链接安装。

## 6.2 已有技能的迁移与去重策略

`setup.ps1` / `add-agent.ps1` 处理"Agent 目录里已有的技能"时：

| 情况 | 处理 |
| --- | --- |
| 共享库无同名 | **迁移**进共享库（移动，数据不丢） |
| 同名且内容一致 | **自动去重**：删冗余副本，共享库保留一份 |
| 同名且内容不同 | **冲突**：两边保留，提示人工决定，处理后再跑 |

"内容一致"按目录内所有文件的相对路径 + SHA-256 哈希比对。

## 6.3 技能管理与扫描（日常都在交互控制台完成）

搭建完成后，推荐统一从 `setup-wizard.ps1` 进入：

- **[3] 技能管理**：
  - `a` **按分类分组列出**技能（9 大分类自动归类，每行含中文简介）；
  - `b` 从 **GitHub / skills.sh 仓库链接**安装技能（同 6.1 命令，输入链接即可）；
  - `c` 移除技能（双重确认，防止误删）；
  - `d` **按分类浏览**（先列分类清单，输入编号查看该类技能）；
  - `e` **生成/刷新总路由技能（skill-router）**：扫描共享库按 9 大分类生成 `router-guide\SKILL.md`，在任何 Agent 中触发它即可按情境推荐共享库技能（**全量收录，不设排除名单**）。
- **[5] 扫描各 Agent 已安装技能**：逐个检查配置中的 Agent 目录，标注每个技能的状态（已接入共享库 / 已共享内容一致 / 冲突 / 独有 / 目录不存在），发现"独有"技能按提示迁移进共享库即可。

图解见 [`diagrams/skills-management.svg`](../diagrams/skills-management.svg)。

## 7. 搭建后的状态

```text
C:\Users\24664\skills\shared\        ← 唯一的技能数据源
  ├─ tdd/
  ├─ grill-me/
  ├─ code-review/
  └─ ...（你已安装的全部技能）

C:\Users\24664\.claude\skills  ──Junction──▶  shared
C:\Users\24664\.agents\skills ──Junction──▶  shared
C:\...\Doubao\.user_skills    ──Junction──▶  shared
```

此时任意 Agent 里看到的技能列表完全一致。
