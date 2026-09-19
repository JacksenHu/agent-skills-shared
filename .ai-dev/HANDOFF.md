# HANDOFF — 活跃工作交接

> 本文件是跨工具 / 跨模型切换时的“工作记忆”。新会话只读本文件 + START_HERE.md 就应能恢复现场。
> 写作要求：**结构化、可执行、只写恢复现场必需的信息**；不贴对话原文、大段代码和日志。
> 每次收工前由当前 AI 更新顶部元信息与各小节；归档线以下由脚本自动搬走，不要手删。

## 元信息

- 最近更新：2026-09-20
- 更新于工具 / 模型：WorkBuddy AI（jacksen · DeepSeek-V4.1）
- 工作分支：main（本地为 git clone，与 origin/main 同步；远程 JacksenHu/agent-skills-shared）
- 进行中的 spec（如用 speckit / Spec Kit）：无（本项目未启用 speckit，无 specs/ 目录）

## 当前任务

- 目标：接手项目 + 做一轮「文档 ↔ 代码」一致性体检，修正过期/失真的上下文文档。
- 背景：用户要求「接手这个项目」。按 START_HERE §1 加载协议读完上下文后，对新 clone 的工作副本做静态体检（不触碰真实共享库与各 Agent 目录）。

## 进度状态

- 已完成：
  - 接手加载：clone → 读 START_HERE / HANDOFF / project-brief / README / conventions / lessons / code-index
  - 静态体检（真实执行，结果如下）：
    - 语法：12 个 .ps1 全部通过 PowerShell Parser 校验，0 错误
    - 编码：12 个 .ps1 全部 UTF-8 带 BOM（符合教训表）
    - 预设数：setup-wizard.ps1 静态 23 项 + Marvis 动态 = 24；agents.example.json 24 项，与 README「24 个」一致
    - 引用完整性：README/docs 引用的脚本与图解全部存在，无失效引用
  - 修正 3 处文档失真（见下方「本次改动」）
- 进行中：
  - 无（体检已闭环）

## 下一步动作（checkbox，完成即勾选，不要重写整段）

- [x] 静态体检：语法 / BOM / 预设数 / 引用完整性
- [x] 校正 code-index.md（剔除本地幽灵文件、补齐 agents.example.json、刷新行数）
- [x] 修正 HANDOFF 元信息中「本地非 git 仓库」「.ai-dev 未推送」两处过期描述
- [ ] 推送到 GitHub（**阻塞**：本机 gh 未登录、无 GH_TOKEN、无 .git-credentials；待用户提供凭据或自行 push）
- [ ] 真机跑通关键路径（需用户机器上已有 config\agents.json；本副本无该文件，属预期）

## 本次形成的关键约束 / 决策（新会话必须遵守）

- 项目事实源在 `.ai-dev/`，AGENTS.md 只作薄指针（devctx 同步脚本会覆盖，勿手写）。
- **`.ai-dev/` 已随仓库推送**（commit b2c2f13），不再是本地私有；写入前先想「协作者会看到」。
- `code-index.md` 此前混入两个本地非仓库文件（`config/rules.example.md`、`scripts/sync-rules.ps1`，属 devctx 开发工作目录，与本项目无关）——**已剔除**；重建索引时勿再把它们扫进来。
- 本环境无 devctx 技能，索引维护走 START_HERE §3.2「手工增量修改」降级路径。

## 陷阱：试过且走不通的路（避免重复浪费）

- `git` 不在 PowerShell 的 PATH 里（bash 有）；PowerShell 脚本内直接 `& git` 会 CommandNotFound。要拿文件清单用 `git ls-files` 就走 bash，或在 PS 里用完整路径。
- PowerShell 工具的回传输出会被吞（只显示 exit code），且 `*>` 重定向写出的是 UTF-16LE。需要看结果时：先 `*>` 落盘，再用 `iconv -f UTF-16LE -t UTF-8` 读。
- .ps1 脚本必须 UTF-8 带 BOM（PS5.1 中文乱码）；本 .ai-dev 的 md 由现代工具读取，UTF-8 即可。
- git stderr 输出会被 PowerShell 显示为错误（NativeCommandError），判断以退出码为准。
- 本环境 curl 走 schannel，报 `CRYPT_E_NO_REVOCATION_CHECK`；`git clone` 不受影响（全局已设 sslverify=false + schannelcheckrevoke=false）。

## 本次改动文件清单

| 文件 | 改动 | 原因 |
|---|---|---|
| `.ai-dev/code-index.md` | 剔除 2 条幽灵条目（rules.example.md / sync-rules.ps1）、补入 agents.example.json、README 行数 331→343、表头 21 文件/4433 行 → 20 文件/4322 行 | 索引与实际仓库不符（START_HERE §1.5：以代码为准回写文档） |
| `.ai-dev/HANDOFF.md` | 刷新元信息、当前任务、进度、下一步、陷阱；修正「本地非 git 仓库」「.ai-dev 未推送」失真描述 | 收工协议 §3.1 |


---
<!-- ARCHIVE-LINE: 本行以下为历史完成记录，超限时由 archive_handoff.py 自动归档到 archive/，不要手动删除 -->

## 历史完成记录

<!-- 已闭环的事项简要留痕；新内容写在本节最上方 -->

- 2026-09-19 豆包（MainAgent）：接入 devctx 统一上下文——init 生成 `.ai-dev/` 全套（含 code-index 21 条目）+ 根 `AGENTS.md` 薄指针，L2 文档据实填写，`doctor.py --fix` 11 项全绿。已随 commit b2c2f13 推送。
