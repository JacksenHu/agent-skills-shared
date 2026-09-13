# 03 · 完整搭建指南

## 0. 前置条件

- Windows 10 / 11，技能目录所在分区为 **NTFS**；
- PowerShell 5.1+（系统自带）；
- **无需管理员权限**；
- 阅读 [`01-architecture.md`](01-architecture.md) 理解机制，先看 [`05-safety-and-rollback.md`](05-safety-and-rollback.md) 了解风险。

## 1. 准备配置文件

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
