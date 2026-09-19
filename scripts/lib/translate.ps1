#requires -Version 5.1
<#
  translate.ps1 — 技能简介翻译 + SKILL.md frontmatter 解析（公共库）
  被 install-skill.ps1 / translate-skill-intro.ps1 共用（dot-source 加载）

  - Test-HasCjk            : 判断文本是否已含中文
  - Read-SkillFrontmatter  : 解析 SKILL.md 的 YAML frontmatter（支持跨行 / 折叠块）
  - ConvertTo-DescriptionZh: 英文简介 → 中文
                             接口顺序 MyMemory（免费无需 key）→ Google gtx 兜底
                             均失败时逐块保留原文；整段失败则返回原文（调用方用 Test-HasCjk 判定成败）
#>

# ---------- 文本工具 ----------
function Test-HasCjk {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '[\u4e00-\u9fff]')
}

function ConvertFrom-HtmlEntity {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $t = $Text
    $t = $t -replace '&#0?39;', "'"
    $t = $t -replace '&quot;', '"'
    $t = $t -replace '&apos;', "'"
    $t = $t -replace '&lt;', '<'
    $t = $t -replace '&gt;', '>'
    $t = $t -replace '&nbsp;', ' '
    $t = $t -replace '&amp;', '&'
    return $t
}

# 按句边界切块：免费接口单次长度有限，长简介分块翻译再拼接
function Split-ForTranslate {
    param([string]$Text, [int]$MaxLen = 450)
    $parts = [regex]::Split($Text, '(?<=[。！？!?\.;；\n])')
    $chunks = @()
    $cur = ''
    foreach ($p in $parts) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($cur.Length -gt 0 -and ($cur.Length + $p.Length) -gt $MaxLen) {
            $chunks += $cur
            $cur = ''
        }
        $piece = $p
        while ($piece.Length -gt $MaxLen) {
            $chunks += $piece.Substring(0, $MaxLen)
            $piece = $piece.Substring($MaxLen)
        }
        $cur += $piece
    }
    if ($cur.Length -gt 0) { $chunks += $cur }
    if ($chunks.Count -eq 0) { $chunks = @($Text) }
    # 正常返回数组（由管道展开），调用方用 @() 收集即可；勿用 return ,$chunks——会造成数组嵌套
    return $chunks
}

# ---------- 翻译接口 ----------
function Get-MyMemoryZh {
    param([string]$Text, [string]$Email)
    try {
        $q = [uri]::EscapeDataString($Text)
        $uri = "https://api.mymemory.translated.net/get?q=$q&langpair=en|zh-CN"
        # MyMemory 匿名配额很低；带 de=邮箱 可显著提高每日额度（官方支持的用法）
        if ($Email) { $uri += ('&de=' + [uri]::EscapeDataString($Email)) }
        $r = Invoke-RestMethod -Uri $uri -TimeoutSec 12 -UseBasicParsing
        $zh = [string]$r.responseData.translatedText
        if ([string]::IsNullOrWhiteSpace($zh)) { return '' }
        if ($zh -eq 'NO QUERY SPECIFIED') { return '' }
        # 接口把错误信息塞在 translatedText 里返回，必须识别出来，否则会被当成译文
        if ($zh -match 'MYMEMORY WARNING') { return '' }
        if ($zh -match 'QUERY LENGTH LIMIT EXCEEDED') { return '' }
        if ($zh -match 'INVALID (EMAIL|LANGPAIR|SOURCE|TARGET)') { return '' }
        return (ConvertFrom-HtmlEntity $zh).Trim()
    } catch {
        return ''
    }
}

function Get-GoogleZh {
    param([string]$Text)
    try {
        $q = [uri]::EscapeDataString($Text)
        $uri = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=$q"
        $r = Invoke-RestMethod -Uri $uri -TimeoutSec 10 -UseBasicParsing
        $zh = ''
        foreach ($seg in @($r[0])) { $zh += [string]$seg[0] }
        return (ConvertFrom-HtmlEntity $zh).Trim()
    } catch {
        return ''
    }
}

function ConvertTo-DescriptionZh {
    param(
        [string]$Description,
        [int]$MaxLen = 450,
        [string]$Email
    )
    if ([string]::IsNullOrWhiteSpace($Description)) { return '' }
    $desc = $Description.Trim()
    # 已含中文则无需翻译
    if (Test-HasCjk $desc) { return $desc }

    $chunks = @(Split-ForTranslate -Text $desc -MaxLen $MaxLen)
    $out = ''
    foreach ($c in $chunks) {
        $zh = Get-MyMemoryZh -Text $c -Email $Email
        if (-not $zh) { $zh = Get-GoogleZh $c }
        if ($zh) { $out += $zh } else { $out += $c }   # 该块失败：保留原文
    }
    return $out.Trim()
}

# ---------- frontmatter ----------
# 支持三种写法：
#   description: 单行
#   description: 很长的一句话
#     跨行续写（缩进续行）
#   description: >
#     折叠块正文
function Read-SkillFrontmatter {
    param([string]$SkillMdPath)
    $meta = [ordered]@{}
    if (-not (Test-Path -LiteralPath $SkillMdPath)) { return $meta }
    $lines = @(Get-Content -LiteralPath $SkillMdPath -Encoding UTF8 -TotalCount 80)
    if ($lines.Count -lt 3) { return $meta }
    if ($lines[0].Trim() -ne '---') { return $meta }

    $curKey = ''
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line.Trim() -eq '---') { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }

        if ($line -match '^\s') {
            # 缩进续行：并入当前键
            if ($curKey) {
                $add = $line.Trim()
                if ($add) { $meta[$curKey] = (([string]$meta[$curKey] + ' ' + $add).Trim()) }
            }
            continue
        }

        $kv = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*?)\s*$')
        if ($kv.Success) {
            $curKey = $kv.Groups[1].Value
            $val = $kv.Groups[2].Value.Trim().Trim('"').Trim("'")
            # 折叠块 / 字面块的起始标记本身不是内容
            if ($val -eq '>' -or $val -eq '>-' -or $val -eq '>+' -or $val -eq '|' -or $val -eq '|-' -or $val -eq '|+') { $val = '' }
            $meta[$curKey] = $val
        }
    }
    return $meta
}
