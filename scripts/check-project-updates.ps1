#requires -Version 5.1
<#
.SYNOPSIS
  检测并更新「本项目（agent-skills-shared 工具）」自身版本

.DESCRIPTION
  对比项目根 VERSION 文件（如 1.0.0）与 GitHub 仓库远程 VERSION：
    [最新]   本地与远程版本号一致
    [有更新] 远程版本号比本地新（或内容不同）
    [无基准] 本地没有 VERSION 文件（首次使用，可 -Update 同步一次）
    [不可查] 远程读取失败（仓库不存在/网络异常/匿名限速）

  仓库为公开仓库，匿名即可检测，无需登录。
  可选：设置 GitHub Token 提高 API 配额（匿名限速 60 次/小时）：
    - 设置环境变量 GITHUB_TOKEN，或运行本脚本时 -Token ghp_xxx
    - Token 无效时脚本会自动降级为匿名访问，不影响检测

  -Update 升级流程：
    1) 优先用 git clone（已安装 git 时）拉取最新仓库到临时目录；
    2) 否则尝试下载 zip；
    3) 对比文件差异，逐个覆盖项目文件（自动排除 config\agents.json 用户配置）；
    4) 本地 VERSION 随更新文件同步到远程版本。

.EXAMPLE
  .\scripts\check-project-updates.ps1                  # 仅检测（匿名）
  .\scripts\check-project-updates.ps1 -Update          # 检测并升级
  .\scripts\check-project-updates.ps1 -Token ghp_xxx   # 用 Token 提高配额
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProjectRoot,
    [string]$Token,
    [switch]$Update
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# TLS 1.2（Windows PowerShell 5.1 访问 GitHub 必需）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$owner = 'JacksenHu'
$repo  = 'agent-skills-shared'
$branch = 'main'

# ---------- 定位项目根与 VERSION ----------
if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$versionFile = Join-Path $ProjectRoot 'VERSION'
if (-not $Token -and $env:GITHUB_TOKEN) { $Token = $env:GITHUB_TOKEN }

function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host $Msg -ForegroundColor Cyan }

$localVersion = ''
if (Test-Path $versionFile) {
    $localVersion = (Get-Content $versionFile -Raw -Encoding UTF8).Trim()
}
Write-Info "项目目录: $ProjectRoot"
Write-Host ("本地版本: {0}" -f $(if ($localVersion) { $localVersion } else { '（无 VERSION，未记录基准）' })) -ForegroundColor DarkGray

# ---------- 读取远程 VERSION（公开仓库匿名可读；Token 可选提高配额，失败自动降级匿名） ----------
$remoteVersion = ''
$remoteError = ''
$tryTokens = @()
if ($Token) { $tryTokens += $Token }
$tryTokens += ''          # 兜底匿名访问
foreach ($tk in $tryTokens) {
    $h = @{ 'User-Agent' = 'agent-skills-shared' }
    if ($tk) { $h['Authorization'] = "token $tk" }
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/contents/VERSION?ref=$branch" -Headers $h -TimeoutSec 20 -UseBasicParsing
        $pContent = $resp.PSObject.Properties['content']
        if ($pContent -and $pContent.Value) {
            $remoteVersion = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([string]$pContent.Value))).Trim()
            $remoteError = ''
        }
        break
    } catch {
        $code = 0
        try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 }
        if ($code -eq 401 -or $code -eq 403) {
            if ($tk) { Write-Warn 'Token 无效或权限不足，自动改用匿名访问重试。'; continue }
            $remoteError = 'auth'   # 匿名也被拒 → 大概率触发限速
            break
        } elseif ($code -eq 404) {
            # 仓库不存在，或远程缺少 VERSION 文件
            $remoteError = 'notfound'
git commit --amend -m "test"
            break
        } else {
            $remoteError = 'net'
            break
        }
    }
}

# ---------- 判定 ----------
Write-Host ''
if ($remoteError -or -not $remoteVersion) {
    if ($remoteError -eq 'auth') {
        Write-Warn 'GitHub API 拒绝了匿名访问（大概率触发匿名限速 60 次/小时）。'
        Write-Host '  设置 GITHUB_TOKEN 环境变量，或使用 -Token <token> 提高配额后重试。' -ForegroundColor DarkGray
    } elseif ($remoteError -eq 'notfound') {
        Write-Err '远程不可读（404）：仓库不存在，或远程缺少 VERSION 文件。'
        Write-Host '  请确认仓库名/分支正确。' -ForegroundColor DarkGray
    } else {
        Write-Warn '无法连接 GitHub（网络异常或限速），稍后重试。'
    }
    if (Test-Path (Join-Path $ProjectRoot '.git')) {
        Write-Host '  本目录是 git 克隆：也可直接运行 git pull 获取最新版（注意勿覆盖 config\agents.json）。' -ForegroundColor DarkGray
    }
    if ($Update) { Write-Err '远程不可用，已取消升级。' }
    exit 1
}

Write-Info ("远程版本: {0}" -f $remoteVersion)
if (-not $localVersion) {
    Write-Warn '[无基准] 本地未记录版本。运行 -Update 同步最新版本即可建立基准。'
    if (-not $Update) { exit 2 }
} elseif ($localVersion -eq $remoteVersion) {
    Write-Ok '[最新] 本项目已是最新版本。'
    if (-not $Update) { exit 0 }
} else {
    Write-Warn "[有更新] 本地 $localVersion → 远程 $remoteVersion"
    if (-not $Update) {
        Write-Host '升级：.\scripts\check-project-updates.ps1 -Update' -ForegroundColor Cyan
        exit 3
    }
}

# ---------- 升级流程 ----------
Write-Host ''
Write-Info '========== 开始升级 =========='
$tmpDir = Join-Path $env:TEMP ("project-update-" + [guid]::NewGuid().ToString('N'))
$srcRoot = $null
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
try {
    # 方式 1：git clone（最可靠；Token 可选，用于提高配额）
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $authUrl = "https://github.com/$owner/$repo.git"
        if ($Token) { $authUrl = "https://${Token}@github.com/$owner/$repo.git" }
        Write-Host "git clone --depth 1 $authUrl  …"
        $cloneDir = Join-Path $tmpDir 'clone'
        & git clone --depth 1 --branch $branch $authUrl $cloneDir 2>&1 | ForEach-Object { Write-Host "  $_" }
        if (Test-Path (Join-Path $cloneDir 'README.md')) { $srcRoot = $cloneDir }
    }
    # 方式 2：下载 zip（codeload，公开仓库无需登录）
    if (-not $srcRoot) {
        $zipPath = Join-Path $tmpDir 'repo.zip'
        $zipUrl = "https://codeload.github.com/$owner/$repo/zip/refs/heads/$branch"
        try {
            Write-Host "下载: $zipUrl"
            $iwrArgs = @{ Uri = $zipUrl; OutFile = $zipPath; TimeoutSec = 60; UseBasicParsing = $true }
            if ($Token) { $iwrArgs.Headers = @{ 'User-Agent' = 'agent-skills-shared'; 'Authorization' = "token $Token" } }
            else { $iwrArgs.Headers = @{ 'User-Agent' = 'agent-skills-shared' } }
            Invoke-WebRequest @iwrArgs
            if ((Get-Item $zipPath).Length -gt 0) {
                $extractDir = Join-Path $tmpDir 'extract'
                Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
                $cand = @(Get-ChildItem $extractDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'README.md') })
                if ($cand.Count -gt 0) { $srcRoot = $cand[0].FullName }
            }
        } catch {
            Write-Warn "zip 下载失败：$($_.Exception.Message)"
        }
    }

    if (-not $srcRoot) {
        Write-Err '未能自动获取更新包。请手动升级：'
        Write-Host '  1) 浏览器打开仓库 → Code → Download ZIP' -ForegroundColor DarkGray
        Write-Host '  2) 解压后，将 scripts / docs / diagrams / README.md / VERSION 等覆盖到本项目目录' -ForegroundColor DarkGray
        Write-Host "  3) 不要覆盖 config\agents.json（你的配置）" -ForegroundColor DarkGray
        Write-Host "  项目目录: $ProjectRoot" -ForegroundColor DarkGray
        exit 1
    }

    # ---------- 对比并覆盖（排除用户配置） ----------
    Write-Host ''
    Write-Host '比对远程文件与本地差异…' -ForegroundColor Cyan
    $newFiles = @(Get-ChildItem $srcRoot -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '\\\\\\.git\\\\'
    })
    $changed = @()
    $same = 0
    foreach ($f in $newFiles) {
        $rel = $f.FullName.Substring($srcRoot.Length).TrimStart([char[]]@('\\\\\u0027, '/\u0027))
        if ($rel -ieq 'config/agents.json') { continue }   # 用户配置绝不覆盖
        $dest = Join-Path $ProjectRoot $rel
        if (Test-Path $dest) {
            $h1 = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
            $h2 = (Get-FileHash $dest -Algorithm SHA256).Hash
            if ($h1 -eq $h2) { $same++; continue }
        }
        $changed += [pscustomobject]@{ Rel = $rel; Src = $f.FullName; Dest = $dest }
    }
    if ($changed.Count -eq 0) {
        Write-Ok "无需更新：$same 个文件与远程一致。"
        exit 0
    }
    Write-Warn "发现 $($changed.Count) 个文件需更新（$same 个已一致）："
    foreach ($c in $changed) { Write-Host "  - $($c.Rel)" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '? 确认覆盖以上文件？（config\agents.json 已自动排除） [Y/n]  > ' -NoNewline
    $ans = (Read-Host).Trim().ToLower()
    if ($ans -ne 'y' -and $ans -ne 'yes' -and $ans -ne '') {
        Write-Ok '已取消，未做任何修改。'
        exit 0
    }

    foreach ($c in $changed) {
        $dir = Split-Path $c.Dest -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($PSCmdlet.ShouldProcess($c.Dest, '覆盖为远程版本')) {
            Copy-Item $c.Src -Destination $c.Dest -Force
            Write-Host "  ✔ $($c.Rel)" -ForegroundColor Green
        }
    }
    Write-Host ''
    Write-Ok "升级完成，本地版本 = $remoteVersion"
    Write-Host '提示：桌面「统一技能库管理」快捷方式若指向本目录则无需重建；' -ForegroundColor DarkGray
    Write-Host '      若快捷方式失效（目录被移动），删除旧快捷方式后重新启动向导即可自动重建。' -ForegroundColor DarkGray
} finally {
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
}
