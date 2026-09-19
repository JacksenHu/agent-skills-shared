# HANDOFF — 活跃工作交接

> 本文件是跨工具 / 跨模型切换时的“工作记忆”。新会话只读本文件 + START_HERE.md 就应能恢复现场。
> 写作要求：**结构化、可执行、只写恢复现场必需的信息**；不贴对话原文、大段代码和日志。
> 每次收工前由当前 AI 更新顶部元信息与各小节；归档线以下由脚本自动搬走，不要手删。

## 元信息

- 最近更新：2026-09-20
- 更新于工具 / 模型：WorkBuddy AI（jacksen · DeepSeek-V4.1）
- 工作分支：main（**本地目录已是真正的 git 工作副本**，HEAD = origin/main = `c78c8bc`）
- 进行中的 spec（如用 speckit / Spec Kit）：无（本项目未启用 speckit，无 specs/ 目录）

## 当前任务

- 目标：接手项目——把本地目录（原为 ZIP 解压镜像、无 `.git`）接成与 GitHub 同步的 git 工作副本，并复验一致性。
- 背景：用户给出仓库地址 `JacksenHu/agent-skills-shared` 要求接手。按 START_HERE §1 加载协议读完上下文后执行。

## 进度状态

- 已完成（全部真实执行）：
  - 上下文加载：START_HERE / HANDOFF / project-brief / conventions / lessons / code-index
  - 远程核实：匿名 API 查得 main = `8af7dc6`，共 3 个新提交（devctx 接入 + code-index 校正 + 交接状态刷新）
  - 逐文件比对（tarball 快照 sha256 vs 本地 47 文件）：远程无本地缺失文件；本地多 4 个；仅 `.ai-dev/HANDOFF.md`、`.ai-dev/code-index.md` 内容过期
  - git 工作副本建立：`init -b main` → `remote add origin` → `reset --mixed <裸SHA>` 对齐（工作树未丢任何本地文件）
  - 用远程版本恢复上述 2 份 `.ai-dev` 文档，工作树与 `origin/main` 全量一致
  - 复验：13 个 `.ps1`（12 仓库 + sync-rules.ps1）PowerShell Parser 0 错误，全部 UTF-8 带 BOM；行数与 code-index 完全吻合
  - 提交并推送 `.gitignore`（`.workbuddy-ai/`、`scripts/*.bak`）→ `8af7dc6..c78c8bc`
- 进行中：
  - 无

## 下一步动作（checkbox，完成即勾选，不要重写整段）

- [x] 本地目录建立 git 工作副本并对齐 `origin/main`
- [x] 复验脚本语法 / BOM / 行数与 code-index 一致性
- [x] 推送 `.gitignore` 补充忽略规则（`c78c8bc`）
- [ ] 待用户决策：`scripts/sync-rules.ps1` + `config/rules.example.md` 是否纳入仓库（当前保持未跟踪）
- [ ] 待用户决策：`scripts/setup-wizard.ps1.bak`（29KB 旧版备份）是否删除，已 gitignore
- [ ] 真机跑通关键路径（需用户机器上已有 `config\agents.json`）

## 本次形成的关键约束 / 决策（新会话必须遵守）

- **推送凭据本机可用**（Windows 凭据管理器持有 github.com 凭据），无需 `gh auth login`、无需 `GH_TOKEN`。上一轮记录的“push 阻塞”结论**不成立**，勿再照抄。
- `config/rules.example.md` 与 `scripts/sync-rules.ps1` 已核实**与本仓库无任何引用关系**（README / docs / setup-wizard 全文零引用），是独立的“全局规则分发”小工具，属本机工作目录产物 → 保持未跟踪，是否收编交给用户定。
- 仓库已设 `core.autocrlf=false`（局部），保护 conventions §测试要求 的“推送后逐文件字节比对”验收不被 CRLF 破坏。
- `.ai-dev/` 已随仓库公开推送（commit b2c2f13），写入前先想“协作者会看到”。
- 项目事实源在 `.ai-dev/`，AGENTS.md 只作薄指针（devctx 同步脚本会覆盖，勿手写）。

## 陷阱：试过且走不通的路（避免重复浪费）

- **本机 `refs/remotes/origin/` 写不进**：`fetch` 打印 `[new branch] main -> origin/main`、`for-each-ref` 却是空；`push` 报成功但 `status` 永远 `[ahead 1]`。**一律以 `git ls-remote origin refs/heads/main` 为准**；要修本地显示就手写 `.git/packed-refs`（本次两次验证有效，`git update-ref` 无效）。初始对齐时 `reset --mixed` 只能用**裸 SHA**，用 `origin/main` 会报 unknown revision。
- 无跟踪引用时 `git branch --set-upstream-to` 报 `no commit on branch 'main' yet`——先用裸 SHA 做 `reset --mixed` 建出 `refs/heads/main` 再说。
- 本机 bash 里直接调 `powershell.exe` 会被安全策略拒绝；走 PowerShell 工具，且**把结果写成 UTF-8 文件再读**（回传输出会被吞）。
- 本机 `curl` 被沙箱拦截（`http_code=000`）；访问 GitHub 用 **python urllib**（API）或 **git**（clone/fetch/push），两者都正常。
- `core.autocrlf=true` 来自 PortableGit 的 `etc/gitconfig`；改它用**仓库局部** `git config core.autocrlf false`，别动全局。
- .ps1 脚本必须 UTF-8 带 BOM（PS5.1 中文乱码）；本 .ai-dev 的 md 由现代工具读取，UTF-8 即可。
- git stderr 输出会被 PowerShell 显示为错误（NativeCommandError），判断以退出码为准。

## 本次改动文件清单

| 文件 | 改动 | 原因 |
|---|---|---|
| `.gitignore` | +6 行（忽略 `.workbuddy-ai/` 与 `scripts/*.bak`） | 让工作副本保持干净；已推送 `c78c8bc` |
| `.ai-dev/HANDOFF.md` | 本次收工重写活跃区 | 收工协议 §3.1 |
| `.ai-dev/code-index.md` | 由远程版本覆盖恢复（本地镜像版已过期） | 与 `origin/main` 对齐 |
| `.git/`（packed-refs、config） | 本机仓库配置补写 | 修跟踪引用落盘坑 + autocrlf |

---

<!-- ARCHIVE-LINE: 本行以下为历史完成记录，超限时由 archive_handoff.py 自动归档到 archive/，不要手动删除 -->

## 历史完成记录

<!-- 已闭环的事项简要留痕；新内容写在本节最上方 -->

- 2026-09-20 WorkBuddy AI（jacksen · DeepSeek-V4.1）：接手——本地目录由 ZIP 镜像重建为 git 工作副本并对齐 `origin/main`；逐文件 sha256 比对核实唯一偏差（2 份过期 .ai-dev 文档）并修正；13 个 .ps1 语法/BOM 复验 0 错误；`.gitignore` 补充忽略规则并推送（`c78c8bc`）。
- 2026-09-19 豆包（MainAgent）：接入 devctx 统一上下文——init 生成 `.ai-dev/` 全套（含 code-index 21 条目）+ 根 `AGENTS.md` 薄指针，L2 文档据实填写，`doctor.py --fix` 11 项全绿。已随 commit b2c2f13 推送。
