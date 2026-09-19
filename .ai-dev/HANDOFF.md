# HANDOFF — 活跃工作交接

> 本文件是跨工具 / 跨模型切换时的“工作记忆”。新会话只读本文件 + START_HERE.md 就应能恢复现场。
> 写作要求：**结构化、可执行、只写恢复现场必需的信息**；不贴对话原文、大段代码和日志。
> 每次收工前由当前 AI 更新顶部元信息与各小节；归档线以下由脚本自动搬走，不要手删。

## 元信息

- 最近更新：2026-09-19
- 更新于工具 / 模型：豆包（MainAgent）
- 工作分支：main（本地目录非 git 仓库，GitHub 远程为 JacksenHu/agent-skills-shared）
- 进行中的 spec（如用 speckit / Spec Kit）：无（本项目未启用 speckit，无 specs/ 目录）

## 当前任务

- 目标：为 agent-skills-shared 项目接入 devctx 统一上下文（.ai-dev/），已完成 init 全链 + L2 实质内容起草。
- 背景：用户要求“统一上下文[Devctx]”并选择给当前项目实际接入；init_project.py 已生成 .ai-dev/ 全套与 AGENTS.md 薄指针，本 HANDOFF 初始化即收尾。

## 进度状态

- 已完成：
  - devctx init：.ai-dev/ 全套模板 + code-index.md（21 源文件）+ AGENTS.md 指针（agents 通用开放标准）
  - L2 实质内容：project-brief.md / architecture.md / conventions.md / glossary.md / lessons.md 已据实填写
  - HANDOFF.md 本次初始化；`doctor.py --fix` 后 11 项检查全绿（0 error / 0 warning）
- 进行中：
  - 无（接入已闭环）

## 下一步动作（checkbox，完成即勾选，不要重写整段）

- [x] 运行 `python scripts\doctor.py <项目根> --fix`，确认无 error（11 项全绿）
- [x] 向用户交付“已接入”，并列出待用户确认的问题（如 .ai-dev 是否随 GitHub 仓库推送）

## 本次形成的关键约束 / 决策（新会话必须遵守）

- 项目事实源在 `.ai-dev/`，AGENTS.md 只作薄指针（devctx 同步脚本会覆盖，勿手写）。
- 项目根 AGENTS.md 由 devctx 生成；工作目录 `new-chat\AGENTS.md` 是另一文件（sync-rules 维护，与项目无关，不遵循其内容）。
- .ai-dev/ 是否推送 GitHub：待用户决定（推送则共享库对协作者可见上下文；不推送则本地私有）。当前未推送。

## 陷阱：试过且走不通的路（避免重复浪费）

- 本地项目目录不是 git 仓库（ZIP 解压镜像），devctx init 会 fallback 到显式目录——属预期行为，不是错误。
- .ps1 脚本必须 UTF-8 带 BOM（PS5.1 中文乱码）；本 .ai-dev 的 md 由现代工具读取，UTF-8 即可。
- git stderr 输出会被 PowerShell 显示为错误（NativeCommandError），判断以退出码为准。

## 本次改动文件清单

| 文件 | 改动 | 原因 |
|---|---|---|
| `.ai-dev/START_HERE.md` | init 生成 | devctx 入口 |
| `.ai-dev/HANDOFF.md` | init 生成 + 本次初始化 | 工作记忆 |
| `.ai-dev/project-brief.md` | init 生成 + 据实填写 | L2 长期记忆 |
| `.ai-dev/architecture.md` | init 生成 + 据实填写 | L2 长期记忆 |
| `.ai-dev/conventions.md` | init 生成 + 据实填写 | L2 统一规范 |
| `.ai-dev/glossary.md` | init 生成 + 据实填写 | L2 术语表 |
| `.ai-dev/lessons.md` | init 生成（空） | 规范要求初始可空 |
| `.ai-dev/code-index.md` | init 自动生成（21 源文件） | 代码地图 |
| `.ai-dev/ignore.conf` | init 生成 | 索引忽略规则 |
| `.ai-dev/decisions/0000-template.md` | init 生成 | ADR 模板 |
| `AGENTS.md` | init 写入薄指针 | 各工具自动引导 |

---
<!-- ARCHIVE-LINE: 本行以下为历史完成记录，超限时由 archive_handoff.py 自动归档到 archive/，不要手动删除 -->

## 历史完成记录

<!-- 已闭环的事项简要留痕；新内容写在本节最上方 -->
