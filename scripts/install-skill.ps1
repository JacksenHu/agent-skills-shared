#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 从 GitHub 仓库一键安装技能到共享库

.DESCRIPTION
  给定一个 GitHub 仓库链接（技能仓库），自动：
  1) 下载仓库（zip，无需安装 git）；
  2) 识别技能位置：仓库根目录有 SKILL.md → 视为单个技能；
     否则扫描子目录，把每个含 SKILL.md 的目录作为独立技能；
  3) 复制到共享技能库（sharedRoot），同名冲突默认跳过并报告；
  4) 输出安装结果与依赖提示。

  安装到共享库后，所有已接入的 Agent 都能读取（重启会话生效）。

.EXAMPLE
  .\scripts\install-skill.ps1 -RepoUrl "https://github.com/hgta23/findskills"
  .\scripts\install-skill.ps1 -RepoUrl "https://github.com/vinvcn/mattpocock-skills-zh-CN" -Replace
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\agents.json'),
    [string]$SharedRoot,        # 留空则读配置；配置不存在则用默认 ~\skills\shared
    [switch]$Replace            # 同名冲突时替换共享库旧版本
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# TLS 1.2（Windows PowerShell 5.1 访问 GitHub 必需）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

# ---------- 解析仓库链接 ----------
# 支持：https://github.com/owner/repo、owner/repo、带 tree/branch、带 .git
$url = $RepoUrl.Trim()
$m = [regex]::Match($url, 'github\.com[:/]([^/\s]+)/([^/\s#?]+)')
if (-not $m.Success) {
    Write-Err "无法识别的 GitHub 链接：$RepoUrl`n示例：https://github.com/owner/repo"
    exit 1
}
$owner = $m.Groups[1].Value
$repo  = $m.Groups[2].Value -replace '\.git$', ''

# ---------- 确定共享库位置 ----------
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
    if ($PSCmdlet.ShouldProcess($sharedRoot, '创建共享技能库目录')) {
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null
    }
}
Write-Host "共享技能库: $sharedRoot" -ForegroundColor Cyan
Write-Host "安装来源:   $owner/$repo" -ForegroundColor Cyan

# ---------- 下载 zip ----------
$tmpDir = Join-Path $env:TEMP ("skill-install-" + [guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tmpDir 'repo.zip'
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
try {
    # 通过 API 取默认分支（失败时回退 main / master 逐个尝试）
    $branch = $null
    try {
        $api = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo" -Headers @{ 'User-Agent' = 'agent-skills-shared' } -TimeoutSec 20
        $branch = $api.default_branch
    } catch { $branch = $null }
    $candidates = @(if ($branch) { $branch } else { 'main'; 'master' })

    $downloaded = $false
    foreach ($b in $candidates) {
        $zipUrl = "https://codeload.github.com/$owner/$repo/zip/refs/heads/$b"
        try {
            Write-Host "下载: $zipUrl"
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ 'User-Agent' = 'agent-skills-shared' } -TimeoutSec 60 -UseBasicParsing
            if ((Get-Item $zipPath).Length -gt 0) { $downloaded = $true; break }
        } catch { }
    }
    if (-not $downloaded) {
        Write-Err "下载失败：仓库不存在、为私有或网络不可达。$owner/$repo"
        exit 1
    }

    $extractDir = Join-Path $tmpDir 'extract'
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $repoRoot = @(Get-ChildItem $extractDir -Directory)[0].FullName

    # ---------- 识别技能目录 ----------
    $skillMdFiles = @(Get-ChildItem $repoRoot -Recurse -File -Filter 'SKILL.md' -Force -ErrorAction SilentlyContinue)
    if ($skillMdFiles.Count -eq 0) {
        Write-Err "仓库中没有找到任何 SKILL.md，无法安装。$owner/$repo"
        exit 1
    }
    # 每个 SKILL.md 的父目录即技能目录；若 A 是 B 的父目录，只保留更外层的 A
    $allDirs = @($skillMdFiles | ForEach-Object { $_.Directory.FullName } | Sort-Object -Unique)
    $skillDirs = @($allDirs | Where-Object {
        $parent = Split-Path $_ -Parent
        -not ($allDirs -contains $parent)
    })
    # 若唯一技能目录就是仓库根（根有 SKILL.md），用仓库名作为技能名
    $useRepoName = ($skillDirs.Count -eq 1 -and $skillDirs[0] -eq $repoRoot)

    Write-Host "`n识别到 $($skillDirs.Count) 个技能：" -ForegroundColor Cyan
    foreach ($d in $skillDirs) {
        $skillName = if ($d -eq $repoRoot) { $repo } else { Split-Path $d -Leaf }
        Write-Host "  - $skillName"
    }

    # ---------- 复制到共享库 ----------
    $installed = @(); $skipped = @(); $replaced = @()
    foreach ($d in $skillDirs) {
        $skillName = if ($d -eq $repoRoot) { $repo } else { Split-Path $d -Leaf }
        $dest = Join-Path $sharedRoot $skillName

        if (Test-Path $dest) {
            if ($Replace) {
                if ($PSCmdlet.ShouldProcess($dest, "替换共享库中的 $skillName")) {
                    Remove-Item $dest -Recurse -Force
                    Copy-Item $d -Destination $dest -Recurse -Force
                    $replaced += $skillName
                    Write-Warn "[替换] $skillName 已替换为仓库版本"
                }
            } else {
                Write-Warn "[跳过] 共享库已存在同名技能 $skillName（用 -Replace 可强制替换）"
                $skipped += $skillName
            }
            continue
        }
        if ($PSCmdlet.ShouldProcess($dest, "安装技能 $skillName")) {
            Copy-Item $d -Destination $dest -Recurse -Force
            $count = @(Get-ChildItem $dest -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue).Count
            $installed += $skillName
            Write-Ok "已安装: $skillName（$count 个 SKILL.md）"
        }
    }

    # ---------- 依赖提示 ----------
    $depFiles = @(Get-ChildItem $repoRoot -File | Where-Object { $_.Name -in @('package.json', 'requirements.txt', 'pyproject.toml', 'Gemfile') })
    if ($depFiles.Count -gt 0) {
        Write-Host ''
        Write-Warn '该仓库带依赖清单（package.json / requirements.txt 等）。若技能运行报错，请到对应技能目录按需安装依赖（如 npm install / pip install -r requirements.txt）。'
    }

    # ---------- 汇总 ----------
    Write-Host "`n========== 安装结果 ==========" -ForegroundColor Cyan
    if ($installed.Count) { Write-Ok "新装 $($installed.Count) 个: $($installed -join ', ')" }
    if ($replaced.Count)  { Write-Warn "替换 $($replaced.Count) 个: $($replaced -join ', ')" }
    if ($skipped.Count)   { Write-Warn "跳过 $($skipped.Count) 个: $($skipped -join ', ')" }
    Write-Host "目标共享库: $sharedRoot" -ForegroundColor Cyan
    Write-Host "重启各 Agent 会话即可生效。"
} finally {
    # 清理临时文件
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}
