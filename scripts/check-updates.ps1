#requires -Version 5.1
<#
.SYNOPSIS
  检测共享库中「从 GitHub 仓库安装」的技能是否有新版本

.DESCRIPTION
  原理：install-skill.ps1 安装/替换技能时，会向技能目录写入 _meta.json，
  其中记录 source（GitHub 仓库链接）、branch 与 commitSha（安装时仓库默认分支
  的最新提交 SHA，作为版本基准）。本脚本遍历共享库技能目录、读取 _meta.json，
  对每个来源仓库调用 GitHub API（GET /repos/{owner}/{repo}/commits?per_page=1）
  获取远程最新提交 SHA，与本地记录的 commitSha 对比，判定是否有新版本。

  检测结果分四类：
    [更新]   本地 commitSha 落后于远程 —— 可升级（见下）
    [最新]   本地 commitSha 与远程一致
    [无基准] 有 source 但无 commitSha（旧版安装尚未记录基准）—— 重新安装一次即可建立基准
    [不可查] 仓库 404（不存在/私有）或 GitHub API 限速、网络异常

  升级方式：
    1) 向导：主菜单 [6] 检查技能版本更新 → 询问后自动升级
    2) 本脚本 -Update：对「有更新」的仓库自动执行 install-skill.ps1 -RepoUrl … -Replace
    3) 手动逐仓库：install-skill.ps1 -RepoUrl https://github.com/<owner>/<repo> -Replace

  注意：
    - 只有通过 install-skill.ps1 从 GitHub 仓库安装的技能可检测；
      迁移/手动放置的技能无来源信息，仅显示本地版本号（WorkBuddy 等市场安装的
      _meta.json 含 version 字段时可见）。
    - GitHub API 匿名限速 60 次/小时（每个仓库消耗 1 次），多仓库建议
      -Token <token> 或设置环境变量 GITHUB_TOKEN 提高配额。

.PARAMETER ConfigPath
  配置文件路径（默认 ..\config\agents.json）

.PARAMETER SharedRoot
  直接指定共享库路径（留空则读配置）

.PARAMETER Token
  GitHub 个人访问令牌（可选；环境变量 GITHUB_TOKEN 亦可）

.PARAMETER Update
  对「有更新」的仓库自动升级（逐个 install-skill.ps1 -RepoUrl <source> -Replace）

.EXAMPLE
  .\scripts\check-updates.ps1
  .\scripts\check-updates.ps1 -Update
  .\scripts\check-updates.ps1 -Token ghp_xxx
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath,
    [string]$SharedRoot,
    [string]$Token,
    [switch]$Update
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

# TLS 1.2（Windows PowerShell 5.1 访问 GitHub 必需）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$installScript = Join-Path $PSScriptRoot 'install-skill.ps1'

function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host $Msg -ForegroundColor Cyan }

# ---------- 定位共享库 ----------
if (-not $SharedRoot) {
    if (Test-Path $ConfigPath) {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $SharedRoot = [IO.Path]::GetFullPath([string]$cfg.sharedRoot)
    } else {
        $SharedRoot = Join-Path $env:USERPROFILE 'skills\shared'
    }
}
$sharedRoot = [IO.Path]::GetFullPath($SharedRoot)
if (-not (Test-Path $sharedRoot)) {
    Write-Err "共享库不存在: $sharedRoot"
    exit 1
}
if (-not $Token -and $env:GITHUB_TOKEN) { $Token = $env:GITHUB_TOKEN }

# ---------- 遍历技能目录，收集来源 ----------
# repos: owner/repo -> { Skills=@(), LocalSha='', RemoteSha='', Status='' }
$repos = [ordered]@{}
$noSource = @()   # 无仓库来源的技能（迁移/市场安装等）
foreach ($dir in @(Get-ChildItem $sharedRoot -Directory -Force)) {
    $metaFile = Join-Path $dir.FullName '_meta.json'
    $skill = [pscustomobject]@{ Name = $dir.Name; LocalSha = ''; Version = '' }
    if (Test-Path $metaFile) {
        try {
            $j = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
            # StrictMode 下访问不存在的属性会抛异常，故用 PSObject.Properties 安全取值
            $pCommit = $j.PSObject.Properties['commitSha']
            $pVersion = $j.PSObject.Properties['version']
            $pSource = $j.PSObject.Properties['source']
            if ($pCommit)  { $skill.LocalSha = [string]$pCommit.Value }
            if ($pVersion) { $skill.Version  = [string]$pVersion.Value }
            $src = if ($pSource) { [string]$pSource.Value } else { '' }
            $m = [regex]::Match($src, 'github\.com[:/]([^/\s]+)/([^/\s#?]+)')
            if ($m.Success) {
                $key = ($m.Groups[1].Value + '/' + ($m.Groups[2].Value -replace '\.git$', ''))
                if (-not $repos.Contains($key)) {
                    $repos[$key] = [pscustomobject]@{ Key = $key; Skills = @(); LocalSha = ''; RemoteSha = ''; Status = '' }
                }
                $repos[$key].Skills += $skill.Name
                # 同仓库多技能共用一个基准；取任一非空本地 SHA
                if ($skill.LocalSha -and -not $repos[$key].LocalSha) { $repos[$key].LocalSha = $skill.LocalSha }
                continue
            }
        } catch { }
    }
    $noSource += $skill
}

if ($repos.Count -eq 0) {
    Write-Warn '共享库中没有找到带 GitHub 来源（_meta.json.source）的技能。'
    Write-Host '提示：用 .\scripts\install-skill.ps1 -RepoUrl <仓库链接> 安装的技能才能检测更新。'
    if ($noSource.Count -gt 0) {
        Write-Host ("无来源技能 {0} 个（仅显示本地版本）：" -f $noSource.Count) -ForegroundColor DarkGray
        foreach ($s in $noSource) {
            $v = if ($s.Version) { 'v' + $s.Version } else { '无版本信息' }
            Write-Host ("  - {0}（{1}）" -f $s.Name, $v) -ForegroundColor DarkGray
        }
    }
    exit 0
}

# ---------- 查询远程最新提交 ----------
Write-Info ("检测 {0} 个来源仓库…（GitHub API，每仓库 1 次请求）" -f $repos.Count)
$headers = @{ 'User-Agent' = 'agent-skills-shared' }
if ($Token) { $headers['Authorization'] = "token $Token" }
$rateLimited = $false

foreach ($key in $repos.Keys) {
    $r = $repos[$key]
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$key/commits?per_page=1" -Headers $headers -TimeoutSec 20 -UseBasicParsing
        $r.RemoteSha = [string]$resp[0].sha
    } catch {
        $code = 0
        try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 }
        if ($code -eq 403 -or $code -eq 429) { $r.Status = 'rate'; $rateLimited = $true }
        elseif ($code -eq 404) { $r.Status = 'gone' }
        else { $r.Status = 'err' }
    }
}

# ---------- 判定 ----------
foreach ($key in $repos.Keys) {
    $r = $repos[$key]
    if ($r.Status) { continue }
    if (-not $r.LocalSha) { $r.Status = 'nobase' }
    elseif ($r.LocalSha -eq $r.RemoteSha) { $r.Status = 'latest' }
    else { $r.Status = 'update' }
}

# ---------- 输出结果 ----------
Write-Host ''
Write-Info '========== 检测结果 =========='
$updatable = @()
foreach ($key in $repos.Keys) {
    $r = $repos[$key]
    $skills = $r.Skills -join ', '
    switch ($r.Status) {
        'update' {
            Write-Warn ("[更新] {0}  技能: {1}" -f $key, $skills)
            $shortLocal = if ($r.LocalSha.Length -gt 12) { $r.LocalSha.Substring(0, 12) } else { $r.LocalSha }
            $shortRemote = if ($r.RemoteSha.Length -gt 12) { $r.RemoteSha.Substring(0, 12) } else { $r.RemoteSha }
            Write-Host ("        本地 {0} → 远程 {1}" -f $shortLocal, $shortRemote)
            $updatable += $key
        }
        'latest' { Write-Ok ("[最新] {0}  技能: {1}" -f $key, $skills) }
        'nobase' { Write-Warn ("[无基准] {0}  技能: {1}（旧版安装无 commitSha，重新安装一次即可建立基准）" -f $key, $skills) }
        'rate'   { Write-Warn ("[限速] {0}  技能: {1}（GitHub API 限速，用 -Token 或设 GITHUB_TOKEN 后重试）" -f $key, $skills) }
        'gone'   { Write-Warn ("[不可查] {0}  技能: {1}（仓库不存在或为私有）" -f $key, $skills) }
        'err'    { Write-Warn ("[不可查] {0}  技能: {1}（网络或接口异常）" -f $key, $skills) }
    }
}

if ($noSource.Count -gt 0) {
    Write-Host ''
    Write-Host ("无仓库来源（无法远程检测，仅显示本地版本）：{0} 个" -f $noSource.Count) -ForegroundColor DarkGray
    foreach ($s in $noSource) {
        $v = if ($s.Version) { 'v' + $s.Version } else { '无版本信息' }
        Write-Host ("  - {0}（{1}）" -f $s.Name, $v) -ForegroundColor DarkGray
    }
}

# ---------- 升级动作 ----------
if ($Update -and $updatable.Count -gt 0) {
    Write-Host ''
    Write-Info '========== 开始自动升级（install-skill.ps1 -Replace）=========='
    foreach ($key in $updatable) {
        $url = "https://github.com/$key"
        Write-Host ("升级: {0}" -f $url) -ForegroundColor Cyan
        if ($PSCmdlet.ShouldProcess($url, '重新安装该仓库技能（-Replace 覆盖本地旧版）')) {
            & $installScript -RepoUrl $url -Replace -ConfigPath $ConfigPath
        }
    }
} elseif ($updatable.Count -gt 0) {
    Write-Host ''
    Write-Host '升级方式：' -ForegroundColor Cyan
    Write-Host '  向导：主菜单 [6] 检查技能版本更新 → 输入 y 自动升级'
    Write-Host '  命令：.\scripts\check-updates.ps1 -Update'
    Write-Host '  逐仓库：.\scripts\install-skill.ps1 -RepoUrl https://github.com/<owner>/<repo> -Replace'
}

if ($rateLimited) {
    Write-Host ''
    Write-Warn '注意：本次有仓库因 GitHub API 匿名限速（60 次/小时）未查询成功。'
    Write-Host '      可用 -Token <GitHub token> 或设置环境变量 GITHUB_TOKEN 提高配额后重试。'
}
Write-Host ''
Write-Ok '检测完成。升级后重启各 Agent 会话生效。'
