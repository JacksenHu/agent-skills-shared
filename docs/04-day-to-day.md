# 04 · 日常使用

> 原则只有一条：**所有技能操作都在共享库目录进行**，所有 Agent 自动跟随。

## 1. 新增一个技能

**方式 A（推荐）· 从 GitHub / skills.sh 仓库一键安装：**

```powershell
# GitHub 仓库
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/skill-repo"

# skills.sh 技能市场（Vercel，底层仍是 GitHub 仓库）
.\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/owner/repo"

# skills.sh 指定仓库里的某个技能（只装这一个）
.\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/owner/repo/skill-name"
```

脚本自动：下载仓库（zip，无需 git）→ 识别技能（根目录有 `SKILL.md` 视为单技能，
否则把每个含 `SKILL.md` 的子目录作为独立技能；若链接指定技能名则只装该技能）
→ 复制进共享库 → 为每个技能生成 `_meta.json`（名称 + 中文简介 + 来源）→ 报告结果。
同名冲突默认跳过（加 `-Replace` 强制替换旧版本）。

```powershell
# 单技能仓库（如 findskills）→ 安装为 shared\findskills
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/hgta23/findskills"

# 多技能仓库（35+ 个技能在子目录）→ 全部安装进共享库
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/vinvcn/mattpocock-skills-zh-CN"
```

**方式 B · 手动复制：**

```powershell
# 把技能目录整个复制进共享库（保持"每个技能一个子目录 + SKILL.md"的结构）
Copy-Item -Recurse C:\下载\some-skill C:\Users\<你>\skills\shared\some-skill

# 验证
.\scripts\verify.ps1
```

重启各 Agent 会话后，新技能在所有 Agent 中可见。

> **关于中文简介与自动分类**：安装时会自动从 SKILL.md 提取简介；英文简介会尝试在线翻译为
> 中文并缓存在 `_meta.json`。技能管理列表（向导 [3]a）按**自动分类**分组显示中文简介
> （分类依据：SKILL.md frontmatter 的 category/type/tags 字段优先，其次按名称+简介关键词
> 匹配到开发/写作/研究/办公/数据/设计/音视频/Agent 管理等类别；也可在 [3]d 按分类浏览）。
> 手动复制的技能没有 `_meta.json`，列表直接显示 SKILL.md 中的 description。

## 2. 更新一个技能

```powershell
# 用新版本替换共享库里的旧目录（先删旧目录再放新目录，避免残留文件）
Remove-Item -Recurse C:\Users\<你>\skills\shared\old-skill   # ⚠️ 这是共享库内的真实目录，删除安全
Copy-Item -Recurse C:\下载\new-skill C:\Users\<你>\skills\shared\new-skill
```

所有 Agent 下一次会话读到新版本。

## 3. 删除一个技能

```powershell
Remove-Item -Recurse C:\Users\<你>\skills\shared\unused-skill
```

⚠️ **所有 Agent 同时失去该技能**。这是共享的特性，删除前请确认。

## 4. 接入一个新的 Agent

```powershell
# 方式一：把新 Agent 的路径加进 config\agents.json，然后
.\scripts\add-agent.ps1 -AgentName 新Agent备注 -RootPath "C:\...\新目录"

# 方式二：只加进配置文件，重跑 setup（自动处理增量）
.\scripts\setup.ps1
```

add-agent 与 setup 对单个目录的语义完全一致（迁移已有内容 → 建联接）。

## 5. 移除一个 Agent（不再共享）

```powershell
.\scripts\remove-agent.ps1 -AgentName claude-code
```

只拆除该 Agent 的**联接（门）**，共享库数据保留。如需把技能物归原位，见回滚文档。

## 6. 巡检

```powershell
# 随时检查：哪些联接正常、每个 Agent 能看到多少技能
.\scripts\verify.ps1
```

建议每周/每次改动后跑一次。

## 7. 检测各 Agent 已安装技能（重要）

在某个 Agent 里**手动安装**的技能（如 Claude Code 的 `/install`、Codex 的 `add` 等）
会落在该 Agent 自己的技能目录，**不会**自动进共享库。本方案提供扫描工具：

```powershell
# 扫描 config\agents.json 里所有 Agent 目录
.\scripts\scan-agents.ps1

# 或在向导主菜单选 [5] 扫描各 Agent 已安装技能
```

每个 Agent 目录的状态会标注为：

| 状态 | 含义 | 建议 |
| --- | --- | --- |
| ✅ 已接入共享库 | 该目录是 Junction，技能全部来自共享库 | 无需处理 |
| [已共享] | 该 Agent 目录里的技能与共享库**内容一致**（重复安装） | 可删除该目录下的这份，避免占空间 |
| [冲突] | 与共享库同名但**内容不同**（两边都有） | 人工对比后保留一份，移除另一份 |
| [独有] | 共享库**没有**该技能（只存在于该 Agent） | 迁移进共享库，让所有 Agent 共用 |
| ✗ 目录不存在 | 该 Agent 未安装或路径已变 | 检查路径 |

**"独有"技能迁移到共享库**（二选一）：

```powershell
# 方式一：该 Agent 目录整目录接入共享库（目录里所有技能都会并入共享库）
.\scripts\setup.ps1   # 或在向导 [1] 快速搭建中重新勾选该 Agent

# 方式二：只迁移单个技能目录
Copy-Item -Recurse C:\...\agent-skill-dir C:\Users\<你>\skills\shared\<技能名>
```

> 提示：把 Agent 目录接入共享库后，以后在该 Agent 里手动安装的技能会自动
> 出现在共享库（因为目录就是共享库），不再需要手动迁移。

## 8. 图解

![日常更新流程](update-flow.svg)
