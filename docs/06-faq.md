# 06 · 常见问题（FAQ）

## Q1：为什么不用符号链接（mklink /D）？

符号链接创建需要管理员权限（或开启 Windows 开发者模式），而 **Junction 完全免提权**，效果相同（读写穿透、即时同步）。对普通用户而言 Junction 是零门槛选择。

## Q2：Junction 需要管理员权限吗？

不需要。`mklink /J` 普通权限即可创建。这也是本方案选它的核心原因之一。

## Q2.1：首次运行脚本报"禁止运行脚本"怎么办？

Windows PowerShell 默认执行策略是 `Restricted`，会拒绝运行任何 `.ps1` 脚本。放行（只影响当前用户）：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

输入 `Y` 确认后重试即可。`RemoteSigned` 表示只允许运行**本地创建**的脚本和**带有效数字签名**的远程脚本，是微软官方推荐的本地脚本放行方式，不会降低系统整体安全级别。脚本本身无需管理员权限。

## Q3：我改了共享库，为什么 Agent 没反应？

大多数 Agent 在**会话启动时**扫描技能目录。改动后请**重启会话**（Doubao 新开对话、Claude Code 重启会话、Cursor 重载窗口）。

## Q4：在一个 Agent 里修改技能，其他 Agent 会看到吗？

会。数据只有一份，所有联接都指向它。这是本方案的**特性**，也是主要风险点（误删会全局生效），日常按 `docs/05` 的纪律操作。

## Q5：移动了共享库目录，联接坏了怎么办？

Junction 记录目标的绝对路径，移动后联接失效。修复：

```powershell
# 1. 拆除失效联接
cmd /c rmdir "C:\...\旧Agent目录"

# 2. 重建（指向新位置）
cmd /c mklink /J "C:\...\旧Agent目录" "D:\新位置\shared"

# 3. 验证
.\scripts\verify.ps1
```

更省事：把 `config\agents.json` 的 `sharedRoot` 改为新路径，重跑 `setup.ps1`（自动重建所有联接）。

## Q6：杀毒软件/索引器会不会出问题？

Junction 是 NTFS 原生机制，绝大多数扫描器透明跟随，一般无碍。个别杀软可能对"非常规目录结构"有提示，加白名单即可。

## Q7：macOS / Linux 能用这个方案吗？

思路相同，工具不同——用符号链接：

```bash
mkdir -p ~/skills/shared
ln -s ~/skills/shared ~/.claude/skills      # Claude Code
ln -s ~/skills/shared ~/.agents/skills      # Codex / Cursor
```

## Q8：技能里的斜杠命令 / 插件配置能跨平台用吗？

**不能**。Claude Code 的 `/grill-me` 斜杠命令、OpenClaw 的专属配置、平台绑定的 MCP 都只在各自平台生效。共享的是**通用 Prompt 型技能**（SKILL.md + 资源文件）。跨平台不兼容的内容建议用平台专属目录单独放。

## Q9：装了一堆技能，想只让某个 Agent 少装几个怎么办？

共享模型是"全量共享"。需要差异化时：

- 方案 A：把"全量技能"放共享库，个别 Agent 的**专属技能**放它的原目录（Junction 之外再放目录 → 注意：Junction 目标已接管该目录，无法再直接放文件！）。
- 因此实际做法是：**共享库放通用技能；专属技能放该 Agent 单独的一个非共享根**（如项目级 `.claude\skills` 等 Agent 还支持的二级目录）。

> ⚠️ 注意：Junction 占用了整个技能根目录，该目录下无法再"额外"放别的子目录（所有子目录都在共享库里）。差异化管理请用 Agent 的项目级目录或其他技能根。

## Q10：可以用 git 管理共享库吗？

推荐。共享库内 `git init`，每次技能变更后 commit，等于全量技能的历史版本与误删保险。

## Q11：脚本 -WhatIf 是什么？

PowerShell 试运行模式：只打印"将要做什么"，不真正执行。搭建前先跑一次最稳妥。

## Q12：配置文件写错路径会怎样？

脚本对不存在的路径会跳过并报告（不会硬建）。`verify.ps1` 也会标 `[FAIL]` 提醒。修正配置重跑即可。

## Q13：这个方案会影响 Doubao 内置的系统技能吗？

不会。脚本只处理你写进 `agents.json` 的路径。Doubao 的系统技能在 `.skills` 目录，**不在**默认配置内，也不会被迁移或改动。

## Q14：我各 Agent 已装了很多技能，迁移时会丢吗？会删吗？

不会丢。迁移 = 把技能**移动**进共享库（数据还在，只是换了位置），原 Agent 目录随后变成指向共享库的**联接（门）**——通过原路径依然能访问同一份数据。回滚流程见 `docs/05`。

## Q15：两个 Agent 有同名技能，会重复还是冲突？

自动处理，分三种情况：

| 情况 | 脚本行为 |
| --- | --- |
| 同名且**内容一致**（同一版本） | **自动去重**：删除冗余副本，共享库保留一份 |
| 同名且**内容不同**（版本不同） | **冲突**：两边都保留，不覆盖；提示你人工决定保留哪份，处理后再跑 |
| 共享库没有同名 | 正常迁移 |

"内容一致"按整个目录的文件相对路径 + 文件哈希比对（SHA-256），不是只比名字。

## Q16：能从 GitHub 仓库链接一键安装技能吗？

可以。

```powershell
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/skill-repo"
```

自动下载（zip，无需 git）、识别技能结构（根目录或子目录含 `SKILL.md`）、安装进共享库；
同名冲突默认跳过，`-Replace` 强制替换。也可以在交互控制台 `setup-wizard.ps1` → [3] 技能管理 → [b] 里输入链接安装。

## Q16.1：能安装 skills.sh 上的技能吗？

可以。skills.sh 是 Vercel 的技能市场，底层仍是 GitHub 仓库，直接贴它的链接即可：

```powershell
# 整包安装
.\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/owner/repo"

# 只装其中的某个技能
.\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/owner/repo/skill-name"
```

## Q16.2：技能管理列表里能看到技能的中文简介吗？

可以。`setup-wizard.ps1` → [3] 技能管理 → [a] 列出，每行显示「技能名（SKILL.md 数）＋ 简介」，
并按**自动分类**分组（[3]d 可按分类浏览）。通过 `install-skill.ps1` 安装的技能会自动生成 `_meta.json`（含自动翻译的中文简介）；
手动复制的技能则直接读取 SKILL.md 中的 description 显示。

## Q16.3：技能是怎么自动分类的？

分类规则（在 `setup-wizard.ps1` 顶部可改）：

1. **优先**读 SKILL.md frontmatter 的 `category` / `type` / `tags` 字段（命中分类名或关键词即采用）；
2. 否则按「技能名 + 简介」匹配内置关键词词典，归入：开发与工程、写作与内容、研究与搜索、
   办公与效率、数据分析、设计与创意、音视频与媒体、Agent 与技能管理、生活与日常；
3. 都匹配不到归入「未分类」，排在最后。

想固定某个技能的分类，在它的 SKILL.md frontmatter 里加一行即可，如 `category: 办公与效率`。

## Q17：仓库里的技能安装后怎么更新？

**先检测有没有新版本，再升级：**

```powershell
# 检测：对比 _meta.json 记录的 commitSha 与 GitHub 仓库最新提交
.\scripts\check-updates.ps1
# 自动升级所有有更新的仓库
.\scripts\check-updates.ps1 -Update
```

或在向导主菜单选 [6]。手动升级也可以重新运行安装命令，同名会被跳过；
要覆盖旧版本加 `-Replace`：

```powershell
.\scripts\install-skill.ps1 -RepoUrl "https://github.com/owner/skill-repo" -Replace
```

或手动替换共享库中的技能目录（见 `docs/04` 第 3 节）。

> 说明：只有**从仓库链接安装**的技能能检测（安装时记录 `branch` + `commitSha` 作为版本基准）；
> 迁移/手放的技能无远程依据，仅显示本地版本号。GitHub API 匿名限速 60 次/小时，
> 多仓库时可用 `-Token <token>` 或环境变量 `GITHUB_TOKEN` 提高配额。

## Q18：安装的技能需要 npm install / pip install 之类依赖怎么办？

`install-skill.ps1` 会检测仓库根目录的依赖清单（`package.json` / `requirements.txt` / `pyproject.toml` / `Gemfile`）并提示。依赖是技能自身的运行环境问题，与共享无关：在技能目录（共享库内）按需安装一次，各 Agent 通过联接即共享该环境（运行环境类依赖建议放到共享库外的全局路径，避免各平台隔离差异）。

## Q19：我在 Agent 里手动安装的技能，会进共享库吗？怎么检测？

**不会自动进**。在 Agent 内手动安装（如 Claude Code `/install`、Codex `add`）会装到该 Agent 自己的技能目录，与共享库是两个独立位置。

随时检测：

```powershell
.\scripts\scan-agents.ps1
# 或向导主菜单 [5] 扫描各 Agent 已安装技能
```

脚本会标注每个 Agent 目录里各技能的状态：已接入共享库 / 已共享（内容一致）/ 冲突（同名不同内容）/ 独有（共享库没有）。发现"独有"技能后，按输出提示迁移进共享库即可（详见 `docs/04` 第 8 节）。

> 小技巧：Agent 目录一旦接入共享库（Junction），之后在该 Agent 里手动安装的技能会**直接落在共享库**，天然共享，无需再迁移。
