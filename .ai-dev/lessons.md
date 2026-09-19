# Lessons — 项目永久教训（反复踩过的坑）

> 长期沉淀"这个项目永远不能这么干"的教训。与 HANDOFF 的"陷阱"区不同：
> HANDOFF 记本次临时坑（易失，随 handoff 压缩），本文件记反复验证、跨阶段仍有效的教训（持久）。
> 保持精简：只留"换个 AI 来做还会再踩"的坑；一条一个事实，写清"为什么不行 + 该怎么做"。
> 当 HANDOFF 陷阱区里某个坑重复出现第二次，就把它提升到这里。

## 架构与边界

| 教训 | 为什么不行 | 正确做法 |
|---|---|---|
| 勿把 `config\agents.json` 提交入库 | 含真实用户路径/ID，且是私有本机配置 | 仓库只维护 agents.example.json；.gitignore 排除 agents.json |
| 勿静默覆盖同名冲突技能 | 两技能内容可能不同，覆盖即丢数据 | 保留原处并提示人工决策，处理后再重跑 |
| 勿触碰各 Agent 平台内置技能根 | 系统技能目录与共享库无关，误接入会造成混乱 | 只接用户级技能根；内置根列入"不动清单"（如豆包 `.skills`） |

## 工具链与环境

| 教训 | 为什么不行 | 正确做法 |
|---|---|---|
| 无 BOM 的 .ps1 在 PowerShell 5.1 中文乱码 | PS5.1 默认按 ANSI/GBK 解析 | 所有 .ps1 保存为 UTF-8 带 BOM |
| bash 内联执行含 `$var` 的 PowerShell 代码会被转义破坏 | `$var` 被外层 shell 展开 | 一律写 .ps1 脚本文件再执行 |
| git 的 stderr 输出被 PowerShell 当错误显示 | NativeCommandError 是显示层误报 | 以退出码/实际结果判断，clone 成功即成功 |
| 提交信息含中文经 GBK 控制台乱码 | ConvertTo-Json/控制台编码 | git 提交信息用 ASCII 英文 |
| setup-wizard.ps1 内容超 Read 25000 token 单行限额 | 单行 payload 过大 | 大文件走 git clone→覆盖→commit→push 通道 |

## 数据与外部系统

| 教训 | 为什么不行 | 正确做法 |
|---|---|---|
| 共享库技能无远程基准时检测不了更新 | install-skill 才有 branch+commitSha 记录 | 手工迁移的技能显示本地版本，注明"无远程基准" |
| 探测"已安装"只看技能根子目录会漏判 | 部分软件（CodeBuddy/Marvis）装了但 skills 子目录未建 | 用父目录探测（ProbePath），提示"已安装·技能根待创建" |
| 同一软件多技能根都接共享库 → 每技能加载多份 | 豆包同时读 .user_skills/Doubao\skills/.agents\skills | duplicate-guard 同源组检测；每软件只保留一个技能根接入 |
