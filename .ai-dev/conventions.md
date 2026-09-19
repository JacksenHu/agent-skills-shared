# Conventions — 开发约定（所有工具统一遵守）

> 本文件是跨 IDE / 跨模型的**统一行为规范**。任何工具生成的代码都必须满足这里的硬性约定；
> 与本文件冲突的“模型个人习惯”一律无效。约定要少而硬，只写真正会反复踩的规则，不写语言教科书。

## 代码风格

- 格式化工具与版本：无自动格式化工具；全部脚本为 PowerShell 5.1（Windows 自带），文档为 Markdown。
- 命名：脚本/文档 kebab-case（如 `setup-wizard.ps1`）；PowerShell 函数用 PascalCase（如 `Show-BoxTop`）；参数用 PascalCase（如 `-RepoUrl`）。
- 函数与文件体量：单脚本 ≤ 1500 行；新增逻辑优先放独立脚本，复用逻辑进 `scripts/lib/` 由 dot-source 加载。

## 工程结构约束

- 分层依赖方向：交互控制台（setup-wizard.ps1）→ 功能脚本（setup/add-agent/install-skill/…）→ 公共库（scripts/lib/）；禁止功能脚本反向依赖控制台。
- 公共能力放哪：`scripts/lib/`（目前 duplicate-guard.ps1：同源多根检测）。
- 禁止事项：
  - 禁止直接修改 `%USERPROFILE%\skills\shared` 之外的 Agent 平台内置技能目录（如豆包 `.skills` 系统根）。
  - 禁止静默覆盖冲突技能：冲突必须保留原处并提示人工决策。
  - 禁止把 `config\agents.json`（含真实路径/用户 ID）提交入库。
  - 禁止用 bash 内联执行含 `$var` 的 PowerShell 代码（转义破坏），一律写 .ps1 文件再执行。

## 错误处理与日志

- 错误处理：用户可恢复的错误（冲突、缺目录、无效输入）用警告/提示并继续；致命错误（无法写共享库）显式报错并停止。
- 日志：交互控制台用 VT 真彩色（preset 内语义色：primary/accent/ok/warn/err/text/dim/faint/border/gold/white）；非交互脚本用 `[OK]/[WARN]/[ERR]` 前缀。禁止打印 Token / 路径中的用户 ID 等敏感信息。

## 测试要求

- 该脚本项目无自动化测试框架；每次改动后必须：① PowerShell Parser 语法校验（0 错误）；② 真机执行关键路径（如 `verify.ps1` 全绿、`generate-router-skill.ps1` 正常生成）；③ 推送 GitHub 后逐文件内容比对一致。
- 覆盖率底线：不适用；以“推送后 verify 通过 + 内容一致”为验收。

## 分支与提交

- 分支命名：main（单分支维护，无需 feature 分支）。
- 提交信息（Conventional Commits，**必须 ASCII**，中文会经 GBK 控制台乱码）：
  ```text
  feat: add skill-router generator (generate-router-skill.ps1) + wizard [3]e + docs/README sync
  fix(wizard): parent-dir probe for CodeBuddy/WorkBuddy (installed-but-no-skill-root) + docs note
  docs: update preset agent list 23->24 with international editions
  ```
- 提交粒度：一次提交只做一件事，禁止混合无关改动。

## AI 协作特别约定（重要）

- 改动前先在 `code-index.md` 定位，改动后若增删/移动文件，必须重建索引。
- 难以逆转的决定先写 `decisions/` ADR，再动手。
- 不擅自升级依赖版本、不引入新依赖，除非任务明确要求或经用户同意。
- 不修改与当前任务无关的文件；发现的既有问题只记录到 HANDOFF「陷阱」或单独提出。
- 每次收工更新 HANDOFF.md，保证下一个工具能无缝接续。
- 安全红线：本项目会列举各 Agent 技能目录，但不得输出/上传用户的真实 agents.json、Token、open_id、用户 ID；文档示例一律用 `%USERPROFILE%` 占位。
