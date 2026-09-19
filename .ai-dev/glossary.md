# Glossary — 术语表

> 只收会被猜错的业务黑话与缩写，不收通用词汇。词条格式：术语 — 一句话解释（必要时的背景）。

## 项目专用术语

- **共享库（shared library）** — 本项目的唯一技能数据源：`%USERPROFILE%\skills\shared`。所有 Agent 技能根通过 Junction 指向它。
- **Junction** — Windows NTFS 目录联接（`mklink /J`），无需管理员权限；指向共享库后，Agent 读其技能根即读到共享库内容，写入实时穿透。
- **接入（add-agent）** — 把某 Agent 的用户级技能根目录与共享库建立 Junction 联接（含已有技能迁移、去重）。
- **移除（remove-agent）** — 拆除某 Agent 技能根与共享库的联接，数据保留在共享库（拆的是“路”，不是“库”）。
- **迁移冲突** — 接入时共享库已有同名但内容不同的技能目录；默认保留原处、不覆盖，提示人工决策后重跑。
- **重复加载（同源多根）** — 同一软件同时读取多个技能根目录且都指向共享库，导致每个技能被加载多份（如豆包同时读 `.user_skills` + `Doubao\skills` + `.agents\skills`）。duplicate-guard.ps1 负责识别。
- **`_meta.json`** — install-skill.ps1 为技能生成的元数据（自动翻译的中文简介 + 版本基准 branch/commitSha），技能管理列表与路由索引读取它。
- **skill-router（router-guide）** — 共享库内的总路由技能 `router-guide\SKILL.md`：按 9 大分类索引全部技能，任何 Agent 触发它可按情境推荐技能。
- **9 大分类** — 开发与工程 / 写作与内容 / 研究与搜索 / 办公与效率 / 数据分析 / 设计与创意 / 音视频与媒体 / Agent 与技能管理 / 生活与日常（另有「未分类」兜底）。
- **VERSION 自更（check-project-updates）** — 项目根 VERSION 文件记录本地版本，脚本对比 GitHub 远程版本；有 git 走 git clone 覆盖，无 git 走 zip 下载。
- **父目录探测（ProbePath）** — 软件已安装但技能根子目录未创建时（如 `~\.codebuddy` 存在而 `~\.codebuddy\skills` 不存在），仍识别为「✅ 已安装 · 技能根待创建」并可接入。

## Agent 路径黑话

- **Agent 用户级技能根** — 各软件存放用户技能的位置，如豆包 `~\.agents\skills`、Claude Code `~\.claude\skills`、Codex `~\.codex\skills`、WorkBuddy 国内 `~\.workbuddy\skills`、CodeBuddy（WorkBuddy AI 国际版）`~\.codebuddy\skills`、Trae `~\.trae\skills`（CN 为 `.trae-cn`）、Qoder `~\.qoder\skills`（CN 为 `.qoder-cn`）。
- **平台内置技能根** — 软件自带的系统技能目录，**不接入共享库**（如豆包 `...\agent_mode\workspace\.skills`）。
