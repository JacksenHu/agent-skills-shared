#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 交互式控制台：首页菜单选择，覆盖搭建、验证、技能管理与仓库安装

.DESCRIPTION
  全程交互，无需手写 JSON。主菜单：
    [1] 快速搭建 —— 配置 Agent 并建立共享联接（自动迁移已有技能、智能去重）
    [2] 验证所有 Agent 联接
    [3] 技能管理（列出含中文简介 / 从 GitHub、skills.sh 安装 / 移除）
    [4] 接入 / 移除单个 Agent
    [5] 扫描各 Agent 已安装技能（发现未进共享库的技能）
    [6] 帮助与文档
    [0] 退出

  快速搭建内置 11 个常见 Agent 技能路径预设（Doubao、Claude Code、Codex、
  Cursor、Windsurf、OpenClaw、Trae、Trae CN、GitHub Copilot、Zed 等，
  均来自官方文档），自动探测本机状态，输入 d 一键全选已检测到的。

.EXAMPLE
  .\scripts\setup-wizard.ps1          # 启动交互控制台
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\agents.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$setupScript      = Join-Path $PSScriptRoot 'setup.ps1'
$verifyScript     = Join-Path $PSScriptRoot 'verify.ps1'
$addAgentScript   = Join-Path $PSScriptRoot 'add-agent.ps1'
$removeAgentScript= Join-Path $PSScriptRoot 'remove-agent.ps1'
$installScript    = Join-Path $PSScriptRoot 'install-skill.ps1'

# ---------- 输出辅助 ----------
function Write-Info { param([string]$Msg) Write-Host $Msg -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[!] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[X] $Msg" -ForegroundColor Red }

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
    param([int]$Count, [string]$Prompt, [bool[]]$Detected)
    while ($true) {
        $raw = (Read-Host $Prompt).Trim().ToLower()
        if ($raw -eq '' -or $raw -eq 'q') { return @() }
        if ($raw -eq 'a') { return @(1..$Count) }
        if ($raw -eq 'd') {
            # 一键全选"已检测到"的条目
            return @(0..($Count - 1) | Where-Object { $Detected[$_] } | ForEach-Object { $_ + 1 })
        }
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
        Write-Warn "输入无效，请输入 1-$Count 的编号（逗号分隔多选）、d=全选已检测到、a=全部或 q。"
    }
}

function Get-SharedRoot {
    if (Test-Path $ConfigPath) {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [IO.Path]::GetFullPath([string]$cfg.sharedRoot)
    }
    return $null
}

# ---------- 技能管理 ----------
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

function Get-SkillIntro {
    # 返回技能的中文简介：优先 _meta.json（安装时生成），否则读 SKILL.md 的 description
    param([string]$SkillDir)
    $metaFile = Join-Path $SkillDir '_meta.json'
    if (Test-Path $metaFile) {
        try {
            $m = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($m.descriptionZh) { return [string]$m.descriptionZh }
            if ($m.description)  { return [string]$m.description }
        } catch { }
    }
    $md = Join-Path $SkillDir 'SKILL.md'
    if (Test-Path $md) {
        $fm = Read-SkillFrontmatter $md
        $d = [string]$fm['description']
        if ($d) { return $d }
    }
    return '（无简介）'
}

function Show-SkillList {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot -or -not (Test-Path $sharedRoot)) {
        Write-Warn '共享库不存在。请先执行 [1] 快速搭建，或检查配置。'
        return
    }
    $skills = @(Get-ChildItem $sharedRoot -Directory -Force | Where-Object { $_.Name -ne '_meta.json' })
    if ($skills.Count -eq 0) { Write-Warn "共享库为空: $sharedRoot"; return }
    Write-Info "共享库技能清单（$($skills.Count) 个）：$sharedRoot"
    foreach ($s in $skills | Sort-Object Name) {
        $count = @(Get-ChildItem $s.FullName -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue).Count
        $intro = Get-SkillIntro $s.FullName
        if ($intro.Length -gt 60) { $intro = $intro.Substring(0, 60) + '…' }
        Write-Host ("  - {0}  ({1} 个 SKILL.md)  {2}" -f $s.Name, $count, $intro)
    }
}

function Remove-SkillInteractive {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot -or -not (Test-Path $sharedRoot)) {
        Write-Warn '共享库不存在。请先执行 [1] 快速搭建。'
        return
    }
    $skills = @(Get-ChildItem $sharedRoot -Directory -Force | Sort-Object Name)
    if ($skills.Count -eq 0) { Write-Warn '共享库为空。'; return }

    Write-Info "请选择要移除的技能（1-$($skills.Count)）："
    for ($i = 0; $i -lt $skills.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $skills[$i].Name)
    }
    $n = 0
    while ($true) {
        $raw = (Read-Host '  输入编号').Trim()
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $skills.Count) { $n = [int]$raw; break }
        Write-Warn "请输入 1-$($skills.Count) 的编号。"
    }
    $skill = $skills[$n - 1]
    $target = $skill.FullName
    Write-Warn "即将移除：$target"
    Write-Warn '⚠ 移除会删除共享库中的该技能，影响所有已接入的 Agent！'
    if (-not (Read-YesNo '确认删除？' $false)) { Write-Host '已取消。'; return }
    $confirm = (Read-Host "请再次输入技能名 [$($skill.Name)] 以确认").Trim()
    if ($confirm -ne $skill.Name) { Write-Warn '输入不一致，已取消。'; return }
    Remove-Item $target -Recurse -Force
    Write-Ok "已移除技能: $($skill.Name)"
}

function Install-SkillInteractive {
    Write-Info '从 GitHub / skills.sh 仓库安装技能'
    Write-Host '  示例：https://github.com/hgta23/findskills'
    Write-Host '        https://skills.sh/s/vercel-labs/skills/find-skills'
    $url = (Read-Host '  输入仓库链接（q 取消）').Trim()
    if ($url -eq '' -or $url -eq 'q') { Write-Host '已取消。'; return }
    & $installScript -RepoUrl $url
    Write-Host ''
}

# ---------- 接入 / 移除 Agent ----------
function Add-AgentInteractive {
    $name = (Read-Host '  输入 Agent 名称（如 myagent，q 取消）').Trim()
    if ($name -eq '' -or $name -eq 'q') { Write-Host '已取消。'; return }
    $path = (Read-Host '  输入其技能根目录完整路径').Trim()
    if ($path -eq '') { Write-Warn '路径为空，已取消。'; return }
    & $addAgentScript -AgentName $name -RootPath $path
    Write-Host ''
    Write-Host '提示：可用 [1] 快速搭建把该路径一并写入 config\agents.json，便于统一巡检。' -ForegroundColor Cyan
}

function Remove-AgentInteractive {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot) { Write-Warn '没有配置，无法判断。请先 [1] 快速搭建。'; return }
    $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agents = @($cfg.agents.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Path = [string]$_.Value }
    } | Sort-Object Name)
    if ($agents.Count -eq 0) { Write-Warn '配置中没有 Agent。'; return }

    Write-Info "当前已配置的 Agent："
    for ($i = 0; $i -lt $agents.Count; $i++) {
        Write-Host ("  [{0}] {1}  ->  {2}" -f ($i + 1), $agents[$i].Name, $agents[$i].Path)
    }
    $n = 0
    while ($true) {
        $raw = (Read-Host '  输入要移除的编号（q 取消）').Trim()
        if ($raw -eq 'q') { return }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $agents.Count) { $n = [int]$raw; break }
        Write-Warn "请输入 1-$($agents.Count) 的编号。"
    }
    $target = $agents[$n - 1]
    if (-not (Read-YesNo "移除 $($target.Name) 的联接？（数据仍在共享库，不删除）" $false)) { return }
    & $removeAgentScript -AgentName $target.Name -RootPath $target.Path
    Write-Host ''
}

# ---------- 快速搭建（引导生成配置） ----------
function Invoke-SetupFlow {
    $useExisting = $false
    if (Test-Path $ConfigPath) {
        Write-Warn "检测到已有配置：$ConfigPath"
        $useExisting = Read-YesNo '直接沿用现有配置搭建/验证？' $true
    }

    if (-not $useExisting) {
        Write-Info '[1/3] 共享技能库位置'
        $defaultShared = Join-Path $env:USERPROFILE 'skills\shared'
        Write-Host "  默认：$defaultShared"
        $in = (Read-Host '  回车使用默认，或输入其他路径').Trim()
        $sharedRoot = if ($in) { [IO.Path]::GetFullPath($in) } else { $defaultShared }

        Write-Info '[2/3] 选择要接入的 Agent（已预设常见 Agent 路径，自动探测本机状态）'
        $detectors = @(
            @{ Key = 'doubao-user-skills'; Label = 'Doubao（豆包）用户技能'; Path = (Join-Path $env:LOCALAPPDATA 'Doubao\User Data\Default\.doubao\agent_mode\workspace\.user_skills') },
            @{ Key = 'doubao-extra';        Label = 'Doubao（豆包）其他技能根'; Path = (Join-Path $env:USERPROFILE 'Doubao\skills') },
            @{ Key = 'claude-code';         Label = 'Claude Code';             Path = (Join-Path $env:USERPROFILE '.claude\skills') },
            @{ Key = 'codex-agents-skills'; Label = 'Codex / Cursor / Zed / Copilot（.agents 通用）'; Path = (Join-Path $env:USERPROFILE '.agents\skills') },
            @{ Key = 'codex-legacy';        Label = 'Codex 旧版';              Path = (Join-Path $env:USERPROFILE '.codex\skills') },
            @{ Key = 'cursor';              Label = 'Cursor（独立目录）';      Path = (Join-Path $env:USERPROFILE '.cursor\skills') },
            @{ Key = 'windsurf';            Label = 'Windsurf';                Path = (Join-Path $env:USERPROFILE '.codeium\windsurf\skills') },
            @{ Key = 'openclaw';            Label = 'OpenClaw';                Path = (Join-Path $env:USERPROFILE '.openclaw\workspace\skills') },
            @{ Key = 'trae';                Label = 'Trae（国际版）';          Path = (Join-Path $env:USERPROFILE '.trae\skills') },
            @{ Key = 'trae-cn';             Label = 'Trae CN（国内版）';       Path = (Join-Path $env:USERPROFILE '.trae-cn\skills') },
            @{ Key = 'copilot';             Label = 'GitHub Copilot';          Path = (Join-Path $env:USERPROFILE '.copilot\skills') }
        )
        $choices = @()
        $detectedFlags = @()
        for ($i = 0; $i -lt $detectors.Count; $i++) {
            $d = $detectors[$i]
            $exists = Test-Path $d.Path
            $mark = if ($exists) { '✅ 已检测到' } else { '　未找到　' }
            Write-Host ("  [{0}] {1,-40} {2}  {3}" -f ($i + 1), $d.Label, $mark, $d.Path)
            $choices += [pscustomobject]@{ Key = $d.Key; Path = $d.Path }
            $detectedFlags += $exists
        }
        $sel = Read-ChoiceList $choices.Count '  输入编号接入（逗号分隔多选，d=全选已检测到，a=全部，q=跳过）' $detectedFlags

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
            return
        }

        Write-Info '[3/3] 确认配置'
        Write-Host "  共享库：$sharedRoot"
        foreach ($a in $agentList) {
            Write-Host ("    {0} -> {1}" -f $a.Name, $a.Path)
        }
        if (-not (Read-YesNo '确认无误，写入配置并开始搭建？' $true)) {
            Write-Host '已取消，未做任何修改。'
            return
        }

        $agents = [ordered]@{}
        foreach ($a in $agentList) { $agents[$a.Name] = $a.Path }
        $cfg = [ordered]@{ sharedRoot = $sharedRoot; agents = $agents }
        $configDir = Split-Path $ConfigPath -Parent
        if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
        $cfg | ConvertTo-Json -Depth 4 | Out-File -FilePath $ConfigPath -Encoding UTF8
        Write-Ok "已写入配置：$ConfigPath"
    }

    Write-Host ''
    Write-Host '--- 开始搭建（setup.ps1）---' -ForegroundColor Cyan
    & $setupScript -ConfigPath $ConfigPath
    Write-Host ''
    Write-Host '--- 开始验证（verify.ps1）---' -ForegroundColor Cyan
    & $verifyScript -ConfigPath $ConfigPath
    Write-Host ''
    Write-Ok '搭建完成！请重启各 Agent 会话（新开会话）使技能生效。'
}

# ---------- 帮助 ----------
function Show-Help {
    Write-Info '帮助与文档'
    Write-Host @'
  仓库（含全部文档与图解）：
    https://github.com/JacksenHu/agent-skills-shared

  文档：
    docs/01-architecture.md           方案原理
    docs/02-agent-path-reference.md   各 Agent 技能目录速查
    docs/03-setup-guide.md            搭建指南
    docs/04-day-to-day.md             日常使用（新增/更新/删除技能、增删 Agent）
    docs/05-safety-and-rollback.md    风险与回滚
    docs/06-faq.md                    常见问题

  常用命令：
    快速搭建（非交互）  .\scripts\setup.ps1
    验证                .\scripts\verify.ps1
    扫描 Agent 技能     .\scripts\scan-agents.ps1
    接入 Agent          .\scripts\add-agent.ps1 -AgentName 名称 -RootPath 路径
    移除 Agent          .\scripts\remove-agent.ps1 -AgentName 名称 -RootPath 路径
    安装技能（仓库链接）.\scripts\install-skill.ps1 -RepoUrl https://github.com/owner/repo
    安装技能（skills.sh）.\scripts\install-skill.ps1 -RepoUrl https://skills.sh/s/owner/repo

  提示：
    - 迁移/去重/冲突策略见 setup.ps1 输出与 docs/05
    - 仓库链接安装到共享库后，重启各 Agent 会话生效
    - 在 Agent 内手动安装的技能会落在该 Agent 目录，可用 [5] 扫描发现并迁移
'@
    Write-Host ''
}

# ---------- 主菜单 ----------
function Show-MainMenu {
    while ($true) {
        Write-Host ''
        Write-Host '============================================' -ForegroundColor Cyan
        Write-Host '  统一技能库 · 管理控制台' -ForegroundColor White
        Write-Host '  一套技能，只装一次，所有 Agent 共用' -ForegroundColor White
        Write-Host '============================================' -ForegroundColor Cyan
        Write-Host '  [1] 快速搭建（配置 + 迁移 + 建立联接）'
        Write-Host '  [2] 验证所有 Agent 联接'
        Write-Host '  [3] 技能管理'
        Write-Host '  [4] 接入 / 移除 Agent'
        Write-Host '  [5] 扫描各 Agent 已安装技能（发现未进共享库的技能）'
        Write-Host '  [6] 帮助与文档'
        Write-Host '  [0] 退出'
        Write-Host ''
        $choice = (Read-Host '  请选择 [0-6]').Trim()

        switch ($choice) {
            '1' { Invoke-SetupFlow }
            '2' {
                if (-not (Test-Path $ConfigPath)) { Write-Warn '还没有配置。请先 [1] 快速搭建。' }
                else { & $verifyScript -ConfigPath $ConfigPath }
            }
            '3' {
                while ($true) {
                    Write-Host ''
                    Write-Info '── 技能管理 ──'
                    Write-Host '  [a] 列出共享库中的技能（含中文简介）'
                    Write-Host '  [b] 从 GitHub / skills.sh 仓库安装技能'
                    Write-Host '  [c] 移除共享库中的技能'
                    Write-Host '  [q] 返回主菜单'
                    $sub = (Read-Host '  请选择').Trim().ToLower()
                    if ($sub -eq 'q' -or $sub -eq '') { break }
                    switch ($sub) {
                        'a' { Show-SkillList; Write-Host '' }
                        'b' { Install-SkillInteractive }
                        'c' { Remove-SkillInteractive; Write-Host '' }
                        default { Write-Warn '无效选项。' }
                    }
                }
            }
            '4' {
                while ($true) {
                    Write-Host ''
                    Write-Info '── 接入 / 移除 Agent ──'
                    Write-Host '  [a] 接入新 Agent（建联接，数据自动迁移）'
                    Write-Host '  [b] 移除 Agent（拆联接，数据保留在共享库）'
                    Write-Host '  [q] 返回主菜单'
                    $sub = (Read-Host '  请选择').Trim().ToLower()
                    if ($sub -eq 'q' -or $sub -eq '') { break }
                    switch ($sub) {
                        'a' { Add-AgentInteractive }
                        'b' { Remove-AgentInteractive }
                        default { Write-Warn '无效选项。' }
                    }
                }
            }
            '5' {
                if (-not (Test-Path $ConfigPath)) { Write-Warn '还没有配置。请先 [1] 快速搭建。' }
                else { & (Join-Path $PSScriptRoot 'scan-agents.ps1') -ConfigPath $ConfigPath }
            }
            '6' { Show-Help }
            '0' { Write-Ok '再见！'; return }
            default { Write-Warn '无效选项，请输入 0-6。' }
        }
    }
}

Show-MainMenu
