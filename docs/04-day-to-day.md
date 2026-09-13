# 04 · 日常使用

> 原则只有一条：**所有技能操作都在共享库目录进行**，所有 Agent 自动跟随。

## 1. 新增一个技能

**方式 A（推荐）· 从 GitHub 仓库一键安装：**

```powershell
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/skill-repo"
```

脚本自动：下载仓库（zip，无需 git）→ 识别技能（根目录有 `SKILL.md` 视为单技能，
否则把每个含 `SKILL.md` 的子目录作为独立技能）→ 复制进共享库 → 报告结果。
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

## 7. 图解

![日常更新流程](update-flow.svg)
