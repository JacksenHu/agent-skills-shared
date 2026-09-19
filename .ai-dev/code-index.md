# Code Index — 代码地图（自动生成，请勿手改）

- 生成时间：2026-09-20 01:15（手工增量校正：generate-router-skill.ps1 199→186 行）
- 源码文件：20 个，合计约 4309 行
- 用法：先在本文件定位目标，再精读对应源码；不要全仓遍历。增删/移动文件后用 build_index.py 重建。

## 目录结构

```text
agent-skills-shared/
config/
diagrams/
docs/
scripts/
  lib/
```

## 文件清单（按目录分组）

### (root)

- `README.md` (343 行) — Agent Skills 共享方案（统一目录 + 目录联接）  <!-- README.md -->
### config

- `agents.example.json` (29 行) — Agent 路径配置模板（24 项预设，含 Marvis 占位）  <!-- config/agents.example.json -->
### docs

- `01-architecture.md` (131 行) — 01 · 方案详解（架构与原理）  <!-- docs/01-architecture.md -->
- `02-agent-path-reference.md` (113 行) — 02 · 主流 Agent 技能目录速查表  <!-- docs/02-agent-path-reference.md -->
- `03-setup-guide.md` (201 行) — 03 · 完整搭建指南  <!-- docs/03-setup-guide.md -->
- `04-day-to-day.md` (234 行) — 04 · 日常使用  <!-- docs/04-day-to-day.md -->
- `05-safety-and-rollback.md` (101 行) — 05 · 风险清单与回滚  <!-- docs/05-safety-and-rollback.md -->
- `06-faq.md` (224 行) — 06 · 常见问题（FAQ）  <!-- docs/06-faq.md -->
### scripts

- `add-agent.ps1` (151 行) — requires -Version 5.1  <!-- scripts/add-agent.ps1 -->
- `check-project-updates.ps1` (250 行) — requires -Version 5.1  <!-- scripts/check-project-updates.ps1 -->
- `check-updates.ps1` (220 行) — requires -Version 5.1  <!-- scripts/check-updates.ps1 -->
- `generate-router-skill.ps1` (186 行) — requires -Version 5.1  <!-- scripts/generate-router-skill.ps1 -->
- `install-skill.ps1` (272 行) — requires -Version 5.1  <!-- scripts/install-skill.ps1 -->
- `merge-agent-roots.ps1` (164 行) — requires -Version 5.1  <!-- scripts/merge-agent-roots.ps1 -->
- `remove-agent.ps1` (73 行) — requires -Version 5.1  <!-- scripts/remove-agent.ps1 -->
- `scan-agents.ps1` (158 行) — requires -Version 5.1  <!-- scripts/scan-agents.ps1 -->
- `setup-wizard.ps1` (1115 行) — requires -Version 5.1  <!-- scripts/setup-wizard.ps1 -->
- `setup.ps1` (173 行) — requires -Version 5.1  <!-- scripts/setup.ps1 -->
- `verify.ps1` (107 行) — requires -Version 5.1  <!-- scripts/verify.ps1 -->
### scripts/lib

- `duplicate-guard.ps1` (64 行) — duplicate-guard.ps1 — 「同一 Agent 多技能根」重复加载防护 被 setup.ps1 / add-agent.ps1 / verify.ps1 共用（dot-source 加载） 背景：部分软件（如豆包）会同时扫描  <!-- scripts/lib/duplicate-guard.ps1 -->
