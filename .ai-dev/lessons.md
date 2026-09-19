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
| 本机 `git fetch/push` 不落盘 `refs/remotes/origin/*` | 引用目录写不进；`status` 长期显示 `[ahead 1]`，手打 SHA 补引用会显示 `[gone]`，全是假象 | 一律以 `git ls-remote origin refs/heads/main` 为权威；要修本地显示就手写 `.git/packed-refs`，**SHA 必须复制命令输出的完整 40 位**并 `git cat-file -e` 校验 |
| AI 执行环境（PowerShell 工具）起不了子进程、禁 `Add-Type`/反射、回传输出被吞 | `cmd /c`、`powershell -File`、`Add-Type` 均不可用或静默失败 | 抓脚本输出用同会话重定向 `& .\scripts\x.ps1 *> out.txt`（UTF-16LE，读前 `iconv -f UTF-16LE -t UTF-8`）；删到回收站用 python ctypes `SHFileOperationW`；访问网络用 python urllib 或 git |
| `Write-Host "..." -f $a,$b -ForegroundColor X` 直接崩 | `-f` 被按**无歧义参数缩写**解析为 `-ForegroundColor`，`$a` 被当颜色名 → `ParameterBindingException`，且脚本"打完上一条进度就无声消失" | 格式化串**必须加括号**：`Write-Host ("..." -f $a,$b) -ForegroundColor X` |
| PS 函数返回数组用 `return ,$arr` + 调用方 `@()` | 会得到嵌套数组，`$x[0].Length` 变成元素个数，取到错数据（如分块失效） | 函数正常 `return $arr`（管道自动展开），调用方用 `@()` 收集即可 |
| 进度输出用 `` `r `` 覆盖同一行 | 重定向到文件时 `` `r `` 不换行，整段日志挤成一行，`grep`/`tail` 全部失效 | 非交互或可能被重定向的脚本一律逐行输出，不要 `` `r `` |

## 数据与外部系统

| 教训 | 为什么不行 | 正确做法 |
|---|---|---|
| 共享库技能无远程基准时检测不了更新 | install-skill 才有 branch+commitSha 记录 | 手工迁移的技能显示本地版本，注明"无远程基准" |
| 探测"已安装"只看技能根子目录会漏判 | 部分软件（CodeBuddy/Marvis）装了但 skills 子目录未建 | 用父目录探测（ProbePath），提示"已安装·技能根待创建" |
| 同一软件多技能根都接共享库 → 每技能加载多份 | 豆包同时读 .user_skills/Doubao\skills/.agents\skills | duplicate-guard 同源组检测；每软件只保留一个技能根接入 |
