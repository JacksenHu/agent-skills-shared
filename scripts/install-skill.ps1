#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 从 GitHub / skills.sh 一键安装技能到共享库

.DESCRIPTION
  给定一个技能仓库链接，自动：
  1) 识别来源：
       GitHub   https://github.com/owner/repo、owner/repo（含 tree/branch/.git）
       skills.sh https://skills.sh/s/owner/repo 或 https://skills.sh/s/owner/repo/skill-name
     skills.sh 是 Vercel 的技能市场，底层仍是 GitHub 仓库；
  2) 下载仓库 zip（无需安装 git）；
  3) 识别技能位置：仓库根有 SKILL.md → 视为单个技能；
     否则扫描子目录，把每个含 SKILL.md 的目录作为独立技能；
     若链接指定了具体技能名（skills.sh 的 /skill-name），只安装该技能；
  4) 复制到共享技能库（sharedRoot），同名冲突默认跳过并报告；
  5) 为每个技能生成 _meta.json（含名称、简介、中文翻译简介与版本基准
     branch + commitSha，供 check-updates.ps1 检测技能版本升级），
     供「技能管理」列表显示中文简介；
  6) 输出安装结果与依赖提示。

  安装到共享库后，所有已接入的 Agent 都能读取（重启会话生效）。

.EXAMPLE
  .\scripts\install-skill.ps1 -RepoUrl "https://github.com/hgta23/findskills"
  .\scripts\install-skill.ps1 -RepoUrl "https://skills.sh/s/vercel-labs/skills/find-skills"
  .\scripts\install-skill.ps1 -RepoUrl "https://github.com/vinvcn/mattpocock-skills-zh-CN" -Replace
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$RepoUrl,
    [string]$ConfigPath,
    [string]$SharedRoot,        # 留空则读配置；配置不存在则用默认 ~\skills\shared
    [switch]$Replace            # 同名冲突时替换共享库旧版本
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

# TLS 1.2（Windows PowerShell 5.1 访问 GitHub 必需）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

# ---------- 中文简介（免费翻译接口，失败回退原文） ----------
function ConvertTo-DescriptionZh {
    param([string]$Description)
    if ([string]::IsNullOrWhiteSpace($Description)) { return '' }
    # 已含中文则无需翻译
    if ($Description -match '[\u4e00-\u9fff]') { return $Description.Trim() }
    if ($Description.Length -gt 800) { $Description = $Description.Substring(0, 800) }
    $q = [uri]::EscapeDataString($Description)
    # 1) MyMemory（免费，无需 key，国内可达）
    try {
        $uri = "https://api.mymemory.translated.net/get?q=$q&langpair=en|zh-CN"
        $r = Invoke-RestMethod -Uri $uri -TimeoutSec 10 -UseBasicParsing
        $zh = [string]$r.responseData.translatedText
        if ($zh -and $zh -ne 'NO QUERY SPECIFIED' -and $zh -notmatch 'MYMEMORY WARNING') { return $zh.Trim() }
    } catch { }
    # 2) Google gtx（部分地区不可达，作为兜底）
    try {
        $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=$q"
        $r = Invoke-RestMethod -Uri $uri -TimeoutSec 8 -UseBasicParsing
        $zh = ''
        foreach ($seg in @($r[0])) { $zh += [string]$seg[0] }
        if ($zh) { return $zh.Trim() }
    } catch { }
    return $Description.Trim()
}

# 写 _meta.json：名称 / 简介 / 中文简介 / 来源 / 版本基准（branch + commitSha）/ 时间
# commitSha 为安装时仓库默认分支最新提交，供 check-updates.ps1 检测升级用
function Write-SkillMeta {
    param([string]$Dest, [string]$SkillName, [string]$Desc)
    $descZh = ConvertTo-DescriptionZh $Desc
    $meta = [ordered]@{
        name          = $SkillName
        description   = $Desc
        descriptionZh = $descZh
        source        = "https://github.com/$owner/$repo"
        branch        = $branch
        commitSha     = $commitSha
        installedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    $meta | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $Dest '_meta.json') -Encoding UTF8
}

function Read-SkillFrontmatter {
    param([string]$SkillMdPath)
    $text = Get-Content $SkillMdPath -Raw -Encoding UTF8
    $m = [regex]::Match($text, '(?s)^---\s*\r?\n(.*?)\r?\n---')
    $meta = [ordered]@{}
    if ($m.Success) {
        foreach ($line in ($m.Groups[1].Value -split "`r?`n")) {
            $kv = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$')
            if ($kv.Success) {
                $meta[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim().Trim('"').Trim("'")
            }
        }
    }
    return $meta
}

# ---------- 解析仓库链接 ----------
# 支持：github.com/owner/repo、owner/repo、skills.sh/s/owner/repo[/skill-name]
$url = $RepoUrl.Trim()
$owner = $null; $repo = $null; $wantedSkill = $null

$m = [regex]::Match($url, 'skills\.sh[:/]s?/([^/\s#?]+)/([^/\s#?]+)(?:/([^/\s#?]+))?')
if ($m.Success) {
    $owner = $m.Groups[1].Value
    $repo  = $m.Groups[2].Value -replace '\.git$', ''
    $wantedSkill = $m.Groups[3].Value
    if ($wantedSkill) { Write-Warn "skills.sh 链接指定技能: $wantedSkill（仅安装该技能）" }
} else {
    $m = [regex]::Match($url, 'github\.com[:/]([^/\s]+)/([^/\s#?]+)')
    if (-not $m.Success) {
        Write-Err "无法识别的链接：$RepoUrl`n支持：`n  https://github.com/owner/repo`n  owner/repo`n  https://skills.sh/s/owner/repo（或 /skill-name）"
        exit 1
    }
    $owner = $m.Groups[1].Value
    $repo  = $m.Groups[2].Value -replace '\.git$', ''
}

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
    $commitSha = ''
    try {
        $api = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo" -Headers @{ 'User-Agent' = 'agent-skills-shared' } -TimeoutSec 20
        $branch = $api.default_branch
    } catch { $branch = $null }
    # 记录版本基准：默认分支最新提交 SHA（供 check-updates.ps1 检测升级）
    if ($branch) {
        try {
            $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/commits/$branch" -Headers @{ 'User-Agent' = 'agent-skills-shared' } -TimeoutSec 20 -UseBasicParsing
            $commitSha = [string]$commit.sha
        } catch { $commitSha = '' }
    }
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

    # skills.sh 链接指定了技能名：只保留该技能目录（按目录名匹配）
    if ($wantedSkill) {
        $wanted = @($skillDirs | Where-Object { (Split-Path $_ -Leaf) -eq $wantedSkill })
        if ($wanted.Count -eq 0) {
            Write-Warn "仓库中没有找到指定技能目录 [$wantedSkill]，将安装全部技能。"
        } else {
            $skillDirs = $wanted
        }
    }

    Write-Host "`n识别到 $($skillDirs.Count) 个技能：" -ForegroundColor Cyan
    foreach ($d in $skillDirs) {
        $skillName = if ($d -eq $repoRoot) { $repo } else { Split-Path $d -Leaf }
        Write-Host "  - $skillName"
    }

    # ---------- 复制到共享库 + 生成简介元数据 ----------
    $installed = @(); $skipped = @(); $replaced = @()
    foreach ($d in $skillDirs) {
        $skillName = if ($d -eq $repoRoot) { $repo } else { Split-Path $d -Leaf }
        $dest = Join-Path $sharedRoot $skillName

        $desc = ''
        $mdFile = Join-Path $d 'SKILL.md'
        if (Test-Path $mdFile) {
            $fm = Read-SkillFrontmatter $mdFile
            $desc = [string]$fm['description']
        }

        if (Test-Path $dest) {
            if ($Replace) {
                if ($PSCmdlet.ShouldProcess($dest, "替换共享库中的 $skillName")) {
                    Remove-Item $dest -Recurse -Force
                    Copy-Item $d -Destination $dest -Recurse -Force
                    Write-SkillMeta -Dest $dest -SkillName $skillName -Desc $desc
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
            Write-SkillMeta -Dest $dest -SkillName $skillName -Desc $desc
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
