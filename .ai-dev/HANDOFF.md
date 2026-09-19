# HANDOFF — 活跃工作交接

> 本文件是跨工具 / 跨模型切换时的“工作记忆”。新会话只读本文件 + START_HERE.md 就应能恢复现场。
> 写作要求：**结构化、可执行、只写恢复现场必需的信息**；不贴对话原文、大段代码和日志。
> 每次收工前由当前 AI 更新顶部元信息与各小节；归档线以下由脚本自动搬走，不要手删。

## 元信息

- 最近更新：2026-09-20
- 更新于工具 / 模型：WorkBuddy AI（jacksen · DeepSeek-V4.1）
- 工作分支：main（本地工作副本与 origin/main 同步；最近已推送 `3653de9`，本轮提交为其后继）
- 进行中的 spec（如用 speckit / Spec Kit）：无（本项目未启用 speckit，无 specs/ 目录）

## 当前任务

- 目标（本轮）：在「技能管理」里新增**技能介绍翻译**功能——把英文技能简介译成中文写入 `_meta.json`（向导入口 `[3]f`）。
- 背景：用户直接提出。功能已实现并真机跑通：全库 144 个技能中 131 个已有中文简介；余 12 个因免费接口限流暂缺，可随时重跑补齐。

## 进度状态

- 已完成（本轮，全部真实执行）：
  - 新增 `scripts/translate-skill-intro.ps1`（210 行）：扫描共享库 → 取英文简介（SKILL.md frontmatter 优先，回退 `_meta.json`）→ 译中文 → **合并**写回 `_meta.json`；支持 `-WhatIf` 预演 / `-Name` 单个 / `-Force` 重译 / `-Email` 提配额 / 连续失败熔断
  - 新增 `scripts/lib/translate.ps1`（157 行）：`ConvertTo-DescriptionZh`（MyMemory → Google 兜底，按句切块规避 500 字符上限）、`Read-SkillFrontmatter`（支持跨行 / 折叠块）、`Test-HasCjk`
  - `install-skill.ps1` 改为复用该库（删掉本地重复实现，272→235 行）
  - 向导接线：`[3]` 子菜单新增 `[f] 技能介绍翻译` + 分发；帮助页与主菜单描述同步（1115→1127 行）
  - 真机结果：`-WhatIf` 预演 48 个待翻（与实测一致）；**已翻译写入 35 个**，累计 131 个技能有中文简介
  - 翻译后重跑路由：`router-guide\SKILL.md` 143 条中 **122 条带中文简介**（此前约 87 条），未分类 36 → 30
  - 复验：14 个 `.ps1` Parser 0 错误、UTF-8 BOM 全在；code-index 已同步（22 文件 / 约 4656 行）
- 进行中：
  - 12 个技能待补翻（`seagull-*` ×6、`xlsx`、`web-deploy-github`、`web-design-guidelines`、`windows-kernel-security`、`test-driven-development`、`writing-plans`）——MyMemory 返回 **HTTP 429**（本机唯一可达的翻译接口，匿名按 IP 限每日额度），已交由定时任务自动补齐，非代码问题

## 下一步动作（checkbox，完成即勾选，不要重写整段）

- [x] 实现 `translate-skill-intro.ps1` + `lib/translate.ps1` + 向导 `[3]f` + 文档/索引同步
- [x] 真机跑通翻译并重新生成路由索引（中文覆盖 122/143）
- [x] **安装路径真机验证完成**：`install-skill.ps1 -RepoUrl https://github.com/hgta23/findskills -SharedRoot <scratch>` 全链路通过（下载 → 识别 1 个技能 → 写 `_meta.json`），`source` / `branch` / `commitSha` / `installedAt` 字段齐全；`description` 经公共库 `Read-SkillFrontmatter` 解析、`descriptionZh` 经公共库 `ConvertTo-DescriptionZh` 写入 → 删本地实现改 dot-source 后**无回归**（证据：`.workbuddy-ai\tmp\install-test-meta.json`，测试用 scratch 库已清理）
- [x] **剩余 12 个技能的翻译改为自动补齐**：定时任务 `5b8eebb2-9544-42ab-9d23-c0e2aa9e236c`（每天 03:00 重跑，2026-09-24 自动过期）；脚本幂等，已翻译的自动跳过
- [ ] 可选加速：若要立刻补完，设环境变量 `MYMEMORY_EMAIL=<邮箱>` 或加 `-Email <邮箱>`（MyMemory 的 `de=` 参数可把匿名额度提高一个数量级；**本次未擅自提交用户邮箱**）
- [ ] 待用户确认（前一环节遗留）：重启豆包 / Trae 会话，确认归并重复技能根后技能列表未变空

## 本次形成的关键约束 / 决策（新会话必须遵守）

- **翻译与 frontmatter 解析只放 `scripts/lib/translate.ps1`**，`install-skill.ps1` 与新脚本都 dot-source；不要再复制第二份实现（本次已合并）。
- **`_meta.json` 必须合并写回**：翻译只增改 `description` / `descriptionZh` / `translatedAt`；`source` / `branch` / `commitSha` 是 `check-updates.ps1` 的版本基准，绝不能丢。
- `generate-router-skill.ps1` **不设任何排除名单**（全量收录）；重复技能根一律**保留 `~\.agents\skills`**（跨 Agent 共享入口）。
- `VERSION` 已 bump 到 `1.1.0`；判定逻辑是 `-eq` 比较，**不相等即报 `[有更新]`**。
- 推送凭据本机可用（Windows 凭据管理器持有 github.com 凭据），无需 `gh auth login` / `GH_TOKEN`。
- `.ai-dev/` 已随仓库公开推送（commit b2c2f13），写入前先想“协作者会看到”；项目事实源在 `.ai-dev/`，AGENTS.md 只作薄指针。
- 仓库局部 `core.autocrlf=false`，保护 conventions「推送后逐文件字节比对」验收。

## 陷阱：试过且走不通的路（避免重复浪费）

> 环境级长期坑已提炼到 `lessons.md`「工具链与环境」，这里只留本轮新坑。

- **`Write-Host "..." -f $a,$b -ForegroundColor X` 会静默崩脚本**：`-f` 被 PowerShell 按**无歧义参数缩写**解析成 `-ForegroundColor`，于是把 `$a` 当颜色名 → `ParameterBindingException`（已实测确认）。格式化串**必须加括号**：`Write-Host ("..." -f $a,$b) -ForegroundColor X`。本次脚本"打印进度后无声死掉"就是这个。
- **PS 函数返回数组别用 `return ,$arr`**：调用方再套 `@()` 会得到嵌套数组（`$x[0].Length` 变成元素个数），本次导致分块翻译失效、把 992 字符整段发给接口。
- **MyMemory 把错误信息塞在 `translatedText` 里正常返回**（`QUERY LENGTH LIMIT EXCEEDED` / `MYMEMORY WARNING` / `NO QUERY SPECIFIED`）→ 必须逐条识别为失败，否则会被当成译文；超限时 HTTP 状态码是 **429**。
- **本机出网只放通少数域名**（沙箱代理）：翻译接口里**只有 `api.mymemory.translated.net` 通**——`translate.googleapis.com` 与 `clients5.google.com` 报 `Tunnel connection failed: 502`、`edge.microsoft.com/translate/auth` 404、`libretranslate.de` 403、`lt.vern.cc` 502。**别指望 Google 兜底**；MyMemory 一旦 429，本环境当次翻译链路就是不可用，只能等次日额度重置。
- `Write-Progress`（`Expand-Archive`、下载进度条）**不会被 `*>` 重定向捕获**，会直接刷屏且无法落盘；判断这类命令的结果要看它自己写的文件。
- **进度行不要用 `` `r `` 覆盖**：输出重定向到文件时 `` `r `` 不换行，整段日志挤成一行，`grep`/`tail` 全失效（排查时白绕一圈）。要抓日志就用普通换行。

## 本次改动文件清单

| 文件 | 改动 | 原因 |
|---|---|---|
| `scripts/translate-skill-intro.ps1` | **新增**（210 行） | 技能介绍翻译主脚本（向导 [3]f） |
| `scripts/lib/translate.ps1` | **新增**（157 行） | 翻译 + frontmatter 解析公共库 |
| `scripts/install-skill.ps1` | 删除本地重复实现，改 dot-source lib（272→235 行） | 消除两份实现漂移 |
| `scripts/setup-wizard.ps1` | `[3]f` 菜单 + 分发 + 帮助页（1115→1127 行） | 功能入口 |
| `README.md`、`docs/01-architecture.md`、`docs/03-setup-guide.md` | 补新脚本与新菜单项说明 | 文档与代码一致 |
| `.ai-dev/code-index.md` | 22 文件 / 约 4656 行 | 新增源码文件 |
| `.ai-dev/lessons.md` | 追加环境级长期坑 | HANDOFF 陷阱区超载，按 START_HERE §2 提升 |
| 本机共享库（非仓库内容） | 131 个技能的 `_meta.json` 写入 `descriptionZh`；`router-guide\SKILL.md` 重生成 | 功能介绍的落点 |
| 本机 scratch 共享库（非仓库内容） | 跑通 `install-skill.ps1` 验证后已清理，证据留 `.workbuddy-ai\tmp\install-test-meta.json` | 验证改 dot-source 无回归 |
| 定时任务 `5b8eebb2-…`（非仓库内容） | 每天 03:00 重跑翻译，补完剩余 12 个技能 | 外部配额受限，改为自动补齐 |

---

<!-- ARCHIVE-LINE: 本行以下为历史完成记录，超限时由 archive_handoff.py 自动归档到 archive/，不要手动删除 -->

## 历史完成记录

<!-- 已闭环的事项简要留痕；新内容写在本节最上方 -->

- 2026-09-20 WorkBuddy AI（第三轮）：新增「技能介绍翻译」——`translate-skill-intro.ps1` + `lib/translate.ps1` + 向导 `[3]f`；`install-skill.ps1` 改为复用公共库；真机翻译 35 个技能、路由索引中文覆盖 122/143。
- 2026-09-20 WorkBuddy AI（第二轮）：移除 skill-router 的受限排除（全量收录，技能总数 131→143）；归并重复技能根（保留 `~\.agents\skills`，清空 2 个重复根）；`VERSION` bump 到 1.1.0。
- 2026-09-20 WorkBuddy AI（第一轮）：接手——本地目录由 ZIP 镜像重建为 git 工作副本并对齐 `origin/main`；逐文件 sha256 比对修正 2 份过期 `.ai-dev` 文档；13 个 `.ps1` 语法/BOM 复验 0 错误；移出 rule-sync 工具、回收旧向导备份；**真机验证** `verify.ps1` 全绿。
- 2026-09-19 豆包（MainAgent）：接入 devctx 统一上下文——init 生成 `.ai-dev/` 全套 + 根 `AGENTS.md` 薄指针，L2 文档据实填写，`doctor.py --fix` 11 项全绿。已随 commit b2c2f13 推送。
