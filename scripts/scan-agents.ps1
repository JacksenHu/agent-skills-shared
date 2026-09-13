#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 扫描各 Agent 技能目录，检测"已安装但未进共享库"的技能

.DESCRIPTION
  用户在某个 Agent 里手动安装的技能会落在该 Agent 自己的技能目录。
  本脚本逐 Agent 检查：
    - 目录不存在（该 Agent 未安装 / 路径变了）
    - 已通过 Junction 接入共享库（技能全部来自共享库，无独有）
    - 真实目录：列出其中的技能，与共享库逐一对比
        * 与共享库同名且内容一致  → 已共享（无需处理）
        * 与共享库同名但内容不同  → 冲突（两边都有，需人工决定）
        * 共享库中没有             → 该 Agent 独有（建议迁移进共享库）
  输出带状态标注的技能清单与处理建议。

.EXAMPLE
  .\scripts\scan-agents.ps1
  .\scripts\scan-agents.ps1 -ConfigPath .\config\agents.json
#>
[CmdletBinding()]
param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

function Write-Info { param([string]$Msg) Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

if (-not (Test-Path $ConfigPath)) {
    Write-Err "未找到配置：$ConfigPath"
    Write-Host '请先运行 .\scripts\setup-wizard.ps1 → [1] 快速搭建 生成配置。'
    exit 1
}

$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sharedRoot = [IO.Path]::GetFullPath([string]$cfg.sharedRoot)
$agents = @($cfg.agents.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; Path = [string]$_.Value }
} | Sort-Object Name)

Write-Host "共享技能库: $sharedRoot" -ForegroundColor Cyan
Write-Host ("共 {0} 个 Agent 待检查`n" -f $agents.Count) -ForegroundColor Cyan

# ---------- 工具函数 ----------
function Get-ContentHash {
    # 目录内容指纹：相对路径 + 文件大小 + SHA-256，用于内容级比对
    param([string]$Dir)
    $files = @(Get-ChildItem $Dir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '_meta.json' })
    if ($files.Count -eq 0) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in $files | Sort-Object FullName) {
        $rel = $f.FullName.Substring($Dir.Length).TrimStart('\')
        $sha = (Get-FileHash $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        [void]$sb.Append("$rel|$($f.Length)|$sha;")
    }
    return $sb.ToString()
}

function Get-SkillDirs {
    # 目录下含 SKILL.md 的技能目录（排除 _meta.json 等文件影响）
    param([string]$Dir)
    $mds = @(Get-ChildItem $Dir -Recurse -File -Filter 'SKILL.md' -Force -ErrorAction SilentlyContinue)
    $all = @($mds | ForEach-Object { $_.Directory.FullName } | Sort-Object -Unique)
    return @($all | Where-Object {
        $parent = Split-Path $_ -Parent
        -not ($all -contains $parent)
    })
}

function Get-SkillName {
    param([string]$SkillDir, [string]$Root)
    if ($SkillDir -eq $Root) { return (Split-Path $Root -Leaf) }
    return (Split-Path $SkillDir -Leaf)
}

# ---------- 主流程 ----------
$totalLonely = 0
$conflicts = @()
foreach ($agent in $agents) {
    Write-Host ("===== Agent: {0}" -f $agent.Name) -ForegroundColor White
    Write-Host ("  路径: {0}" -f $agent.Path)

    if (-not (Test-Path $agent.Path)) {
        Write-Warn '  ✗ 目录不存在（该 Agent 可能未安装，或路径已变化）'
        Write-Host ''
        continue
    }

    $item = Get-Item $agent.Path -Force
    if ($item.LinkType) {
        $target = [string](($item.Target) -join '')
        if ($target.TrimEnd('\') -eq $sharedRoot.TrimEnd('\')) {
            Write-Ok "  ✓ 已接入共享库（Junction → $target）"
            Write-Host '    该 Agent 的技能全部来自共享库，无独有技能。'
        } else {
            Write-Warn "  ⚠ 是联接，但指向其他目录：$target"
            Write-Host '    未指向共享库，请人工检查。'
        }
        Write-Host ''
        continue
    }

    # 真实目录：逐技能对比
    $skillDirs = Get-SkillDirs $agent.Path
    if ($skillDirs.Count -eq 0) {
        Write-Warn '  ✗ 该目录下没有任何 SKILL.md 技能'
        Write-Host ''
        continue
    }
    Write-Host "  目录是真实目录（未接入共享库），检测到 $($skillDirs.Count) 个技能："

    foreach ($sd in $skillDirs) {
        $name = Get-SkillName $sd $agent.Path
        $sharedSkill = Join-Path $sharedRoot $name
        if (Test-Path $sharedSkill) {
            $localHash  = Get-ContentHash $sd
            $sharedHash = Get-ContentHash $sharedSkill
            if ($localHash -eq $sharedHash -and $localHash -ne '') {
                Write-Ok    "    [已共享] $name —— 与共享库内容一致（重复安装，可删除本目录下该技能）"
            } else {
                Write-Warn  "    [冲突]   $name —— 共享库也有同名技能但内容不同，两边保留，需人工决定"
                $conflicts += "$($agent.Name):$name"
            }
        } else {
            Write-Warn "    [独有]   $name —— 共享库中没有，建议迁移进共享库"
            $totalLonely++
        }
    }
    Write-Host ''
}

# ---------- 汇总与建议 ----------
Write-Host '========== 汇总 ==========' -ForegroundColor Cyan
if ($totalLonely -eq 0 -and $conflicts.Count -eq 0) {
    Write-Ok '未发现独有技能或冲突技能，各 Agent 技能均已纳入共享库。'
} else {
    if ($totalLonely -gt 0) {
        Write-Warn "发现 $totalLonely 个独有技能（只存在于单个 Agent，未进共享库）。"
        Write-Host '处理方式：'
        Write-Host '  1) 迁移到共享库（推荐，所有 Agent 共用）：在向导 [1] 快速搭建中重新勾选该 Agent，'
        Write-Host '     或运行 .\scripts\setup.ps1 让迁移逻辑自动处理；'
        Write-Host '  2) 若只是想让该 Agent 也能看到共享技能：运行 .\scripts\add-agent.ps1 接入。'
    }
    if ($conflicts.Count -gt 0) {
        Write-Warn "发现 $($conflicts.Count) 个冲突技能（与共享库同名但内容不同）。"
        Write-Host '处理方式：人工检查两边内容，决定保留哪一份；再用向导 [3] 技能管理移除另一份，'
        Write-Host '或 install-skill.ps1 -Replace 用仓库版本覆盖。'
    }
}
