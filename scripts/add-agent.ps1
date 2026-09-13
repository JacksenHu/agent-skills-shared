#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 接入单个 Agent：为其技能根目录建立到共享库的联接

.DESCRIPTION
  对指定目录执行与 setup.ps1 相同的单目录逻辑：
  - 目录不存在 → 直接建联接
  - 已是联接 → 校验目标
  - 真实目录有内容 → 迁移进共享库（冲突保留并报告）→ 删空目录 → 建联接

  建议同时把该路径写入 config\agents.json，便于后续统一巡检。

.EXAMPLE
  .\scripts\add-agent.ps1 -AgentName 新Agent -RootPath "C:\Users\me\.newagent\skills"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [string]$SharedRoot = (Join-Path $env:USERPROFILE 'skills\shared')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 加载「同一 Agent 多技能根」重复加载防护（setup / add-agent / verify 共用）
. (Join-Path $PSScriptRoot 'lib\duplicate-guard.ps1')

# ---------- 工具：比较两个目录内容是否完全一致（相对路径 + 文件哈希） ----------
function Test-DirSame {
    param([string]$PathA, [string]$PathB)
    $filesA = @(Get-ChildItem $PathA -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)
    $filesB = @(Get-ChildItem $PathB -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)
    if ($filesA.Count -ne $filesB.Count) { return $false }
    if ($filesA.Count -eq 0) { return $true }
    $sha = [Security.Cryptography.SHA256]::Create()
    for ($i = 0; $i -lt $filesA.Count; $i++) {
        $relA = $filesA[$i].FullName.Substring($PathA.Length).TrimStart([char[]]@('\', '/'))
        $relB = $filesB[$i].FullName.Substring($PathB.Length).TrimStart([char[]]@('\', '/'))
        if ($relA -ne $relB) { return $false }
        $hA = [Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($filesA[$i].FullName)))
        $hB = [Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($filesB[$i].FullName)))
        if ($hA -ne $hB) { return $false }
    }
    return $true
}

$root = [IO.Path]::GetFullPath($RootPath)
$sharedRoot = [IO.Path]::GetFullPath($SharedRoot)

Write-Host "接入 Agent: $AgentName" -ForegroundColor Cyan
Write-Host "根目录:   $root" -ForegroundColor Cyan
Write-Host "共享库:   $sharedRoot" -ForegroundColor Cyan

# ---------- 预检：同一 Agent 多技能根 → 重复加载防护 ----------
# 新目录若与该软件已有的技能根（含 config\agents.json 中已接入的）构成同源多根，
# 接入共享库会导致技能重复加载。默认取消，避免重复发生。
$knownPaths = @()
$cfgPath = Join-Path $PSScriptRoot '..\config\agents.json'
if (Test-Path $cfgPath) {
    try {
        $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.agents) {
            $knownPaths += @($cfg.agents.PSObject.Properties | ForEach-Object { [IO.Path]::GetFullPath([string]$_.Value) })
        }
    } catch { }
}
$knownPaths += $root
$conflicts = Get-SameSourceConflicts @($knownPaths | Select-Object -Unique)
if ($WhatIfPreference) {
    Show-ConflictWarning $conflicts | Out-Null
} elseif (-not (Show-ConflictWarning $conflicts -Ask)) {
    Write-Host '已取消：新目录与该软件已有的技能根构成重复加载，请只保留一个入口（其余用 remove-agent.ps1 拆除）。' -ForegroundColor Yellow
    exit 1
}

# 共享库不存在时创建
if (-not (Test-Path $sharedRoot)) {
    if ($PSCmdlet.ShouldProcess($sharedRoot, '创建共享技能库目录')) {
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null
        Write-Host "[OK] 已创建共享库: $sharedRoot" -ForegroundColor Green
    }
}

# 与 setup.ps1 相同的单目录处理
if (Test-Path $root) {
    $item = Get-Item $root -Force
    if ($item.LinkType -eq 'Junction') {
        $target = [string](($item.Target) -join '')
        if ($target -eq $sharedRoot) {
            Write-Host "[SKIP] 已是指向共享库的联接" -ForegroundColor Yellow
        } else {
            Write-Warning "是联接但目标不是共享库: $target`n请先手动处理，再重新运行。"
        }
        return
    }
    if (-not $item.PSIsContainer) {
        Write-Warning "$root 不是目录，已中止。"
        return
    }

    $children = @(Get-ChildItem $root -Force)
    $conflicted = 0
    if ($children.Count -gt 0) {
        Write-Host "迁移 $($children.Count) 项已有内容到共享库…"
        foreach ($c in $children) {
            $dest = Join-Path $sharedRoot $c.Name
            if (Test-Path $dest) {
                if (Test-DirSame -PathA $c.FullName -PathB $dest) {
                    Write-Host "  [去重] $($c.Name) 与共享库内容一致，移除冗余副本" -ForegroundColor Yellow
                    if ($PSCmdlet.ShouldProcess($c.FullName, '移除与共享库内容一致的冗余副本')) {
                        Remove-Item -Path $c.FullName -Recurse -Force
                    }
                } else {
                    Write-Warning "  [冲突] 共享库已有同名「$($c.Name)」但内容不同；保留原处 `n         $($c.FullName)`n         请人工决定（保留哪份），处理后再运行。"
                    $conflicted++
                }
                continue
            }
            if ($PSCmdlet.ShouldProcess($c.FullName, '迁移到共享库')) {
                Move-Item -Path $c.FullName -Destination $dest
                Write-Host "  已迁移: $($c.Name)" -ForegroundColor Green
            }
        }
    }
    if ($conflicted -gt 0) {
        Write-Warning "$AgentName 存在 $conflicted 项内容冲突（见上方），目录未清空，请人工处理后重跑。"
        return
    }
    if ($PSCmdlet.ShouldProcess($root, '删除空目录（内容已迁移）')) {
        Remove-Item -Path $root -Force
    }
    if (Test-Path $root) {
        Write-Warning "$root 未能清空，请手动处理后再运行。"
        return
    }
}

if ($PSCmdlet.ShouldProcess($root, "创建目录联接 -> $sharedRoot")) {
    $out = & cmd /c ('mklink /J "' + $root + '" "' + $sharedRoot + '"') 2>&1
    $out | ForEach-Object { Write-Host "  $_" }
    $check = Get-Item $root -Force -ErrorAction SilentlyContinue
    $checkTarget = if ($check) { [string](($check.Target) -join '') } else { '' }
    if ($check -and $check.LinkType -eq 'Junction' -and $checkTarget -eq $sharedRoot) {
        Write-Host "[OK] 联接已建立: $root" -ForegroundColor Green
        Write-Host "提示：记得把该路径加入 config\agents.json（键名 $AgentName），并重启该 Agent 会话。"
    } else {
        Write-Warning "[FAIL] 联接创建失败，请检查目标路径与权限。"
    }
}
