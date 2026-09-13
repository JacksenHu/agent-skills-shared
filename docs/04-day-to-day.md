# 04 · 日常使用

> 场景：新增 / 更新 / 删除技能，接入 / 移除 Agent，扫描，更新检测。

## 0. 总览

```
日常维护 = 技能操作（增/改/删） + Agent 操作（接/拆） + 巡检（验证/扫描/更新）
```

- **技能操作**：直接操作共享库 `%USERPROFILE%\skills\shared\<技能名>`，或向导 [3] 技能管理。
- **Agent 操作**：向导 [4]，或 `add-agent.ps1` / `remove-agent.ps1`。
- **巡检**：向导 [2] 验证、[5] 扫描、[6] 更新检测。

> 图解：`diagrams/skills-management.svg`（技能管理流程）、`diagrams/update-flow.svg`（更新流程）。

## 1. 新增技能

### 1a. 手动放进共享库

把技能文件夹复制/解压到共享库：

```powershell
Copy-Item .\my-skill -Destination "$env:USERPROFILE\skills\shared\" -Recurse
```

技能目录应含 `SKILL.md`（技能定义，多数 Agent 以此为入口）。

### 1b. 用向导安装（推荐）

向导主菜单 [3] → **b**，输入仓库链接，自动识别 GitHub 仓库或 skills.sh 链接并安装：

```
https://github.com/hgta23/findskills
https://skills.sh/s/vercel-labs/skills/find-skills
```

- 自动将技能解压到共享库；
- 自动读取 `SKILL.md` 生成中文简介（`_meta.json`）；
- GitHub 仓库安装会记录仓库地址与 commit 基准（用于 [6]a 更新检测）；
- skills.sh 链接安装暂不记录来源（无法检测升级）。

安装完成后重启各 Agent 会话（新开会话）生效。

## 2. 更新技能

### 2a. 更新某个技能（手动）

直接删除共享库中该技能目录并重新安装，或覆盖同名文件。

### 2b. 检测本项目（工具）自身更新

项目自身更新检测脚本 `check-project-updates.ps1`，对比本地 `VERSION` 与 GitHub 仓库远程版本：

```powershell
# 只检测：对比本地 VERSION 与 GitHub 仓库远程 VERSION（公开仓库，匿名即可）
.\scripts\check-project-updates.ps1

# 检测并一键升级（git clone 或下载 ZIP；自动排除 config\agents.json）
.\scripts\check-project-updates.ps1 -Update

# 可选：设置 GitHub Token 提高 API 配额（匿名限速 60 次/小时）
.\scripts\check-project-updates.ps1 -Token ghp_xxx
```

或在向导主菜单选 [6] → **b**。

要点：

- 本地 `VERSION`（项目根）记录当前版本号；远程对比 GitHub 仓库 main 分支的 `VERSION`。
- 判定结果四类：`[最新]` 已是最新 / `[有更新]` 本地落后（显示 本地 → 远程）/ `[无基准]` 本地无 VERSION（旧版解压，`-Update` 同步一次）/ `[不可查]` 远程读不到。
- `-Update` 升级前会列出差异文件并**二次确认**；`config\agents.json`（你的 Agent 配置）**永不覆盖**。
- Token 可选（仅提高 API 配额）：GitHub → Settings → Developer settings → Personal access tokens（classic）→ 勾选 `repo`；
  也可设置环境变量 `GITHUB_TOKEN`，脚本自动读取；Token 无效时自动降级为匿名访问。
- git 克隆目录也可以直接 `git pull` 升级（同样注意勿覆盖 `config\agents.json`）。
- 升级完成后新版本立即生效，无需重启 Agent。

> 图解：`diagrams/check-project-updates-flow.svg`。

## 3. 删除技能

- **推荐**：向导主菜单 [3] → **c**，选择技能并二次确认（输入技能名）后删除；
- 或直接删除共享库中的技能目录。

> 删除是永久操作：共享库删除后，所有 Agent 的该技能立即消失（Junction 是实时指针）。
> 回滚方案见 `docs/05-safety-and-rollback.md`。

## 4. 接入 / 移除 Agent

### 接入

```powershell
.\scripts\add-agent.ps1 -AgentName myagent -RootPath C:\Users\me\.myagent\skills
```

或向导 [4] → **a**。脚本会：备份已有内容 → 迁移进共享库 → 建 Junction → 验证。

### 移除

```powershell
.\scripts\remove-agent.ps1 -AgentName myagent -RootPath C:\Users\me\.myagent\skills
```

或向导 [4] → **b**。移除只拆联接，数据保留在共享库，不删除。

> 移除后该 Agent 技能目录变为空目录（此前是联接指针）。

## 5. 扫描已装技能

```powershell
.\scripts\scan-agents.ps1
```

或向导 [5]。对每个已配置 Agent：

- 列出「已在共享库（经联接可见）」的技能；
- 列出「仅存在于该 Agent、未进共享库」的技能；
- 手动安装在 Agent 目录的技能可借此发现，再迁移进共享库。

## 6. 验证联接

```powershell
.\scripts\verify.ps1
```

或向导 [2]。逐项检查：配置存在性、目录存在性、是否 Junction、技能可见性、各 Agent 与共享库技能数一致性。

## 7. 升级 / 回滚

升级与回滚细节见 `docs/05-safety-and-rollback.md`；快速回滚：`remove-agent.ps1` 拆联接 + 恢复备份目录。
