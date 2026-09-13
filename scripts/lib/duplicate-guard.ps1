# duplicate-guard.ps1 — 「同一 Agent 多技能根」重复加载防护
# 被 setup.ps1 / add-agent.ps1 / verify.ps1 共用（dot-source 加载）
#
# 背景：部分软件（如豆包）会同时扫描多个已注册的技能根目录。
# 若这些目录全部通过 Junction 指向同一个共享库，软件会把每个技能重复加载多份
# （例如豆包同时读 .user_skills / Doubao\skills / .agents\skills → 每技能 3 份）。
# 本文件内置"会被同一软件同时扫描"的技能根组，用于接入前检测并默认阻止。
#
# 组表依据：docs/02-agent-path-reference.md 记录的官方/实测读取关系。
# 路径匹配：小写 + 通配符（* 任意字符），\\ 为 Windows 路径分隔符字面量。

#requires -Version 5.1

$script:SameSourceGroups = @(
    @{ Name = 'Doubao（豆包）'; Patterns = @('*\.doubao\agent_mode\workspace\.user_skills', '*\doubao\skills', '*\.agents\skills') },
    @{ Name = 'Codex / Cursor / Zed / GitHub Copilot'; Patterns = @('*\.agents\skills', '*\.codex\skills', '*\.cursor\skills', '*\.copilot\skills', '*\.zed\skills') },
    @{ Name = 'Trae / Trae CN'; Patterns = @('*\.agents\skills', '*\.trae\skills', '*\.trae-cn\skills') }
)

function Test-SameSourcePattern {
    param([string]$Path, [string[]]$Patterns)
    $p = $Path.ToLowerInvariant()
    foreach ($pat in $Patterns) { if ($p -like $pat) { return $true } }
    return $false
}

# 返回冲突列表：组内命中 >= 2 个路径即为同源多根
function Get-SameSourceConflicts {
    param([string[]]$Paths)
    $conflicts = @()
    foreach ($g in $script:SameSourceGroups) {
        $hits = @($Paths | Where-Object { Test-SameSourcePattern $_ $g.Patterns })
        if ($hits.Count -ge 2) {
            $conflicts += [pscustomobject]@{ Name = $g.Name; Paths = @($hits) }
        }
    }
    return ,$conflicts
}

# 打印警告；-Ask 时返回是否继续（默认 n = 不继续）
function Show-ConflictWarning {
    param([object[]]$Conflicts, [switch]$Ask)
    if (-not $Conflicts -or $Conflicts.Count -eq 0) { return $true }
    Write-Host ''
    Write-Host '╔════ 检测到「同一 Agent 多技能根」重复加载风险 ════╗' -ForegroundColor Red
    foreach ($c in $Conflicts) {
        Write-Host ('  可能被同一软件同时读取：' + $c.Name) -ForegroundColor Yellow
        foreach ($pp in $c.Paths) { Write-Host ('    · ' + $pp) -ForegroundColor DarkGray }
    }
    Write-Host '   这些目录若都指向同一共享库，该软件会把每个技能重复加载多份' -ForegroundColor DarkGray
    Write-Host '  （例：豆包同时读 .user_skills / Doubao\skills / .agents\skills → 每技能 3 份）。' -ForegroundColor DarkGray
    Write-Host '   建议：每个软件只保留一个技能根接入共享库，其余用 remove-agent.ps1 拆除。' -ForegroundColor DarkGray
    if ($Ask) {
        Write-Host '? 仍然继续？（默认 n，取消执行） [y/N]  > ' -NoNewline
        $ans = (Read-Host).Trim().ToLower()
        return ($ans -eq 'y' -or $ans -eq 'yes')
    }
    return $true
}
