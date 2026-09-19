# Architecture — 架构说明

> 回答“代码怎么组织、请求怎么流、改需求去哪改”。与 code-index.md 配合：本文件讲设计与原因，索引讲文件位置。

## 架构总览

纯 PowerShell 脚本集，无框架。核心模型：**单一共享技能库**（`%USERPROFILE%\skills\shared`）为唯一数据源，每个 Agent 的用户级技能根目录通过 NTFS Junction（`mklink /J`，无需管理员）指向它，读写穿透实时共享。交互控制台 `setup-wizard.ps1` 是总入口，按菜单调用各功能脚本；`lib\duplicate-guard.ps1` 被多个脚本 dot-source 共用，做「同一 Agent 多技能根 → 重复加载」防护。

```text
setup-wizard.ps1 (交互控制台)
 ├─ [1] 快速搭建  → setup.ps1 逻辑（迁移去重 → 建 Junction → verify）
 ├─ [2] 验证      → verify.ps1
 ├─ [3] 技能管理  → install-skill / generate-router-skill / 内置清单与分类
 ├─ [4] 接入/移除 → add-agent / remove-agent / merge-agent-roots
 ├─ [5] 扫描已装  → scan-agents.ps1
 └─ [6] 检查更新  → check-updates / check-project-updates
共享库 ↔ Agent 技能根：NTFS Junction（mklink /J）
```

## 模块职责与边界

| 模块 / 目录 | 职责 | 不负责什么 | 关键入口文件 |
|---|---|---|---|
| `scripts/setup-wizard.ps1` | 交互控制台：首页菜单、VT 真彩色界面、技能分类清单、路由技能生成入口 | 不直接操作共享库数据（调子脚本） | `setup-wizard.ps1` |
| `scripts/setup.ps1` | 一键搭建：迁移（内容一致自动去重、不同提示冲突）→ 建联接 → 验证 | 不触碰平台内置技能根（如豆包 .skills） | `setup.ps1` |
| `scripts/add-agent.ps1` / `remove-agent.ps1` | 单 Agent 接入（迁移+建联接）/ 移除（拆联接，数据保留） | 冲突时不做删除决策，留人工 | `add-agent.ps1` |
| `scripts/merge-agent-roots.ps1` | 归并同一软件多技能根，消除重复加载 | 不删除共享库数据 | `merge-agent-roots.ps1` |
| `scripts/verify.ps1` | 逐项验证联接、Junction 指向、技能可见数 | — | `verify.ps1` |
| `scripts/install-skill.ps1` | 从 GitHub / skills.sh 链接安装技能，生成 `_meta.json`（中文简介+版本基准） | 无远程依据的技能无法检测更新 | `install-skill.ps1` |
| `scripts/generate-router-skill.ps1` | 扫描共享库生成 `router-guide/SKILL.md`（9 大分类总路由） | 受限类技能（色情/破解/钓鱼/外挂等）不参与推荐 | `generate-router-skill.ps1` |
| `scripts/check-updates.ps1` / `check-project-updates.ps1` | 技能版本更新（对比来源仓库 commit）/ 项目自更（对比 VERSION） | — | 同名文件 |
| `scripts/scan-agents.ps1` | 扫描各 Agent 已装技能，标注 已共享/冲突/独有 | — | `scan-agents.ps1` |
| `scripts/lib/duplicate-guard.ps1` | 同源多根检测（豆包/Codex/Trae/CodeBuddy 等组） | — | dot-source 共用 |
| `config/agents.example.json` | 24 项 Agent 路径预设模板（含国际版） | 真实路径以本机为准 | 模板文件 |
| `docs/` + `diagrams/` | 完整中文文档 + SVG 图解 | — | — |

## 关键数据流 / 主链路

1. **接入链路**：用户在向导选 Agent → 探测其技能根（含父目录探测：软件装了但 skills 未建 → “已安装·技能根待创建”）→ 迁移已有技能（哈希比对去重）→ `mklink /J 技能根 → 共享库` → verify 确认。
2. **使用链路**：任一 Agent 新会话 → 扫描其技能根（=Junction= 共享库）→ 加载全部技能 → 用户触发技能（如 skill-router 按情境推荐）。
3. **更新链路**：install-skill 记录来源 commit → check-updates 对比远程 → -Update 逐个 `install-skill -Replace`。

## “改什么，去哪改”速查

| 需求类型 | 改动位置 | 注意联动 |
|---|---|---|
| 新增 Agent 预设路径 | `setup-wizard.ps1` detectors 数组 + `config/agents.example.json` + `docs/02` + README 预设数 | 若该软件兼容读 `.claude/.agents` 等根，同时更新 `duplicate-guard.ps1` 同源组 |
| 调整技能分类词典 | `setup-wizard.ps1` 与 `generate-router-skill.ps1` 的 `$script:CategoryDefs`（两处保持一致） | 重新生成 router-guide |
| 新增向导菜单项 | `setup-wizard.ps1` 主菜单 switch + 对应函数 | README 菜单表同步 |
| 改同源多根检测 | `scripts/lib/duplicate-guard.ps1` SameSourceGroups | docs/02 的读取关系说明 |
| 增加/排除路由技能 | `generate-router-skill.ps1` 排除名单 | 重新生成 |

## 跨模块约定

- 所有脚本 **UTF-8 带 BOM**（PowerShell 5.1 中文不乱码）；提交信息用 ASCII（防 GBK 控制台乱码）。
- 共享库是唯一数据源：脚本只允许“迁移进共享库”，不得反向复制；冲突一律保留原处并报告，不自动覆盖。
- `config\agents.json` 是私有配置（.gitignore 排除），永不入库；仓库只维护 `agents.example.json`。
- duplicate-guard 由 setup / add-agent / verify / merge 共用，新增读取关系必须先更新它。

## 已知技术债与限制

- 向导 / 脚本为 PowerShell 5.1 编写，`&&` 等新语法不可用；内联 `$var` 经 bash 转义会被破坏，需写 .ps1 文件执行。
- `git` 的 stderr 输出会被 PowerShell 当错误显示（NativeCommandError），实际可能成功——判断以退出码为准。
- 探测“已安装”基于目录存在性；个别软件（Marvis）技能根含用户 ID，靠动态发现兜底。
- 共享库含用户手工迁移的技能时无远程基准，`check-updates` 无法检测其更新（仅显示本地版本）。
