#requires -Version 5.1
<#
.SYNOPSIS
  统一技能库 · 管理控制台（专业版界面）

.DESCRIPTION
  全程交互，无需手写 JSON。主菜单：
    [1] 快速搭建 —— 配置 Agent 并建立共享联接（自动迁移已有技能、智能去重）
    [2] 验证联接 —— 检查所有 Agent 的技能可见性
    [3] 技能管理 —— 分类清单 / GitHub、skills.sh 仓库安装 / 移除 / 分类浏览
    [4] 接入 / 移除 Agent
    [5] 扫描已装技能 —— 发现各 Agent 中未进共享库的技能
    [6] 检查版本更新 —— 对比 GitHub 仓库最新提交，可选自动升级
    [7] 帮助与文档
    [0] 退出

  界面特性：
    - Windows 10+ 虚拟终端（VT）真彩色渐变标题、双线框面板、状态栏
    - 自动探测终端能力：不支持 ANSI 时降级为 16 色，功能不受影响
    - 首次启动自动在桌面创建「统一技能库管理」快捷方式（已存在则跳过）

.EXAMPLE
  .\scripts\setup-wizard.ps1          # 启动交互控制台
#>
[CmdletBinding()]
param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

$setupScript      = Join-Path $PSScriptRoot 'setup.ps1'
$verifyScript     = Join-Path $PSScriptRoot 'verify.ps1'
$addAgentScript   = Join-Path $PSScriptRoot 'add-agent.ps1'
$removeAgentScript= Join-Path $PSScriptRoot 'remove-agent.ps1'
$installScript    = Join-Path $PSScriptRoot 'install-skill.ps1'
$checkUpdatesScript = Join-Path $PSScriptRoot 'check-updates.ps1'

# =====================================================================
#  终端美化层
# =====================================================================
$script:E = [char]27          # ESC
$script:Ansi = $false         # 是否启用真彩色 VT

# 语义调色板：rgb = 真彩色三元组；c16 = 16 色降级名
$script:Palette = @{
    primary = @{ rgb = @(14, 165, 233);    c16 = 'Cyan' }      # 主蓝
    accent  = @{ rgb = @(56, 189, 248);    c16 = 'Cyan' }      # 亮蓝
    ok      = @{ rgb = @(16, 185, 129);    c16 = 'Green' }     # 绿
    warn    = @{ rgb = @(245, 158, 11);    c16 = 'Yellow' }    # 琥珀
    err     = @{ rgb = @(239, 68, 68);     c16 = 'Red' }       # 红
    text    = @{ rgb = @(226, 232, 240);   c16 = 'White' }     # 正文
    dim     = @{ rgb = @(148, 163, 184);   c16 = 'DarkGray' }  # 次要
    faint   = @{ rgb = @(100, 116, 139);   c16 = 'DarkGray' }  # 更弱
    border  = @{ rgb = @(71, 85, 105);     c16 = 'DarkGray' }  # 边框
    gold    = @{ rgb = @(251, 191, 36);    c16 = 'Yellow' }    # 金
    white   = @{ rgb = @(248, 250, 252);   c16 = 'White' }
}

# 尝试启用 Windows 10+ 虚拟终端（真彩色）；失败则降级 16 色
function Initialize-Ansi {
    try {
        if (-not ('Uni.VT' -as [type])) {
            $sig = @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
            Add-Type -MemberDefinition $sig -Name 'VT' -Namespace 'Uni' -ErrorAction Stop
        }
        $t = 'Uni.VT' -as [type]
        $h = $t::GetStdHandle(-11)                    # STD_OUTPUT_HANDLE
        $m = [uint32]0
        if ($t::GetConsoleMode($h, [ref]$m)) {
            $ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
            if ($t::SetConsoleMode($h, $m -bor $ENABLE_VIRTUAL_TERMINAL_PROCESSING)) {
                $script:Ansi = $true
            }
        }
    } catch {
        $script:Ansi = $false
    }
    if ($script:Ansi) {
        try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    }
}

# 带样式的文本输出：-C 语义色名，-Bold 加粗（仅 ANSI），-NoNewline
function Write-C {
    param(
        [string]$Text,
        [string]$C = 'text',
        [switch]$Bold,
        [switch]$NoNewline
    )
    $p = $script:Palette[$C]
    if (-not $p) { $p = $script:Palette['text'] }
    if ($script:Ansi) {
        $b = if ($Bold) { '1;' } else { '' }
        $s = "$($script:E)[${b}38;2;$($p.rgb[0]);$($p.rgb[1]);$($p.rgb[2])m$Text$($script:E)[0m"
        if ($NoNewline) { [Console]::Write($s) } else { [Console]::WriteLine($s) }
    } else {
        if ($NoNewline) { Write-Host -NoNewline $Text -ForegroundColor $p.c16 }
        else { Write-Host $Text -ForegroundColor $p.c16 }
    }
}

# 显示宽度（CJK / 全角按 2 计算），用于对齐
function Get-Width {
    param([string]$Text)
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        $wide = ($code -ge 0x1100 -and $code -le 0x115F) -or
                ($code -ge 0x2E80 -and $code -le 0xA4CF -and $code -ne 0x303F) -or
                ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE10 -and $code -le 0xFE6F) -or
                ($code -ge 0xFF00 -and $code -le 0xFF60) -or
                ($code -ge 0xFFE0 -and $code -le 0xFFE6)
        if ($wide) { $w += 2 } else { $w += 1 }
    }
    return $w
}

# 右补空格到目标宽度
function Pad-Width {
    param([string]$Text, [int]$Width)
    $pad = $Width - (Get-Width $Text)
    if ($pad -lt 0) { $pad = 0 }
    return ($Text + (' ' * $pad))
}

# 截断到目标宽度（加省略号）
function Truncate-Width {
    param([string]$Text, [int]$Width)
    if ((Get-Width $Text) -le $Width) { return $Text }
    $out = ''
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $cw = if ([int]$ch -ge 0x1100) { 2 } else { 1 }
        if ($w + $cw -gt $Width - 1) { break }
        $out += $ch
        $w += $cw
    }
    return ($out + '…')
}

# 语义输出快捷方式
function Write-Info { param([string]$Msg) Write-C "▸ $Msg" -C primary -Bold }
function Write-Ok   { param([string]$Msg) Write-C "✔ $Msg" -C ok -Bold }
function Write-Warn { param([string]$Msg) Write-C "⚠ $Msg" -C warn }
function Write-Err  { param([string]$Msg) Write-C "✘ $Msg" -C err -Bold }

# ---------- 框线面板 ----------
$script:BoxW = 74   # 框内内容宽度

function Show-BoxTop {
    param([string]$Title = '', [string]$C = 'border')
    if ($Title) {
        $t = "─ $Title "
        $dash = $script:BoxW - (Get-Width $t)
        Write-C ("╔" + $t + ('─' * $dash) + "╗") -C $C
    } else {
        Write-C ("╔" + ('═' * $script:BoxW) + "╗") -C $C
    }
}

function Show-BoxMid {
    Write-C ("╠" + ('═' * $script:BoxW) + "╣") -C border
}

function Show-BoxBottom {
    Write-C ("╚" + ('═' * $script:BoxW) + "╝") -C border
}

function Show-BoxRow {
    param([string]$Text = '', [string]$C = 'text', [switch]$Bold)
    $safe = Truncate-Width $Text ($script:BoxW - 4)
    Write-C ("║  " + (Pad-Width $safe ($script:BoxW - 4)) + "  ║") -C $C -Bold:$Bold
}

function Show-BoxRowColor {
    # 支持分段上色的行：segments = @(@{T='文本';C='色';B=$true}, ...)
    # 超出框宽时按顺序截断，保证边框完整
    param([object[]]$Segments)
    $maxW = $script:BoxW - 2
    $plan = @()
    $used = 0
    $done = $false
    foreach ($seg in $Segments) {
        if ($done) { break }
        $t = [string]$seg['T']
        $c = if ($seg.ContainsKey('C')) { [string]$seg['C'] } else { 'text' }
        $b = $false
        if ($seg.ContainsKey('B') -and $seg['B']) { $b = $true }
        $tw = Get-Width $t
        $remaining = $maxW - $used
        if ($tw -le $remaining) {
            $plan += @{ T = $t; C = $c; B = $b }
            $used += $tw
        } else {
            if ($remaining -gt 0) {
                $plan += @{ T = (Truncate-Width $t $remaining); C = $c; B = $b }
                $used += $remaining
            }
            $done = $true
        }
    }
    # 分段着色输出
    Write-C ("║  ") -C border -NoNewline
    foreach ($p in $plan) {
        Write-C $p.T -C $p.C -Bold:$p.B -NoNewline
    }
    Write-C ((' ' * ($maxW - $used)) + "  ║") -C border
}

function Show-BoxBlank {
    Write-C ("║" + (' ' * $script:BoxW) + "║") -C border
}

# 渐变着色文本（ANSI 下从亮蓝渐变到深蓝；降级为纯文本）
function Get-GradientText {
    param([string]$Text)
    if (-not $script:Ansi) { return $Text }
    $chars = $Text.ToCharArray()
    $n = $chars.Count
    $out = ''
    for ($i = 0; $i -lt $n; $i++) {
        $t = if ($n -gt 1) { $i / ($n - 1) } else { 0 }
        $r = [int](125 + (14 - 125) * $t)
        $g = [int](211 + (165 - 211) * $t)
        $b = [int](252 + (233 - 252) * $t)
        $out += "$($script:E)[1;38;2;$r;$g;${b}m$($chars[$i])"
    }
    return $out + "$($script:E)[0m"
}

# ---------- Banner ----------
function Show-Banner {
    Write-C ("╔" + ('═' * $script:BoxW) + "╗") -C primary
    Write-C ("║" + (' ' * $script:BoxW) + "║") -C primary
    $title = '统一技能库 · 管理控制台'
    $titleW = Get-Width $title
    $padL = [int](($script:BoxW - 2 - $titleW) / 2)
    $padR = $script:BoxW - 2 - $padL - $titleW
    if ($script:Ansi) {
        Write-C ("║" + (' ' * $padL)) -C primary -NoNewline
        [Console]::Write((Get-GradientText $title))
        Write-C ((' ' * $padR) + "  ║") -C primary
    } else {
        Write-C ("║" + (' ' * $padL) + $title + (' ' * $padR) + "  ║") -C primary -Bold
    }
    Write-C ("║" + (' ' * $script:BoxW) + "║") -C primary
    $sub = 'UNIFIED SKILLS HUB'
    $padL2 = [int](($script:BoxW - 2 - $sub.Length) / 2)
    Write-C ("║" + (' ' * $padL2) + $sub + (' ' * ($script:BoxW - 2 - $padL2 - $sub.Length)) + "  ║") -C accent
    Write-C ("║" + (' ' * $script:BoxW) + "║") -C primary
    $tag = '一套技能 · 只装一次 · 所有 Agent 共用'
    $tagW = Get-Width $tag
    $padL3 = [int](($script:BoxW - 2 - $tagW) / 2)
    Write-C ("║" + (' ' * $padL3) + $tag + (' ' * ($script:BoxW - 2 - $padL3 - $tagW)) + "  ║") -C dim
    Write-C ("╚" + ('═' * $script:BoxW) + "╝") -C primary
    Write-C ''
}

# ---------- 状态栏 ----------
function Get-StatusText {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot) { return '未配置 · 请先执行 [1] 快速搭建' }
    $skillCount = 0
    $agentCount = 0
    if (Test-Path $sharedRoot) {
        $skillCount = @(Get-ChildItem $sharedRoot -Directory -Force | Where-Object { $_.Name -ne '_meta.json' }).Count
    }
    if (Test-Path $ConfigPath) {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $agentCount = @($cfg.agents.PSObject.Properties).Count
    }
    # 路径精简：保留末两段
    $short = $sharedRoot
    $parts = $sharedRoot.TrimEnd('\') -split '\\'
    if ($parts.Count -gt 2) { $short = '…\' + ($parts[-2]) + '\' + ($parts[-1]) }
    return ("共享库 {0}  ·  {1} 个技能  ·  {2} 个 Agent" -f $short, $skillCount, $agentCount)
}

function Show-StatusBar {
    $status = Get-StatusText
    Show-BoxTop '状态' ok
    Show-BoxRow $status dim
    Show-BoxBottom ok
}

# ---------- 输入辅助 ----------
function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-C ("? " + $Prompt + "  ") -C text -NoNewline
        Write-C $suffix -C dim -NoNewline
        Write-C '  > ' -C primary -NoNewline
        $raw = (Read-Host).Trim().ToLower()
        if ($raw -eq '') { return $Default }
        if ($raw -in @('y', 'yes')) { return $true }
        if ($raw -in @('n', 'no')) { return $false }
        Write-Err '请输入 y 或 n。'
    }
}

function Read-ChoiceList {
    param([int]$Count, [string]$Prompt, [bool[]]$Detected)
    while ($true) {
        Write-C ("? " + $Prompt + "  ") -C text -NoNewline
        Write-C '> ' -C primary -NoNewline
        $raw = (Read-Host).Trim().ToLower()
        if ($raw -eq '' -or $raw -eq 'q') { return @() }
        if ($raw -eq 'a') { return @(1..$Count) }
        if ($raw -eq 'd') {
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
        Write-Err "输入无效，请输入 1-$Count 的编号（逗号分隔多选）、d=全选已检测到、a=全部或 q。"
    }
}

function Get-SharedRoot {
    if (Test-Path $ConfigPath) {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [IO.Path]::GetFullPath([string]$cfg.sharedRoot)
    }
    return $null
}

# =====================================================================
#  技能管理数据层
# =====================================================================
function Read-SkillFrontmatter {
    param([string]$SkillMdPath)
    $text = Get-Content $SkillMdPath -Raw -Encoding UTF8
    $m = [regex]::Match($text, '(?s)^---\s*\r?\n(.*?)\r?\n---')
    $meta = [ordered]@{}
    if ($m.Success) {
        $lines = $m.Groups[1].Value -split "`r?`n"
        $i = 0
        while ($i -lt $lines.Count) {
            $line = $lines[$i]
            $kv = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$')
            if ($kv.Success) {
                $key = $kv.Groups[1].Value
                $val = $kv.Groups[2].Value.Trim().Trim('"').Trim("'")
                if ($val -match '^[>|][+-]?$') {
                    $i++
                    $chunks = @()
                    while ($i -lt $lines.Count -and $lines[$i] -match '^\s+\S') {
                        $chunks += $lines[$i].Trim()
                        $i++
                    }
                    $meta[$key] = ($chunks -join ' ')
                    continue
                }
                $meta[$key] = $val
            }
            $i++
        }
    }
    return $meta
}

function Get-SkillIntro {
    param([string]$SkillDir)
    $metaFile = Join-Path $SkillDir '_meta.json'
    if (Test-Path $metaFile) {
        try {
            $m = Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $zh = $m.PSObject.Properties['descriptionZh']
            if ($zh -and $zh.Value) { return [string]$zh.Value }
            $en = $m.PSObject.Properties['description']
            if ($en -and $en.Value) { return [string]$en.Value }
        } catch { }
    }
    $md = Join-Path $SkillDir 'SKILL.md'
    if (Test-Path $md) {
        $fm = Read-SkillFrontmatter $md
        $d = [string]$fm['description']
        if ($d) { return $d }
    }
    return ''
}

# 技能自动分类关键词词典
$script:CategoryDefs = @(
    @{ Name = '开发与工程'; Keywords = @('test', 'debug', 'coding', 'code', 'review', 'git', 'commit', 'refactor', 'typescript', 'python', 'react', 'frontend', 'backend', 'programming', 'lint', '开发', '测试', '调试', '代码', '审查', '编程', '工程', '重构', '构建') },
    @{ Name = '写作与内容'; Keywords = @('write', 'writing', 'article', 'blog', 'copywriting', 'content', 'essay', 'translate', '写作', '文章', '文案', '内容', '公众号', '小红书', '新媒体', '博客', '润色', '翻译') },
    @{ Name = '研究与搜索'; Keywords = @('research', 'search', 'investigate', 'literature', 'paper', '学术', '研究', '调研', '搜索', '论文', '文献', '查证') },
    @{ Name = '办公与效率'; Keywords = @('productivity', 'meeting', 'summary', 'summariz', 'document', 'excel', 'sheet', 'ppt', 'presentation', 'calendar', 'task', 'todo', 'email', '会议', '纪要', '文档', '效率', '办公', '任务', '日程', '邮件', '表格') },
    @{ Name = '数据分析'; Keywords = @('data', 'analysis', 'analytic', 'statistic', 'dashboard', '数据', '分析', '统计', '图表', '可视化', '报表') },
    @{ Name = '设计与创意'; Keywords = @('design', 'image', 'poster', 'banner', 'logo', 'illustration', '设计', '图片', '海报', '插画', '视觉', '封面', '创意') },
    @{ Name = '音视频与媒体'; Keywords = @('video', 'audio', 'media', 'podcast', '视频', '音频', '剪辑', '字幕', '配音', '媒体') },
    @{ Name = 'Agent 与技能管理'; Keywords = @('agent', 'skill', 'mcp', 'prompt', 'claude', '智能体', '技能', '安装', '模型') },
    @{ Name = '生活与日常'; Keywords = @('life', 'health', 'travel', 'food', 'fitness', '生活', '健康', '旅行', '美食', '健身', '养生', '菜谱') }
)

function Test-SkillKeyword {
    param([string]$Text, [string]$Keyword)
    if ($Keyword -match '^[\u4e00-\u9fff]') { return $Text.Contains($Keyword) }
    return ($Text -match ("\b" + [regex]::Escape($Keyword) + "\b"))
}

function Get-SkillCategory {
    param([string]$SkillDir, [string]$Name, [string]$Description)
    $md = Join-Path $SkillDir 'SKILL.md'
    if (Test-Path $md) {
        $fm = Read-SkillFrontmatter $md
        foreach ($f in @('category', 'type', 'tags')) {
            $v = [string]$fm[$f]
            if ($v) {
                $vLower = $v.ToLower()
                foreach ($c in $script:CategoryDefs) {
                    if ($vLower -eq $c.Name.ToLower()) { return $c.Name }
                }
                foreach ($c in $script:CategoryDefs) {
                    foreach ($k in $c.Keywords) {
                        if (Test-SkillKeyword $vLower $k) { return $c.Name }
                    }
                }
            }
        }
    }
    $text = "$Name $Description".ToLower()
    foreach ($c in $script:CategoryDefs) {
        foreach ($k in $c.Keywords) {
            if (Test-SkillKeyword $text $k) { return $c.Name }
        }
    }
    return '未分类'
}

function Get-SkillListWithCategory {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot -or -not (Test-Path $sharedRoot)) { return $null }
    $skills = @(Get-ChildItem $sharedRoot -Directory -Force | Where-Object { $_.Name -ne '_meta.json' })
    $result = @()
    foreach ($s in $skills | Sort-Object Name) {
        $count = @(Get-ChildItem $s.FullName -Recurse -File -Filter 'SKILL.md' -ErrorAction SilentlyContinue).Count
        $intro = Get-SkillIntro $s.FullName
        $cat = Get-SkillCategory $s.FullName $s.Name $intro
        $result += [pscustomobject]@{ Name = $s.Name; Count = $count; Intro = $intro; Category = $cat }
    }
    return $result
}

function Get-CategoryOrder {
    # 未分类放最后，其余按技能数降序
    param($List)
    $groups = $List | Group-Object Category
    return @($groups | Sort-Object @{ Expression = { if ($_.Name -eq '未分类') { -1 } else { $_.Count } }; Descending = $true })
}

# =====================================================================
#  技能管理界面
# =====================================================================
function Show-SkillList {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot -or -not (Test-Path $sharedRoot)) {
        Write-Warn '共享库不存在。请先执行 [1] 快速搭建，或检查配置。'
        return
    }
    $skills = @(Get-ChildItem $sharedRoot -Directory -Force | Where-Object { $_.Name -ne '_meta.json' })
    if ($skills.Count -eq 0) { Write-Warn "共享库为空: $sharedRoot"; return }
    $list = Get-SkillListWithCategory
    $cats = @($list | Select-Object -ExpandProperty Category -Unique)
    Show-BoxTop ("技能清单 · 共 {0} 个技能 · {1} 个分类" -f $list.Count, $cats.Count) primary
    $ordered = Get-CategoryOrder $list
    foreach ($g in $ordered) {
        Show-BoxRowColor @(
            @{ T = ('◆ ' + $g.Name); C = 'primary'; B = $true },
            @{ T = ("（{0}）" -f $g.Count); C = 'gold'; B = $true }
        )
        foreach ($item in ($g.Group | Sort-Object Name)) {
            $intro = Truncate-Width $item.Intro 40
            if (-not $intro) { $intro = '（无简介）' }
            $row = "    " + (Pad-Width $item.Name 24) + $intro
            Show-BoxRow $row text
        }
        Show-BoxBlank
    }
    Show-BoxBottom primary
}

function Show-CategoryBrowse {
    $list = Get-SkillListWithCategory
    if (-not $list -or $list.Count -eq 0) { Write-Warn '共享库为空。请先安装技能。'; return }
    $ordered = Get-CategoryOrder $list
    Show-BoxTop '按分类浏览' primary
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $row = ("  [{0}]  {1}" -f ($i + 1), (Pad-Width ($ordered[$i].Name) 22)) + ("{0} 个技能" -f $ordered[$i].Count)
        Show-BoxRow $row text
    }
    Show-BoxBottom primary
    $n = 0
    while ($true) {
        Write-C ("? 输入分类编号查看技能（q 返回）  ") -C text -NoNewline
        Write-C '> ' -C primary -NoNewline
        $raw = (Read-Host).Trim()
        if ($raw -eq 'q' -or $raw -eq '') { return }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $ordered.Count) { $n = [int]$raw; break }
        Write-Err "请输入 1-$($ordered.Count) 的编号。"
    }
    $g = $ordered[$n - 1]
    Show-BoxTop ("{0}（{1}）" -f $g.Name, $g.Count) primary
    foreach ($item in ($g.Group | Sort-Object Name)) {
        $intro = Truncate-Width $item.Intro 50
        if (-not $intro) { $intro = '（无简介）' }
        $row = "  " + (Pad-Width $item.Name 24) + $intro
        Show-BoxRow $row text
    }
    Show-BoxBottom primary
    Write-C ''
}

function Remove-SkillInteractive {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot -or -not (Test-Path $sharedRoot)) {
        Write-Warn '共享库不存在。请先执行 [1] 快速搭建。'
        return
    }
    $skills = @(Get-ChildItem $sharedRoot -Directory -Force | Sort-Object Name)
    if ($skills.Count -eq 0) { Write-Warn '共享库为空。'; return }

    Show-BoxTop "选择要移除的技能（1-$($skills.Count)）" err
    for ($i = 0; $i -lt $skills.Count; $i++) {
        Show-BoxRow ("  [{0}]  {1}" -f ($i + 1), $skills[$i].Name) text
    }
    Show-BoxBottom err
    $n = 0
    while ($true) {
        Write-C ("? 输入编号  ") -C text -NoNewline
        Write-C '> ' -C primary -NoNewline
        $raw = (Read-Host).Trim()
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $skills.Count) { $n = [int]$raw; break }
        Write-Err "请输入 1-$($skills.Count) 的编号。"
    }
    $skill = $skills[$n - 1]
    $target = $skill.FullName
    Write-C ''
    Show-BoxTop '危险操作' err
    Show-BoxRowColor @(
        @{ T = ('即将移除：'); C = 'text' },
        @{ T = $target; C = 'warn'; B = $true }
    )
    Show-BoxRow '移除会删除共享库中的该技能，影响所有已接入的 Agent！' warn
    Show-BoxBottom err
    if (-not (Read-YesNo '确认删除？' $false)) { Write-Ok '已取消。'; return }
    $confirm = (Read-Host ("请再次输入技能名 [" + $skill.Name + "] 以确认")).Trim()
    if ($confirm -ne $skill.Name) { Write-Err '输入不一致，已取消。'; return }
    Remove-Item $target -Recurse -Force
    Write-Ok "已移除技能: $($skill.Name)"
}

function Install-SkillInteractive {
    Show-BoxTop '从 GitHub / skills.sh 仓库安装技能' primary
    Show-BoxRow '示例：https://github.com/hgta23/findskills' dim
    Show-BoxRow '      https://skills.sh/s/vercel-labs/skills/find-skills' dim
    Show-BoxBottom primary
    Write-C ("? 输入仓库链接（q 取消）  ") -C text -NoNewline
    Write-C '> ' -C primary -NoNewline
    $url = (Read-Host).Trim()
    if ($url -eq '' -or $url -eq 'q') { Write-Ok '已取消。'; return }
    & $installScript -RepoUrl $url
    Write-C ''
}

# =====================================================================
#  接入 / 移除 Agent
# =====================================================================
function Add-AgentInteractive {
    Write-C ("? 输入 Agent 名称（如 myagent，q 取消）  ") -C text -NoNewline
    Write-C '> ' -C primary -NoNewline
    $name = (Read-Host).Trim()
    if ($name -eq '' -or $name -eq 'q') { Write-Ok '已取消。'; return }
    Write-C ("? 输入其技能根目录完整路径  ") -C text -NoNewline
    Write-C '> ' -C primary -NoNewline
    $path = (Read-Host).Trim()
    if ($path -eq '') { Write-Err '路径为空，已取消。'; return }
    & $addAgentScript -AgentName $name -RootPath $path
    Write-C ''
    Write-C '提示：可用 [1] 快速搭建把该路径一并写入 config\agents.json，便于统一巡检。' -C accent
}

function Remove-AgentInteractive {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot) { Write-Warn '没有配置，无法判断。请先 [1] 快速搭建。'; return }
    $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agents = @($cfg.agents.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Path = [string]$_.Value }
    } | Sort-Object Name)
    if ($agents.Count -eq 0) { Write-Warn '配置中没有 Agent。'; return }

    Show-BoxTop '当前已配置的 Agent' primary
    for ($i = 0; $i -lt $agents.Count; $i++) {
        $row = ("  [{0}]  {1}  ->  {2}" -f ($i + 1), (Pad-Width $agents[$i].Name 24), $agents[$i].Path)
        Show-BoxRow $row text
    }
    Show-BoxBottom primary
    $n = 0
    while ($true) {
        Write-C ("? 输入要移除的编号（q 取消）  ") -C text -NoNewline
        Write-C '> ' -C primary -NoNewline
        $raw = (Read-Host).Trim()
        if ($raw -eq 'q') { return }
        if ($raw -match '^\d+$' -and [int]$raw -ge 1 -and [int]$raw -le $agents.Count) { $n = [int]$raw; break }
        Write-Err "请输入 1-$($agents.Count) 的编号。"
    }
    $target = $agents[$n - 1]
    if (-not (Read-YesNo ("移除 " + $target.Name + " 的联接？（数据仍在共享库，不删除）") $false)) { return }
    & $removeAgentScript -AgentName $target.Name -RootPath $target.Path
    Write-C ''
}

# =====================================================================
#  快速搭建
# =====================================================================
function Show-StepBadge {
    param([int]$Step, [int]$Total, [string]$Title)
    Write-C ''
    Show-BoxTop ("步骤 " + $Step + " / " + $Total + " · " + $Title) primary
    Show-BoxBottom primary
}

function Invoke-SetupFlow {
    $useExisting = $false
    if (Test-Path $ConfigPath) {
        Write-Warn "检测到已有配置：$ConfigPath"
        $useExisting = Read-YesNo '直接沿用现有配置搭建/验证？' $true
    }

    if (-not $useExisting) {
        Show-StepBadge 1 3 '共享技能库位置'
        $defaultShared = Join-Path $env:USERPROFILE 'skills\shared'
        Write-C ("  默认：") -C dim -NoNewline
        Write-C $defaultShared -C accent
        Write-C ("? 回车使用默认，或输入其他路径  ") -C text -NoNewline
        Write-C '> ' -C primary -NoNewline
        $in = (Read-Host).Trim()
        $sharedRoot = if ($in) { [IO.Path]::GetFullPath($in) } else { $defaultShared }

        Show-StepBadge 2 3 '选择要接入的 Agent（预设常见 Agent 路径，自动探测本机状态）'
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
            @{ Key = 'copilot';             Label = 'GitHub Copilot';          Path = (Join-Path $env:USERPROFILE '.copilot\skills') },
            @{ Key = 'workbuddy';           Label = 'WorkBuddy';               Path = (Join-Path $env:USERPROFILE '.workbuddy\skills') }
        )
        $choices = @()
        $detectedFlags = @()
        for ($i = 0; $i -lt $detectors.Count; $i++) {
            $d = $detectors[$i]
            $exists = Test-Path $d.Path
            $mark = if ($exists) { '✅ 已检测到' } else { '　未找到　' }
            $row = ("  [{0}]  {1}  {2}" -f ($i + 1), (Pad-Width $d.Label 42), $mark)
            if ($exists) { Show-BoxRowColor @(@{ T = ('  [' + ($i + 1) + ']  '); C = 'primary'; B = $true }, @{ T = (Pad-Width $d.Label 42); C = 'text' }, @{ T = '✅ 已检测到'; C = 'ok'; B = $true }) }
            else { Show-BoxRow $row dim }
            $choices += [pscustomobject]@{ Key = $d.Key; Path = $d.Path }
            $detectedFlags += $exists
        }
        $sel = Read-ChoiceList $choices.Count '输入编号接入（逗号分隔多选，d=全选已检测到，a=全部，q=跳过）' $detectedFlags

        $agentList = @()
        foreach ($n in $sel) {
            $c = $choices[$n - 1]
            $agentList += [pscustomobject]@{ Name = $c.Key; Path = $c.Path }
        }

        if (Read-YesNo '添加自定义 Agent 路径？' $false) {
            Write-C '格式：名称=完整路径（如 myagent=C:\Users\me\.myagent\skills），空行结束' -C dim
            while ($true) {
                Write-C ("? 名称=路径  ") -C text -NoNewline
                Write-C '> ' -C primary -NoNewline
                $line = (Read-Host).Trim()
                if ($line -eq '') { break }
                $eq = $line.IndexOf('=')
                if ($eq -le 0) { Write-Err '格式错误，应为 名称=路径'; continue }
                $name = $line.Substring(0, $eq).Trim()
                $path = $line.Substring($eq + 1).Trim()
                if (-not $name -or -not $path) { Write-Err '名称或路径为空，已忽略。'; continue }
                $agentList += [pscustomobject]@{ Name = $name; Path = [IO.Path]::GetFullPath($path) }
            }
        }

        if ($agentList.Count -eq 0) {
            Write-Err '未选择任何 Agent，已取消，未做任何修改。'
            return
        }

        Show-StepBadge 3 3 '确认配置'
        Show-BoxTop '配置预览' primary
        Show-BoxRowColor @(@{ T = ('共享库：'); C = 'dim' }, @{ T = $sharedRoot; C = 'accent'; B = $true })
        foreach ($a in $agentList) {
            Show-BoxRow ("  " + (Pad-Width $a.Name 24) + "->  " + $a.Path) text
        }
        Show-BoxBottom primary
        if (-not (Read-YesNo '确认无误，写入配置并开始搭建？' $true)) {
            Write-Ok '已取消，未做任何修改。'
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

    Write-C ''
    Show-BoxTop '开始搭建（setup.ps1）' primary
    Show-BoxBottom primary
    & $setupScript -ConfigPath $ConfigPath
    Write-C ''
    Show-BoxTop '开始验证（verify.ps1）' primary
    Show-BoxBottom primary
    & $verifyScript -ConfigPath $ConfigPath
    Write-C ''
    Write-Ok '搭建完成！请重启各 Agent 会话（新开会话）使技能生效。'
}

# =====================================================================
#  检查技能版本更新
# =====================================================================
function Invoke-CheckUpdates {
    $sharedRoot = Get-SharedRoot
    if (-not $sharedRoot -or -not (Test-Path $sharedRoot)) {
        Write-Warn '共享库不存在。请先 [1] 快速搭建，或用 [3]b 安装技能。'
        return
    }
    Show-BoxTop '检查技能版本更新（GitHub 仓库来源）' primary
    Show-BoxBottom primary
    & $checkUpdatesScript -ConfigPath $ConfigPath
    Write-C ''
    if (Read-YesNo '对检测到的「有更新」仓库立即自动升级？' $false) {
        Write-C ''
        Show-BoxTop '自动升级' ok
        Show-BoxBottom ok
        & $checkUpdatesScript -ConfigPath $ConfigPath -Update
    }
    Write-C ''
    Write-Ok '重启各 Agent 会话使升级后的技能生效。'
}

# =====================================================================
#  帮助
# =====================================================================
function Show-Help {
    Show-BoxTop '帮助与文档' primary
    Show-BoxRow '' text
    Show-BoxRowColor @(@{ T = '仓库（含全部文档与图解）'; C = 'dim' }, @{ T = '  github.com/JacksenHu/agent-skills-shared'; C = 'accent' })
    Show-BoxBlank
    Show-BoxRow 'docs/01-architecture.md           方案原理' dim
    Show-BoxRow 'docs/02-agent-path-reference.md   各 Agent 技能目录速查' dim
    Show-BoxRow 'docs/03-setup-guide.md            搭建指南' dim
    Show-BoxRow 'docs/04-day-to-day.md             日常使用（新增/更新/删除技能、增删 Agent）' dim
    Show-BoxRow 'docs/05-safety-and-rollback.md    风险与回滚' dim
    Show-BoxRow 'docs/06-faq.md                    常见问题' dim
    Show-BoxBlank
    Show-BoxMid
    Show-BoxRow '' text
    Show-BoxRowColor @(@{ T = '常用命令'; C = 'gold'; B = $true })
    Show-BoxRow '快速搭建（非交互）  .\scripts\setup.ps1' text
    Show-BoxRow '验证                .\scripts\verify.ps1' text
    Show-BoxRow '扫描 Agent 技能     .\scripts\scan-agents.ps1' text
    Show-BoxRow '检查技能版本更新    .\scripts\check-updates.ps1  （-Update 自动升级）' text
    Show-BoxRow '接入 Agent    .\scripts\add-agent.ps1 -AgentName 名 -RootPath 路径' text
    Show-BoxRow '移除 Agent    .\scripts\remove-agent.ps1 -AgentName 名 -RootPath 路径' text
    Show-BoxRow '安装技能（仓库链接）.\scripts\install-skill.ps1 -RepoUrl <仓库地址>' text
    Show-BoxRow '安装技能（skills.sh）.\scripts\install-skill.ps1 -RepoUrl <skills 链接>' text
    Show-BoxBlank
    Show-BoxRow '提示：' gold
    Show-BoxRow '- 迁移/去重/冲突策略见 setup.ps1 输出与 docs/05' dim
    Show-BoxRow '- 仓库链接安装到共享库后，重启各 Agent 会话生效' dim
    Show-BoxRow '- 在 Agent 内手动安装的技能可用 [5] 扫描发现并迁移' dim
    Show-BoxRow '- 只有仓库链接安装的技能可检测升级（[6]），安装会记录基准 commitSha' dim
    Show-BoxBottom primary
    Write-C ''
}

# =====================================================================
#  桌面快捷方式（首次启动自动创建）
# =====================================================================
function New-DesktopShortcut {
    $shortcutName = '统一技能库管理.lnk'
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
        $lnk = Join-Path $desktop $shortcutName
        if (Test-Path $lnk) { return $false }
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $sc.Arguments = "-NoExit -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'setup-wizard.ps1')`""
        $sc.WorkingDirectory = Split-Path $PSScriptRoot -Parent
        $sc.Description = '统一技能库 · 管理控制台（一个技能，只装一次，所有 Agent 共用）'
        $sc.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
        $sc.Save()
        return $true
    } catch {
        Write-Warn "创建桌面快捷方式失败（不影响使用）：$($_.Exception.Message)"
        return $false
    }
}

# =====================================================================
#  主菜单
# =====================================================================
function Show-MainMenu {
    while ($true) {
        Write-C ''
        Show-Banner
        Write-C ''
        Show-BoxTop '主菜单' primary
        Show-BoxRowColor @(
            @{ T = '  [1] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '快速搭建' 18); C = 'white'; B = $true },
            @{ T = '配置 Agent · 迁移已有技能 · 建立联接'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [2] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '验证联接' 18); C = 'white'; B = $true },
            @{ T = '检查所有 Agent 的技能可见性'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [3] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '技能管理' 18); C = 'white'; B = $true },
            @{ T = '分类清单 · GitHub / skills.sh 仓库安装 · 移除'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [4] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '接入 / 移除 Agent' 18); C = 'white'; B = $true },
            @{ T = 'Agent 联接管理与回滚'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [5] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '扫描已装技能' 18); C = 'white'; B = $true },
            @{ T = '发现各 Agent 中未进共享库的技能'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [6] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '检查版本更新' 18); C = 'white'; B = $true },
            @{ T = '对比 GitHub 仓库最新提交，可选自动升级'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [7] '; C = 'accent'; B = $true },
            @{ T = (Pad-Width '帮助与文档' 18); C = 'white'; B = $true },
            @{ T = 'docs 导航 · 常用命令'; C = 'dim' }
        )
        Show-BoxRowColor @(
            @{ T = '  [0] '; C = 'gold'; B = $true },
            @{ T = (Pad-Width '退出' 18); C = 'white'; B = $true },
            @{ T = '结束本次会话'; C = 'dim' }
        )
        Show-BoxMid
        Show-StatusBar
        Write-C ''
        Write-C ("? 请选择  ") -C text -NoNewline
        Write-C '[0-7]' -C dim -NoNewline
        Write-C '  > ' -C primary -NoNewline
        $choice = (Read-Host).Trim()

        switch ($choice) {
            '1' { Invoke-SetupFlow }
            '2' {
                if (-not (Test-Path $ConfigPath)) { Write-Warn '还没有配置。请先 [1] 快速搭建。' }
                else { & $verifyScript -ConfigPath $ConfigPath }
            }
            '3' {
                while ($true) {
                    Write-C ''
                    Show-BoxTop '技能管理' primary
                    Show-BoxRowColor @(@{ T = '  [a] '; C = 'accent'; B = $true }, @{ T = (Pad-Width '技能清单' 14); C = 'white'; B = $true }, @{ T = '按分类分组，含中文简介'; C = 'dim' })
                    Show-BoxRowColor @(@{ T = '  [b] '; C = 'accent'; B = $true }, @{ T = (Pad-Width '仓库安装' 14); C = 'white'; B = $true }, @{ T = '从 GitHub / skills.sh 链接安装'; C = 'dim' })
                    Show-BoxRowColor @(@{ T = '  [c] '; C = 'accent'; B = $true }, @{ T = (Pad-Width '移除技能' 14); C = 'white'; B = $true }, @{ T = '从共享库删除（影响所有 Agent）'; C = 'dim' })
                    Show-BoxRowColor @(@{ T = '  [d] '; C = 'accent'; B = $true }, @{ T = (Pad-Width '分类浏览' 14); C = 'white'; B = $true }, @{ T = '先选分类，再查看该类技能'; C = 'dim' })
                    Show-BoxRowColor @(@{ T = '  [q] '; C = 'gold'; B = $true }, @{ T = (Pad-Width '返回主菜单' 14); C = 'white'; B = $true })
                    Show-BoxBottom primary
                    Write-C ("? 请选择  ") -C text -NoNewline
                    Write-C '> ' -C primary -NoNewline
                    $sub = (Read-Host).Trim().ToLower()
                    if ($sub -eq 'q' -or $sub -eq '') { break }
                    switch ($sub) {
                        'a' { Show-SkillList; Write-C '' }
                        'b' { Install-SkillInteractive }
                        'c' { Remove-SkillInteractive; Write-C '' }
                        'd' { Show-CategoryBrowse; Write-C '' }
                        default { Write-Err '无效选项。' }
                    }
                }
            }
            '4' {
                while ($true) {
                    Write-C ''
                    Show-BoxTop '接入 / 移除 Agent' primary
                    Show-BoxRowColor @(@{ T = '  [a] '; C = 'accent'; B = $true }, @{ T = (Pad-Width '接入新 Agent' 14); C = 'white'; B = $true }, @{ T = '建联接，数据自动迁移'; C = 'dim' })
                    Show-BoxRowColor @(@{ T = '  [b] '; C = 'accent'; B = $true }, @{ T = (Pad-Width '移除 Agent' 14); C = 'white'; B = $true }, @{ T = '拆联接，数据保留在共享库'; C = 'dim' })
                    Show-BoxRowColor @(@{ T = '  [q] '; C = 'gold'; B = $true }, @{ T = (Pad-Width '返回主菜单' 14); C = 'white'; B = $true })
                    Show-BoxBottom primary
                    Write-C ("? 请选择  ") -C text -NoNewline
                    Write-C '> ' -C primary -NoNewline
                    $sub = (Read-Host).Trim().ToLower()
                    if ($sub -eq 'q' -or $sub -eq '') { break }
                    switch ($sub) {
                        'a' { Add-AgentInteractive }
                        'b' { Remove-AgentInteractive }
                        default { Write-Err '无效选项。' }
                    }
                }
            }
            '5' {
                if (-not (Test-Path $ConfigPath)) { Write-Warn '还没有配置。请先 [1] 快速搭建。' }
                else { & (Join-Path $PSScriptRoot 'scan-agents.ps1') -ConfigPath $ConfigPath }
            }
            '6' { Invoke-CheckUpdates }
            '7' { Show-Help }
            '0' { Write-Ok '再见！'; return }
            default { Write-Err '无效选项，请输入 0-7。' }
        }
    }
}

# =====================================================================
#  入口
# =====================================================================
Initialize-Ansi

# 首次启动：自动创建桌面快捷方式（已存在则跳过）
if (New-DesktopShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
    Write-C ''
    Show-BoxTop '桌面快捷方式' ok
    Show-BoxRowColor @(@{ T = ('已创建：'); C = 'dim' }, @{ T = (Join-Path $desktop '统一技能库管理.lnk'); C = 'ok'; B = $true })
    Show-BoxRow '以后双击桌面「统一技能库管理」即可打开管理控制台；不需要可自行删除。' dim
    Show-BoxBottom ok
    Write-C ''
}

Show-MainMenu
