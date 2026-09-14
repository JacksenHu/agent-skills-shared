# 02 · 主流 Agent 技能目录速查表

> 路径均为**用户级（全局）**技能目录，即本方案要接的地方。
> 标 ✅ 的路径经官方文档或实测确认；标 ⚠️ 的为社区资料，请以本机为准。

## Windows 用户级技能目录

> 以下 23 项已**预设**在 `setup-wizard.ps1` 的选择列表中（自动探测本机状态，`d` 一键全选已检测到的）。

| Agent | 用户级技能目录 | 项目级技能目录 | 来源 |
| --- | --- | --- | --- |
| **Doubao（豆包）用户技能** ✅ | `%LOCALAPPDATA%\Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills` | — | 本机实测（用户技能装这里） |
| **Doubao 其他技能根** ✅ | `%USERPROFILE%\Doubao\skills`、`%USERPROFILE%\.agents\skills` | — | 本机实测（均为已注册技能根） |
| **Claude Code** ✅ | `%USERPROFILE%\.claude\skills\{slug}\SKILL.md` | `.claude\skills\` | [Claude Code 官方文档](https://code.claude.com/docs/en/skills) |
| **Codex** ✅ | `%USERPROFILE%\.agents\skills\`（新标准）；旧版 `%USERPROFILE%\.codex\skills\` | `.agents\skills\` | [Codex 官方文档](https://www.codex-docs.com/docs/build-skills) |
| **Cursor** ✅ | `%USERPROFILE%\.cursor\skills\`、`%USERPROFILE%\.agents\skills\` | `.cursor\skills\`、`.agents\skills\` | [Cursor 官方文档](https://cursor.com/docs/skills) |
| **Windsurf** ✅ | `%USERPROFILE%\.codeium\windsurf\skills\`（Global） | `.windsurf\skills\` | [Windsurf 官方文档](https://docs.windsurf.com/windsurf/cascade/skills) |
| **OpenClaw** ⚠️ | `%USERPROFILE%\.openclaw\workspace\skills\` | — | ClawHub 技能安装文档 |
| **Trae（国际版）** ✅ | `%USERPROFILE%\.trae\skills\` | `.trae\skills\` | [Trae 官方文档](https://docs.trae.ai/ide/skills) |
| **Trae CN（国内版）** ✅ | `%USERPROFILE%\.trae-cn\skills\` | `.trae\skills\` | [Trae CN 官方文档](https://docs.trae.cn/ide_skills) |
| **GitHub Copilot** ✅ | `%USERPROFILE%\.copilot\skills\`、`%USERPROFILE%\.agents\skills\` | `.github\skills\`、`.agents\skills\` | [GitHub Docs](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/add-skills) |
| **Zed** ✅ | `%USERPROFILE%\.agents\skills\`（Global） | `.agents\skills\` | [Zed 官方文档](https://zed.dev/docs/ai/skills) |
| **WorkBuddy** ✅ | `%USERPROFILE%\.workbuddy\skills\` | — | 本机实测（用户指定） |
| **Marvis（腾讯）** ⚠️ | `%APPDATA%\Tencent\Marvis\User\<用户ID>\skills\custom`（**用户 ID 非固定**，向导自动发现 User 下所有含技能的用户目录） | — | 本机实测（用户指定） |
| **Gemini CLI** ✅ | `%USERPROFILE%\.gemini\skills\`；兼容 `%USERPROFILE%\.agents\skills\` | `.gemini\skills\`、`.agents\skills\` | [Gemini CLI 官方文档](https://geminicli.com/docs/cli/skills/) |
| **OpenCode** ✅ | `%USERPROFILE%\.config\opencode\skills\`；兼容 `%USERPROFILE%\.claude\skills\` | `.opencode\skills\`、`.claude\skills\` | [OpenCode 官方文档](https://dev.opencode.ai/docs/skills) |
| **Qoder** ✅ | `%USERPROFILE%\.qoder\skills\` | `.qoder\skills\` | [Qoder 官方文档](https://docs.qoder.com/cli/Skills) |
| **Qoder CN（通义灵码）** ✅ | `%USERPROFILE%\.qoder-cn\skills\` | `.qoder\skills\` | [阿里云帮助中心](https://help.aliyun.com/zh/lingma/qodercli-cn/user-guide/skills) |
| **Kiro（AWS，Amazon Q CLI 继任）** ✅ | `%USERPROFILE%\.kiro\skills\` | `.kiro\skills\` | [Kiro 官方文档](https://kiro.dev/docs/cli/skills/) |
| **Cline** ✅ | `%USERPROFILE%\.cline\skills\` | `.cline\skills\`、`.clinerules\skills\` | [Cline 官方文档](https://docs.cline.bot/customization/skills) |
| **Roo Code** ✅ | `%USERPROFILE%\.roo\skills\`；兼容 `%USERPROFILE%\.agents\skills\` | `.roo\skills\`、`.agents\skills\` | [Roo Code 官方文档](https://roocodeinc.github.io/Roo-Code/features/skills/) |
| **Augment** ✅ | `%USERPROFILE%\.augment\skills\`；兼容 `%USERPROFILE%\.claude\skills\`、`%USERPROFILE%\.agents\skills\` | `.augment\skills\`、`.claude\skills\` | [Augment 官方文档](https://docs.augmentcode.com/cli/skills) |
| **Crush** ⚠️ | `%USERPROFILE%\.config\crush\skills\` | — | 社区资料（[gist](https://gist.github.com/annextuckner/ad639503a0b5fc8cff863ae0559b53c5)），请以本机为准 |
| **Pi** ⚠️ | `%USERPROFILE%\.pi\agent\skills\` | — | 社区资料（[Skillkit](https://skillkit.net/)），请以本机为准 |

> `%LOCALAPPDATA%` = `C:\Users\<你>\AppData\Local`；`%USERPROFILE%` = `C:\Users\<你>`。

## 扫描优先级（同名技能时谁生效）

- **Claude Code**：Enterprise > Personal（`~/.claude/skills`）> Project（`.claude/skills`）> Plugin
- **Codex**：`$CWD/.agents/skills` > 父目录 `.agents/skills` > 仓库根 `.agents/skills` > `$HOME/.agents/skills` > `/etc/codex/skills` > 内置
- **Cursor**：项目级优先于用户级；同时兼容读取 `.claude/skills`、`.codex/skills`（含用户级）

## 值得注意的"事实标准"

`.agents/skills` 正在成为跨 Agent 的通用技能目录：

- **Codex** 与 **Cursor** 的用户级/项目级都读它；
- **Zed** 全局技能目录就是它；
- **GitHub Copilot** / **VS Code** / **Visual Studio** 都支持读它（与 `~/.copilot/skills` 并列）；
- **Doubao** 也把 `%USERPROFILE%\.agents\skills` 注册为技能根之一；
- **Trae** 也读取 `.agents/skills`；
- **Gemini CLI** / **OpenCode** / **Roo Code** / **Augment** / **Goose** / **Warp** 均兼容读取 `.agents/skills`（或 `.claude/skills`）。

因此本方案在预设清单中把 `~\.agents\skills` 作为跨 Agent 的共享入口，
一份联接即可覆盖 Codex / Cursor / Zed / Copilot / Doubao / Trae / Gemini CLI / Roo Code / Augment / Goose / Warp 等多个 Agent。

> ⚠️ **多技能根 → 重复加载**：部分软件会**同时读多个根**（豆包读
> `.user_skills` + `Doubao\skills` + `.agents\skills`，Trae 读 `.trae-cn\skills` +
> `.agents\skills`）。若这些根全部接入共享库，软件会把每份技能重复加载多份。
> 接入时脚本会自动检测并默认阻止；已接入的用
> `.\scripts\merge-agent-roots.ps1`（向导 [4]c）**一键归并**到单个根，
> 重复立即消除。详见 `docs/04` 第 6b 节。

## 如何确认你机器上的真实路径

```powershell
# 列出可能存在的技能根（覆盖预设清单全部 23 项）
$paths = @(
  "$env:LOCALAPPDATA\Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills",
  "$env:USERPROFILE\Doubao\skills",
  "$env:USERPROFILE\.claude\skills",
  "$env:USERPROFILE\.agents\skills",
  "$env:USERPROFILE\.codex\skills",
  "$env:USERPROFILE\.cursor\skills",
  "$env:USERPROFILE\.codeium\windsurf\skills",
  "$env:USERPROFILE\.openclaw\workspace\skills",
  "$env:USERPROFILE\.trae\skills",
  "$env:USERPROFILE\.trae-cn\skills",
  "$env:USERPROFILE\.copilot\skills",
  "$env:USERPROFILE\.workbuddy\skills",
  "$env:USERPROFILE\.gemini\skills",
  "$env:USERPROFILE\.config\opencode\skills",
  "$env:USERPROFILE\.qoder\skills",
  "$env:USERPROFILE\.qoder-cn\skills",
  "$env:USERPROFILE\.kiro\skills",
  "$env:USERPROFILE\.cline\skills",
  "$env:USERPROFILE\.roo\skills",
  "$env:USERPROFILE\.augment\skills",
  "$env:USERPROFILE\.config\crush\skills",
  "$env:USERPROFILE\.pi\agent\skills"
)
# Marvis 用户 ID 非固定：动态列出所有含技能的用户目录
$marvisUserDir = Join-Path $env:APPDATA 'Tencent\Marvis\User'
if (Test-Path $marvisUserDir) {
  Get-ChildItem $marvisUserDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'skills\custom') } | ForEach-Object { Write-Output (Join-Path $_.FullName 'skills\custom') }
}
$paths | Where-Object { Test-Path $_ } | ForEach-Object { Write-Output $_ }

# 查看某个目录当前内容（确认是否已有技能）
Get-ChildItem "$env:USERPROFILE\.claude\skills"
```

> 把确认存在的路径填入 `config\agents.json` 即可，不存在的路径不写。
> 更省事：直接运行 `.\scripts\setup-wizard.ps1` → [1] 快速搭建，勾选即可，无需手写。
