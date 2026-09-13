#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 验证：检查所有 Agent 的联接与技能可见性

.DESCRIPTION
  逐项检查配置中的每个 Agent 技能根目录：
  - 目录是否存在
  - 是否为 Junction 且指向共享库
  - 通过该入口能看到多少个 SKILL.md

  任一检查失败会以非零退出码结束，便于脚本化。

.EXAMPLE
  .\scripts\verify.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 加载「同一 Agent 多技能根」重复加载防护（setup / add-agent / verify 共用）
. (Join-Path $PSScriptRoot 'lib\duplicate-guard.ps1')

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

if (-not (Test-Path $ConfigPath)) {
    throw "找不到配置文件: $ConfigPath"
}
$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sharedRoot = [IO.Path]::GetFullPath([string]$config.sharedRoot)

$agentPaths = @($config.agents.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; Path = [IO.Path]::GetFullPath([string]$_.Value) }
} | Sort-Object Path -Unique)

Write-Host "共享技能库: $sharedRoot`n" -ForegroundColor Cyan

$failCount = 0
foreach ($a in $agentPaths) {
    $root = $a.Path

    if (-not (Test-Path $root)) {
        Write-Host ("[FAIL] {0,-22} 目录不存在: {1}" -f $a.Name, $root) -ForegroundColor Red
        $failCount++
        continue
    }
    $item = Get-Item $root -Force
    if ($item.LinkType -ne 'Junction') {
        Write-Host ("[FAIL] {0,-22} 不是联接（是真实目录？）: {1}" -f $a.Name, $root) -ForegroundColor Red
        $failCount++
        continue
    }
    $target = [string](($item.Target) -join '')
    if ($target -ne $sharedRoot) {
        Write-Host ("[FAIL] {0,-22} 指向错误目标: {1}" -f $a.Name, $target) -ForegroundColor Red
        $failCount++
        continue
    }
    $count = @(Get-ChildItem -Path $root -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue).Count
    Write-Host ("[OK]   {0,-22} -> {1}（{2} 个 SKILL.md）" -f $a.Name, $target, $count) -ForegroundColor Green
}

# ---------- 重复入口检测（不阻塞，仅提示） ----------
$conflicts = Get-SameSourceConflicts @($agentPaths | ForEach-Object { $_.Path })
Show-ConflictWarning $conflicts | Out-Null

Write-Host "`n========== 验证结果 ==========" -ForegroundColor Cyan
if ($failCount -eq 0) {
    Write-Host "全部通过 ✅  重启各 Agent 会话即可使用共享技能。" -ForegroundColor Green
} else {
    Write-Host "存在 $failCount 项异常 ❌  请按 docs/05 排查（常见：路径写错、目录未被迁移）。" -ForegroundColor Red
}
exit $failCount
