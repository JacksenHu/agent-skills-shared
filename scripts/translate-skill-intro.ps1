#requires -Version 5.1
<#
.SYNOPSIS
  技能介绍翻译：把共享库技能的英文简介译成中文，写入 _meta.json

.DESCRIPTION
  扫描共享库（默认取 config\agents.json 的 sharedRoot）下每个含 SKILL.md 的技能：
    1) 取英文简介来源：优先 SKILL.md frontmatter 的 description，其次已有 _meta.json 的 description
    2) 已含中文（简介本身是中文，或 _meta.json 已有 descriptionZh）默认跳过
    3) 调翻译接口译成中文，**合并**写回 _meta.json
       —— 原有 source / branch / commitSha / installedAt 等字段一律保留（供 check-updates 用）
    4) 翻译失败（结果不含中文）不写文件，计入失败数，可稍后重跑

  翻译接口：MyMemory 免费接口（无需 key），失败自动回退 Google gtx；
  两者都不可达时保留原文。长简介按句切块翻译再拼接。

  翻译后如需让「总路由技能」也显示中文简介，再跑一次 generate-router-skill.ps1。

.PARAMETER SharedRoot
  共享技能库路径，默认读 config\agents.json 的 sharedRoot，读不到则用 %USERPROFILE%\skills\shared

.PARAMETER Name
  只处理指定技能（目录名）。不填则处理全库。

.PARAMETER Force
  已有中文简介也重新翻译。

.PARAMETER DelayMs
  每个技能之间的间隔毫秒数，默认 300，避免免费接口限流。

.PARAMETER Email
  可选。MyMemory 的匿名每日配额很低，带上邮箱（官方支持的 `de=` 参数）可显著提高额度；
  也可设环境变量 MYMEMORY_EMAIL 一劳永逸。不填则用匿名额度，超限的技能会记为失败、下次可补跑。

.EXAMPLE
  .\scripts\translate-skill-intro.ps1                  # 全库增量翻译（只补没有中文的）
  .\scripts\translate-skill-intro.ps1 -WhatIf          # 只列出将要翻译的技能，不发请求不写文件
  .\scripts\translate-skill-intro.ps1 -Name my-skill   # 只翻一个技能
  .\scripts\translate-skill-intro.ps1 -Force           # 全部重译
  .\scripts\translate-skill-intro.ps1 -Email me@x.com  # 提高免费接口每日额度
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$SharedRoot,
    [string]$Name,
    [switch]$Force,
    [int]$DelayMs = 300,
    [string]$Email,
    [int]$MaxConsecutiveFailures = 3   # 连续失败这么多就判定接口被限流，提前收工（0 = 不熔断）
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# 控制台输出强制 UTF-8，避免在 GBK 代码页下中文乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8
if (-not $Email -and $env:MYMEMORY_EMAIL) { $Email = $env:MYMEMORY_EMAIL }

# TLS 1.2（Windows PowerShell 5.1 访问 HTTPS 翻译接口必需）
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'lib\translate.ps1')

function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

# ---------- 定位共享库 ----------
if (-not $SharedRoot) {
    $cfgPath = Join-Path $PSScriptRoot '..\config\agents.json'
    if (Test-Path $cfgPath) {
        try {
            $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $SharedRoot = [string]$cfg.sharedRoot
        } catch { }
    }
    if (-not $SharedRoot) { $SharedRoot = Join-Path $env:USERPROFILE 'skills\shared' }
}
$SharedRoot = [IO.Path]::GetFullPath($SharedRoot)
if (-not (Test-Path $SharedRoot)) {
    Write-Err "共享库不存在: $SharedRoot"
    return
}

# ---------- 取待处理技能 ----------
$dirs = @(Get-ChildItem -LiteralPath $SharedRoot -Directory -Force |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
    Sort-Object Name)
if ($Name) {
    $dirs = @($dirs | Where-Object { $_.Name -eq $Name })
    if ($dirs.Count -eq 0) { Write-Err "共享库中找不到技能: $Name"; return }
}
if ($dirs.Count -eq 0) { Write-Warn '共享库里没有可处理的技能（未找到含 SKILL.md 的目录）。'; return }

Write-Host "共享技能库: $SharedRoot" -ForegroundColor Cyan
Write-Host ("待检查技能: {0} 个{1}" -f $dirs.Count, $(if ($WhatIfPreference) { '（-WhatIf 预演，不请求接口、不写文件）' } else { '' })) -ForegroundColor Cyan
Write-Host ''

$translated = 0
$skippedZh  = 0
$noDesc     = 0
$failed     = 0
$planned    = 0
$consecFail = 0
$rateLimited = $false
$i = 0

foreach ($d in $dirs) {
    $i++
    $tag = ('[{0}/{1}]' -f $i, $dirs.Count)
    $metaPath = Join-Path $d.FullName '_meta.json'

    # 读已有 _meta.json（键值顺序保留；坏文件忽略）
    $meta = [ordered]@{}
    if (Test-Path $metaPath) {
        try {
            $obj = Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $obj.PSObject.Properties) { $meta[$prop.Name] = $prop.Value }
        } catch {
            Write-Warn "$tag $($d.Name)：_meta.json 解析失败，将重建该文件的简介字段"
        }
    }

    # 取英文简介：frontmatter 优先，其次已有 _meta.json
    $fm = Read-SkillFrontmatter (Join-Path $d.FullName 'SKILL.md')
    $desc = ''
    if ($fm.Contains('description')) { $desc = [string]$fm['description'] }
    if (-not $desc -and $meta.Contains('description')) { $desc = [string]$meta['description'] }
    $desc = $desc.Trim()

    if (-not $desc) {
        $noDesc++
        Write-Host ("{0} {1,-38} 跳过：技能无简介" -f $tag, $d.Name) -ForegroundColor DarkGray
        continue
    }

    # 已有中文则跳过（-Force 时重译）
    $existingZh = ''
    if ($meta.Contains('descriptionZh')) { $existingZh = [string]$meta['descriptionZh'] }
    if (-not $Force -and (Test-HasCjk $existingZh)) {
        $skippedZh++
        Write-Host ("{0} {1,-38} 跳过：已有中文简介" -f $tag, $d.Name) -ForegroundColor DarkGray
        continue
    }
    if (-not $Force -and (Test-HasCjk $desc)) {
        $skippedZh++
        Write-Host ("{0} {1,-38} 跳过：原文已是中文" -f $tag, $d.Name) -ForegroundColor DarkGray
        continue
    }

    if ($WhatIfPreference) {
        $planned++
        Write-Host ("{0} {1,-38} 将翻译（原文 {2} 字符）" -f $tag, $d.Name, $desc.Length) -ForegroundColor Yellow
        continue
    }

    Write-Host ("{0} {1,-38} 翻译中…" -f $tag, $d.Name) -ForegroundColor Gray
    $zh = ConvertTo-DescriptionZh -Description $desc -Email $Email
    if (-not (Test-HasCjk $zh)) {
        $failed++
        $consecFail++
        Write-Host ("{0} {1,-38} 失败：接口未返回中文，保持原样" -f $tag, $d.Name) -ForegroundColor Red
        if ($MaxConsecutiveFailures -gt 0 -and $consecFail -ge $MaxConsecutiveFailures) {
            $rateLimited = $true
            Write-Warn ("连续 {0} 次失败，判定翻译接口已限流（免费接口按 IP 限每日额度），提前收工。" -f $consecFail)
            break
        }
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
        continue
    }
    $consecFail = 0

    if ($PSCmdlet.ShouldProcess($metaPath, '写入中文简介')) {
        if (-not $meta.Contains('name') -or -not $meta['name']) { $meta['name'] = $d.Name }
        $meta['description']   = $desc
        $meta['descriptionZh'] = $zh
        $meta['translatedAt']  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $meta | ConvertTo-Json -Depth 3 | Out-File -FilePath $metaPath -Encoding UTF8
        $translated++
        Write-Host ("{0} {1,-38} 已翻译（{2} 字）" -f $tag, $d.Name, $zh.Length) -ForegroundColor Green
    } else {
        $planned++
        Write-Host ("{0} {1,-38} 未写入（已跳过）" -f $tag, $d.Name) -ForegroundColor Yellow
    }

    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

# ---------- 汇总 ----------
Write-Host ''
Write-Host '========== 翻译结果 ==========' -ForegroundColor Cyan
Write-Host ("已处理技能: {0} / {1} 个" -f $i, $dirs.Count) -ForegroundColor White
Write-Host ("已翻译写入: {0} 个" -f $translated) -ForegroundColor Green
if ($skippedZh -gt 0) { Write-Host ("跳过（已有中文）: {0} 个" -f $skippedZh) -ForegroundColor DarkGray }
if ($noDesc -gt 0)    { Write-Host ("跳过（技能无简介）: {0} 个" -f $noDesc) -ForegroundColor DarkGray }
if ($planned -gt 0)   { Write-Host ("未写入（-WhatIf 预演）: {0} 个" -f $planned) -ForegroundColor Yellow }
if ($failed -gt 0)    { Write-Host ("翻译失败: {0} 个（可稍后重跑本脚本补齐）" -f $failed) -ForegroundColor Red }
if ($rateLimited) {
    Write-Host '本次因接口限流提前结束，剩余技能未处理（不影响已写入的结果）。' -ForegroundColor Yellow
    Write-Host '免费接口按 IP 限每日额度；提高额度：-Email 你的邮箱，或设环境变量 MYMEMORY_EMAIL。' -ForegroundColor DarkGray
}

if ($translated -gt 0) {
    Write-Host ''
    Write-Host '中文简介已写入各技能的 _meta.json（原有 source / commitSha 等字段保留）。' -ForegroundColor DarkGray
    Write-Host '如需「总路由技能」索引也显示中文简介，再跑一次：.\scripts\generate-router-skill.ps1' -ForegroundColor DarkGray
}
if ($failed -gt 0) {
    Write-Host '失败通常是免费接口限流或网络不可达，隔几分钟重跑即可（已翻译的会自动跳过）。' -ForegroundColor DarkGray
}
