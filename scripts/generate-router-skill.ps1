#requires -Version 5.1
<#
.SYNOPSIS
  生成 / 刷新「统一技能路由」技能（skill-router）

.DESCRIPTION
  扫描共享技能库，读取每个技能的 _meta.json（中文简介优先）或
  SKILL.md frontmatter description，按 9 大分类组织，生成
  <共享库>\router-guide\SKILL.md —— 一个类似 ask-matt 的总路由技能：
  用户在任何 Agent 中触发它，即可按情境从共享库找到最合适的技能。

  每次新装/移除技能后重新运行本脚本即可刷新索引。

.EXAMPLE
  .\scripts\generate-router-skill.ps1
  .\scripts\generate-router-skill.ps1 -SharedRoot "C:\Users\me\skills\shared"
#>
[CmdletBinding()]
param(
    [string]$SharedRoot = (Join-Path $env:USERPROFILE 'skills\shared')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SharedRoot)) {
    Write-Host "[ERR] 共享库不存在: $SharedRoot" -ForegroundColor Red
    exit 1
}
$SharedRoot = [IO.Path]::GetFullPath($SharedRoot)

# ---------- 解析 SKILL.md frontmatter（简单 YAML 行式解析） ----------
function Read-Frontmatter {
    param([string]$Path)
    $result = @{}
    try {
        $lines = Get-Content $Path -Encoding UTF8 -TotalCount 60
        if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') { return $result }
        foreach ($line in $lines[1..($lines.Count - 1)]) {
            if ($line.Trim() -eq '---') { break }
            $idx = $line.IndexOf(':')
            if ($idx -le 0) { continue }
            $k = $line.Substring(0, $idx).Trim().ToLower()
            $v = $line.Substring($idx + 1).Trim().Trim('"', "'")
            $result[$k] = $v
        }
    } catch { }
    return $result
}

# ---------- 读取技能简介（中文优先） ----------
function Get-SkillIntro {
    param([string]$SkillDir, [string]$Name)
    $meta = Join-Path $SkillDir '_meta.json'
    if (Test-Path $meta) {
        try {
            $j = Get-Content $meta -Raw -Encoding UTF8 | ConvertFrom-Json
            $zh = [string]$j.descriptionZh
            if ($zh -and $zh.Trim() -ne '>' -and $zh.Trim() -ne '') { return $zh.Trim() }
            $en = [string]$j.description
            if ($en -and $en.Trim() -ne '>' -and $en.Trim() -ne '') { return $en.Trim() }
        } catch { }
    }
    $md = Join-Path $SkillDir 'SKILL.md'
    if (Test-Path $md) {
        $fm = Read-Frontmatter $md
        $desc = [string]$fm['description']
        if ($desc) { return $desc.Trim() }
    }
    return ''
}

# ---------- 9 大分类关键词词典（与 setup-wizard.ps1 保持一致） ----------
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
        $fm = Read-Frontmatter $md
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

# 共享库内所有技能一律收录进路由索引：不设排除名单，不做内容审查。

# ---------- 收集全部技能 ----------
$skills = @(Get-ChildItem $SharedRoot -Directory -Force | Where-Object { $_.Name -ne 'router-guide' })
$items = @()
$uncategorized = 0
foreach ($s in $skills | Sort-Object Name) {
    $intro = Get-SkillIntro $s.FullName $s.Name
    $cat = Get-SkillCategory $s.FullName $s.Name $intro
    if ($cat -eq '未分类') { $uncategorized++ }
    $items += [pscustomobject]@{ Name = $s.Name; Intro = $intro; Category = $cat }
}

# ---------- 生成 SKILL.md ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('name: skill-router')
[void]$sb.AppendLine('description: 共享技能库的总路由。当用户描述一个任务或情境时，先阅读本文件的分类索引，从共享技能库中选出最匹配的 1~3 个技能并说明理由；用户也可以直接点名某个技能名，此时说明它是什么、适合什么场景。所有条目按 9 大分类组织。')
[void]$sb.AppendLine('---')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('# 统一技能路由')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('你是共享技能库的路由器，技能库根目录：' + $SharedRoot)
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 使用方式')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('- 直接描述你想做的事（一句话即可），我会按情境推荐最匹配的 1~3 个技能并说明理由；')
[void]$sb.AppendLine('- 或直接说技能名，我告诉你它是什么、什么时候用、怎么触发；')
[void]$sb.AppendLine('- 本技能只做**索引与推荐**：确定技能后，按该技能自己的 SKILL.md 使用。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 路由步骤')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('1. 判断情境属于哪个大类（开发 / 写作 / 研究 / 办公 / 数据 / 设计 / 音视频 / Agent 管理 / 生活）；')
[void]$sb.AppendLine('2. 在该分类条目中按名称与简介匹配任务关键词；')
[void]$sb.AppendLine('3. 命中多个时，按描述贴合度排序，最多推荐 3 个。')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## 分类索引（共 ' + $items.Count + ' 个技能 · 9 大分类 + 未分类）')
[void]$sb.AppendLine('')

$catNames = @('开发与工程', '写作与内容', '研究与搜索', '办公与效率', '数据分析', '设计与创意', '音视频与媒体', 'Agent 与技能管理', '生活与日常', '未分类')
foreach ($cn in $catNames) {
    $group = @($items | Where-Object { $_.Category -eq $cn })
    if ($group.Count -eq 0) { continue }
    [void]$sb.AppendLine('### ' + $cn + '（' + $group.Count + '）')
    [void]$sb.AppendLine('')
    foreach ($g in $group) {
        if ($g.Intro) {
            [void]$sb.AppendLine('- **' + $g.Name + '**：' + $g.Intro)
        } else {
            [void]$sb.AppendLine('- **' + $g.Name + '**')
        }
    }
    [void]$sb.AppendLine('')
}

$outDir = Join-Path $SharedRoot 'router-guide'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$outFile = Join-Path $outDir 'SKILL.md'
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($outFile, $sb.ToString(), $utf8Bom)

Write-Host ''
Write-Host ('[OK] 已生成总路由技能: ' + $outFile) -ForegroundColor Green
Write-Host ('     技能总数: ' + $items.Count + ' · 未分类: ' + $uncategorized) -ForegroundColor Cyan
Write-Host '     在任何 Agent 中触发 skill-router，即可按情境路由到共享库技能。' -ForegroundColor Cyan
Write-Host '     每次新增/移除技能后，重新运行本脚本刷新索引。' -ForegroundColor Cyan
