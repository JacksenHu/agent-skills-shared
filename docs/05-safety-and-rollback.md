# 05 · 风险清单与回滚

## 1. 风险总览

| # | 风险 | 影响 | 缓解 |
| --- | --- | --- | --- |
| 1 | 对 Junction 用递归删除（`Remove-Item -Recurse`、`robocopy /MIR`、`rmdir /s`） | **穿透联接删除共享库真实数据** | 永远只对联接本身用 `cmd /c rmdir` 或 `Remove-Item -Force`；删除共享库内技能时直接操作共享库路径 |
| 2 | 移动/重命名共享库目录 | 所有联接失效（Junction 记录绝对路径） | 移动后跑 `verify.ps1`，重建联接 |
| 3 | 一个 Agent 内误改/误删技能 | 所有 Agent 同时变化 | 改动前用 git/备份；按第 3 节回滚 |
| 4 | 磁盘空间/权限异常 | 共享库不可写 → 所有 Agent 技能异常 | `verify.ps1` 巡检；共享库放 NTFS 本地盘 |
| 5 | 杀毒软件/索引器扫描穿透 | 偶发 IO 压力，功能不受影响 | 一般无需处理；敏感场景可加白名单 |
| 6 | Agent 升级改变技能目录约定 | 联接目标不再是该 Agent 的读取路径 | 关注 Agent 更新日志；路径变化时改配置重跑 setup |
| 7 | 平台专属语法不通用 | 技能内容共享但个别命令在其他 Agent 无效 | 只共享通用 Prompt 型技能 |

## 2. 高危操作红线（务必牢记）

```powershell
# ✅ 安全：删除"联接本身"（只拆门，不动数据）
cmd /c rmdir "C:\Users\<你>\.claude\skills"

# ✅ 安全：删除共享库内的真实技能目录
Remove-Item -Recurse "C:\Users\<你>\skills\shared\unused-skill"

# ❌ 危险：对"联接路径"递归删除 —— 会穿透删除共享库数据
Remove-Item -Recurse "C:\Users\<你>\.claude\skills"        # 禁止！
robocopy 空目录 "C:\Users\<你>\.claude\skills" /MIR        # 禁止！
cmd /c rmdir /s /q "C:\Users\<你>\.claude\skills"          # 禁止！
```

判断路径是否为联接：

```powershell
(Get-Item "C:\Users\<你>\.claude\skills").LinkType   # 输出 Junction = 是联接
```

## 3. 回滚流程

![回滚流程](rollback-flow.svg)

### 场景 A：只想让某个 Agent 脱离共享（拆门）

```powershell
.\scripts\remove-agent.ps1 -AgentName claude-code
```

该 Agent 的技能根目录变回空目录，共享库数据不受影响。

### 场景 B：某 Agent 的技能被误删，需要恢复

1. 从共享库找到（或重新安装）该技能；
2. 若该 Agent 已拆联接：直接复制到它的原目录；
3. 未拆联接：直接写回共享库，Agent 自动恢复。

### 场景 C：彻底回退整个方案（恢复"各自独立"状态）

```powershell
# 1. 逐个拆除联接（技能仍完整保留在共享库）
.\scripts\remove-agent.ps1 -AgentName doubao-user-skills
.\scripts\remove-agent.ps1 -AgentName claude-code
# ...（所有 Agent）

# 2. 把技能从共享库复制回各 Agent 原目录
Copy-Item -Recurse "C:\Users\<你>\skills\shared\*" "C:\Users\<你>\.claude\skills\"

# 3.（可选）清理共享库
Remove-Item -Recurse "C:\Users\<你>\skills\shared"
```

> 由于方案本身"数据只存一份"，回滚 = 拆联接 + 分发副本，任何时刻数据都不会因拆联接而丢失。

## 4. 建议的维护习惯

- 共享库纳入 git 版本管理（`git init` + 定期 commit），误删可回退；
- 改动前后各跑一次 `verify.ps1`；
- 新技能先在共享库放一个测试技能验证全链路，再批量迁移；
- 不要把系统级技能目录（如 Doubao `.skills`）纳入共享。
