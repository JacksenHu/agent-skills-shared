#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 归并「同一 Agent 多技能根」：消除技能重复加载

.DESCRIPTION
  部分软件（豆包、Trae 等）会同时扫描多个已注册的技能根目录。
  如果这些根全部通过 Junction 指向同一个共享库，软件会把每个技能重复加载多份
  （例：豆包同时读 .user_skills / Doubao\skills / .agents\skills → 每技能 3 份）。

  本脚本对每个「会被同一软件同时扫描」的根组：
    - 列出组内各根当前状态（Junction→共享库 / 空目录·已归并 / 缺失 / 其他）
    - 交互式让您选择保留哪个根接入共享库（默认推荐覆盖 Agent 最多的共享根）
    - 其余根执行归并：拆除 Junction（技能数据仍完整保留在共享库）并重建为空目录
      —— 软件仍能找到该根，但读不到技能，因此不再重复加载。

  安全说明：拆除联接使用 cmd /c rmdir（不带 /s），绝不穿透联接删除共享库数据；
  随后重建空目录（New-Item），让软件原技能根路径继续存在。

.EXAMPLE
  .\scripts\merge-agent-roots.ps1               # 交互式选择
  .\scripts\merge-agent-roots.ps1 -Force        # 非交互：各组默认保留推荐根
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 加载「同一 Agent 多技能根」组定义（setup / add-agent / verify 共用）
. (Join-Path $PSScriptRoot 'lib\duplicate-guard.ps1')

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

if (-not (Test-Path $ConfigPath)) {
    throw "找不到配置文件: $ConfigPath"
}
$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sharedRoot = [IO.Path]::GetFullPath([string]$config.sharedRoot)

$agents = @($config.agents.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; Path = [IO.Path]::GetFullPath([string]$_.Value) }
} | Sort-Object Path -Unique)

Write-Host "共享技能库: $sharedRoot`n" -ForegroundColor Cyan

# 收集每个根的状态
function Get-RootState {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 'missing' }
    $item = Get-Item $Path -Force
    if ($item.LinkType -eq 'Junction') {
        $target = [string](($item.Target) -join '')
        if ($target -eq $sharedRoot) { return 'active' }     # 活跃：Junction→共享库
        return 'other-link'                                   # 指向别处
    }
    $hasContent = @(Get-ChildItem $Path -Force).Count -gt 0
    if (-not $hasContent) { return 'empty' }                  # 空目录（已归并过）
    return 'real-dir'                                         # 真实非空目录
}

$stateText = @{
    active     = '活跃（Junction→共享库）'
    empty      = '空目录（已归并）'
    missing    = '目录不存在'
    'other-link' = '联接→其他目标'
    'real-dir' = '真实非空目录（未归并）'
}

# 逐组归并
$changed = $false
foreach ($g in $script:SameSourceGroups) {
    $hits = @($agents | Where-Object { Test-SameSourcePattern $_.Path $g.Patterns })
    if ($hits.Count -lt 2) { continue }    # 单根或无根，无需归并

    $states = @{}
    foreach ($h in $hits) { $states[$h.Path] = Get-RootState $h.Path }
    $active = @($hits | Where-Object { $states[$_.Path] -eq 'active' })
    if ($active.Count -le 1) {
        Write-Host ("[SKIP] {0}：活跃根 {1} 个，无需归并。" -f $g.Name, $active.Count) -ForegroundColor DarkGray
        continue
    }

    Write-Host ''
    Write-Host ("════════ {0} · 检测到 {1} 个技能根同时指向共享库 ════════" -f $g.Name, $active.Count) -ForegroundColor Yellow
    for ($i = 0; $i -lt $hits.Count; $i++) {
        $h = $hits[$i]
        $st = $states[$h.Path]
        $mark = switch ($st) { 'active' { '[A] 活跃' } 'empty' { '[ ] 已归并' } default { '[?] ' + $stateText[$st] } }
        $cover = ''
        # 标注该根还会被哪些软件读取（按组表反查）
        $who = @()
        foreach ($g2 in $script:SameSourceGroups) {
            if ($g2.Name -eq $g.Name) { continue }
            if (Test-SameSourcePattern $h.Path $g2.Patterns) { $who += $g2.Name }
        }
        if ($who.Count -gt 0) { $cover = '（同时被: ' + ($who -join '、') + ' 读取）' }
        Write-Host ("  [{0}]  {1,-6} {2}{3}" -f ($i + 1), $mark, $h.Path, $cover) -ForegroundColor Gray
    }
    Write-Host '  ⚠ 保留的根继续提供全部技能；其余根拆联接后变空目录，技能数据仍留在共享库。' -ForegroundColor DarkGray

    # 默认推荐：覆盖软件最多的共享根（通常是 .agents\skills）
    $defaultIdx = 0
    $best = -1
    for ($i = 0; $i -lt $hits.Count; $i++) {
        $score = 0
        foreach ($g2 in $script:SameSourceGroups) {
            if (Test-SameSourcePattern $hits[$i].Path $g2.Patterns) { $score++ }
        }
        if ($score -gt $best) { $best = $score; $defaultIdx = $i }
    }

    $keepIdx = -1
    if ($Force) {
        $keepIdx = $defaultIdx
        Write-Host ("  [非交互] 默认保留: {0}" -f $hits[$keepIdx].Path) -ForegroundColor Cyan
    } else {
        while ($true) {
            Write-Host ("? 保留哪个根接入共享库？[1-{0}]（默认 {1}）  > " -f $hits.Count, ($defaultIdx + 1)) -NoNewline
            $ans = (Read-Host).Trim()
            if ($ans -eq '') { $keepIdx = $defaultIdx; break }
            if ($ans -match '^\d+$' -and [int]$ans -ge 1 -and [int]$ans -le $hits.Count) { $keepIdx = [int]$ans - 1; break }
            Write-Host "  输入无效，请输入 1-$($hits.Count)。" -ForegroundColor Red
        }
    }

    $keep = $hits[$keepIdx]
    Write-Host ("  保留: {0}" -f $keep.Path) -ForegroundColor Green
    foreach ($h in $hits) {
        if ($h.Path -eq $keep.Path) { continue }
        if ($states[$h.Path] -ne 'active') { continue }   # 只处理活跃根

        $root = $h.Path
        Write-Host ("  归并: {0}" -f $root) -ForegroundColor Cyan
        # 1) 拆联接（仅删重解析点，数据保留在共享库）
        $out = & cmd /c ('rmdir "' + $root + '"') 2>&1
        $out | ForEach-Object { Write-Host ("      " + $_) }
        if (Test-Path $root) {
            Write-Host ("      [FAIL] 拆除失败: {0}（可能被占用），跳过该根。" -f $root) -ForegroundColor Red
            continue
        }
        # 2) 重建空目录，让软件原技能根路径继续存在
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Write-Host ("      [OK] 已归并: {0} → 空目录（技能数据仍在 {1}）" -f $root, $sharedRoot) -ForegroundColor Green
        $changed = $true
    }
    Write-Host ("  [完成] {0} 归并结束。" -f $g.Name) -ForegroundColor Green
}

Write-Host ''
if ($changed) {
    Write-Host '========== 归并完成 ==========' -ForegroundColor Cyan
    Write-Host '· 所有被拆根的技能数据仍完整保留在共享库，未删除任何内容。' -ForegroundColor Green
    Write-Host '· 请重启对应软件（新开会话）验证技能列表：重复项应消失，技能数量 = 共享库技能数。' -ForegroundColor Green
    Write-Host '· 若某个软件技能列表变空/变少，说明它实际读的是被归并的根：' -ForegroundColor Yellow
    Write-Host '  重新运行本脚本选择该根保留，并把之前保留的根改回即可（用 add-agent.ps1 重新接入）。' -ForegroundColor Yellow
    Write-Host '· 运行 verify.ps1 可复查：归并根显示 [归并·空]，保留根显示 [OK]。' -ForegroundColor Cyan
} else {
    Write-Host '没有需要归并的技能根组。' -ForegroundColor Cyan
}
