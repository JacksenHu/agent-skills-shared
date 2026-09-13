#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 交互式安装引导：按菜单选择即可完成配置、搭建与验证

.DESCRIPTION
  全程交互，无需手写 JSON：
  1) 自动探测本机常见 Agent 技能目录（Doubao / Claude Code / Codex / Cursor…）
  2) 菜单选择要接入的 Agent（支持自定义添加其他路径）
  3) 选择共享技能库位置（默认 %USERPROFILE%\skills\shared）
  4) 自动生成 config\agents.json
  5) 自动调用 setup.ps1 搭建、verify.ps1 验证

  若 config\agents.json 已存在，可一键沿用现有配置直接搭建/验证。

.EXAMPLE
  .\scripts\setup-wizard.ps1          # 启动交互引导
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\agents.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------- 输出辅助 ----------
function Write-Info { param([string]$Msg) Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

# ---------- 交互辅助 ----------
function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $raw = (Read-Host "$Prompt $suffix").Trim().ToLower()
        if ($raw -eq '') { return $Default }
        if ($raw -in @('y', 'yes')) { return $true }
        if ($raw -in @('n', 'no')) { return $false }
        Write-Warn '请输入 y 或 n。'
    }
}

function Read-ChoiceList {
    param([int]$Count, [string]$Prompt)
    while ($true) {
        $raw = (Read-Host $Prompt).Trim().ToLower()
        if ($raw -eq '' -or $raw -eq 'q') { return @() }
        if ($raw -eq 'a') { return @(1..$Count) }
        $sel = @()
        $valid = $true
        foreach ($part in ($raw -split ',')) {
            $p = $part.Trim()
            if ($p -notmatch '^\d+$') { $valid = $false; break }
            $n = [int]$p
            if ($n -lt 1 -or $n -gt $Count) { $valid = $false; break }
            $sel += $n
        }
        if ($valid -and $sel.Count -gt 0) { return @($sel | Sort-Object -Unique) }
        Write-Warn "输入无效，请输入 1-$Count 的编号（逗号分隔多选）、a 或 q。"
    }
}

# ---------- 自动探测表 ----------
$detectors = @(
    @{ Key = 'doubao-user-skills'; Label = 'Doubao（豆包）用户技能'; Path = (Join-Path $env:LOCALAPPDATA 'Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills') },
    @{ Key = 'claude-code';         Label = 'Claude Code';             Path = (Join-Path $env:USERPROFILE '.claude\skills') },
    @{ Key = 'codex-agents-skills'; Label = 'Codex / Cursor（.agents）'; Path = (Join-Path $env:USERPROFILE '.agents\skills') },
    @{ Key = 'cursor';              Label = 'Cursor（.cursor）';        Path = (Join-Path $env:USERPROFILE '.cursor\skills') }
)

$setupScript   = Join-Path $PSScriptRoot 'setup.ps1'
$verifyScript  = Join-Path $PSScriptRoot 'verify.ps1'

# ---------- 欢迎 ----------
Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  统一技能库 · 交互式安装引导' -ForegroundColor White
Write-Host '  一套技能，只装一次，所有 Agent 共用（NTFS Junction）' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor Cyan

# ---------- 已有配置？ ----------
$useExisting = $false
if (Test-Path $ConfigPath) {
    Write-Host ''
    Write-Warn "检测到已有配置：$ConfigPath"
    $useExisting = Read-YesNo '直接沿用现有配置搭建/验证？' $true
}

# ---------- 引导生成配置 ----------
if (-not $useExisting) {
    Write-Info ''
    Write-Info '[1/3] 共享技能库位置'
    $defaultShared = Join-Path $env:USERPROFILE 'skills\shared'
    Write-Host "  默认：$defaultShared"
    $in = (Read-Host '  回车使用默认，或输入其他路径').Trim()
    $sharedRoot = if ($in) { [IO.Path]::GetFullPath($in) } else { $defaultShared }

    Write-Info ''
    Write-Info '[2/3] 选择要接入的 Agent（已自动探测以下目录）'
    $choices = @()
    for ($i = 0; $i -lt $detectors.Count; $i++) {
        $d = $detectors[$i]
        $mark = if (Test-Path $d.Path) { '已检测到' } else { '未找到' }
        Write-Host ("  [{0}] {1,-26} {2,-10} {3}" -f ($i + 1), $d.Label, $mark, $d.Path)
        $choices += [pscustomobject]@{ Key = $d.Key; Path = $d.Path }
    }
    $sel = Read-ChoiceList $choices.Count '  输入编号接入（逗号分隔多选，a=全部，q=跳过）'

    $agentList = @()
    foreach ($n in $sel) {
        $c = $choices[$n - 1]
        $agentList += [pscustomobject]@{ Name = $c.Key; Path = $c.Path }
    }

    if (Read-YesNo '  添加自定义 Agent 路径？' $false) {
        Write-Host '  格式：名称=完整路径（如 myagent=C:\Users\me\.myagent\skills），空行结束'
        while ($true) {
            $line = (Read-Host '  名称=路径').Trim()
            if ($line -eq '') { break }
            $eq = $line.IndexOf('=')
            if ($eq -le 0) { Write-Warn '格式错误，应为 名称=路径'; continue }
            $name = $line.Substring(0, $eq).Trim()
            $path = $line.Substring($eq + 1).Trim()
            if (-not $name -or -not $path) { Write-Warn '名称或路径为空，已忽略。'; continue }
            $agentList += [pscustomobject]@{ Name = $name; Path = [IO.Path]::GetFullPath($path) }
        }
    }

    if ($agentList.Count -eq 0) {
        Write-Err '未选择任何 Agent，已取消，未做任何修改。'
        exit 1
    }

    Write-Info ''
    Write-Info '[3/3] 确认配置'
    Write-Host "  共享库：$sharedRoot"
    foreach ($a in $agentList) {
        Write-Host ("    {0} -> {1}" -f $a.Name, $a.Path)
    }
    if (-not (Read-YesNo '确认无误，写入配置并开始搭建？' $true)) {
        Write-Host '已取消，未做任何修改。'
        exit 0
    }

    # 写配置（同名去重，保留最后添加）
    $agents = [ordered]@{}
    foreach ($a in $agentList) { $agents[$a.Name] = $a.Path }
    $cfg = [ordered]@{ sharedRoot = $sharedRoot; agents = $agents }
    $configDir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    $cfg | ConvertTo-Json -Depth 4 | Out-File -FilePath $ConfigPath -Encoding UTF8
    Write-Ok "已写入配置：$ConfigPath"
}

# ---------- 搭建 + 验证 ----------
Write-Host ''
Write-Host '--- 开始搭建（setup.ps1）---' -ForegroundColor Cyan
& $setupScript -ConfigPath $ConfigPath

Write-Host ''
Write-Host '--- 开始验证（verify.ps1）---' -ForegroundColor Cyan
& $verifyScript -ConfigPath $ConfigPath

Write-Host ''
Write-Ok '引导完成！请重启各 Agent 会话（新开会话）使技能生效。'
