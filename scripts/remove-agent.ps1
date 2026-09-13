#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 移除单个 Agent：拆除其技能根目录的联接（回滚）

.DESCRIPTION
  按 agents.json 中的键名找到该 Agent 的根目录，仅拆除联接（『门』），
  共享库中的技能数据原封不动。需要时随时可用 add-agent.ps1 重新接入。

  ⚠ 安全说明：拆除联接使用 cmd /c rmdir（不带 /s）。禁止对联接使用
  Remove-Item -Recurse / robocopy /MIR 等递归操作 —— 会穿透联接删除共享库数据。

.EXAMPLE
  .\scripts\remove-agent.ps1 -AgentName claude-code          # 会二次确认
  .\scripts\remove-agent.ps1 -AgentName claude-code -Force   # 跳过确认
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$AgentName,
    [string]$ConfigPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

if (-not (Test-Path $ConfigPath)) {
    throw "找不到配置文件: $ConfigPath"
}
$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sharedRoot = [IO.Path]::GetFullPath([string]$config.sharedRoot)

# 按键名定位
$prop = $config.agents.PSObject.Properties | Where-Object { $_.Name -eq $AgentName }
if (-not $prop) {
    throw "配置中找不到 Agent「$AgentName」。现有: $((@($config.agents.PSObject.Properties.Name)) -join ', ')"
}
$root = [IO.Path]::GetFullPath([string]$prop.Value)

Write-Host "Agent:   $AgentName" -ForegroundColor Cyan
Write-Host "根目录:  $root" -ForegroundColor Cyan

if (-not (Test-Path $root)) {
    Write-Host "[SKIP] $root 不存在，无需处理。" -ForegroundColor Yellow
    exit 0
}

$item = Get-Item $root -Force
if ($item.LinkType -ne 'Junction') {
    Write-Host "[SKIP] $root 不是联接（真实目录？），无需拆除。" -ForegroundColor Yellow
    exit 0
}

$target = [string](($item.Target) -join '')
Write-Host "联接目标: $target" -ForegroundColor Cyan
Write-Host "将只拆除联接（『门』），共享库数据保留。" -ForegroundColor Yellow

if ($Force -or $PSCmdlet.ShouldProcess($root, '拆除目录联接（数据保留在共享库）')) {
    # 仅删除重解析点本身；绝不使用 -Recurse / rmdir /s
    $out = & cmd /c ('rmdir "' + $root + '"') 2>&1
    $out | ForEach-Object { Write-Host "  $_" }

    if (Test-Path $root) {
        Write-Warning "[FAIL] 联接拆除失败，请检查是否被占用。"
        exit 1
    }
    Write-Host "[OK] 联接已拆除: $root" -ForegroundColor Green
    Write-Host "技能数据仍完整保留在: $sharedRoot" -ForegroundColor Green
    Write-Host "提示：如需把该 Agent 从配置中移除，请编辑 config\agents.json。"
}
