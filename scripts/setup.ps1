#requires -Version 5.1
<#
.SYNOPSIS
  方案一 · 一键搭建：统一技能库 + 目录联接（Junction）

.DESCRIPTION
  读取 config\agents.json：
  1) 创建共享技能库目录（sharedRoot，不存在时）；
  2) 把每个 Agent 的技能根目录通过 NTFS Junction 指向共享库；
  3) 已有技能自动迁移进共享库（同名冲突：保留现有版本并报告，绝不覆盖）。

  无需管理员权限（Junction 免提权）。脚本只处理配置文件中列出的路径，
  不会触碰任何系统级技能目录。

.EXAMPLE
  .\scripts\setup.ps1 -WhatIf      # 试运行：只预览将要执行的操作
  .\scripts\setup.ps1              # 正式执行
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 默认配置路径（$PSScriptRoot 在 param 默认值阶段不可用，故在主体解析）
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot '..\config\agents.json' }

# ---------- 工具：比较两个目录内容是否完全一致（相对路径 + 文件哈希） ----------
function Test-DirSame {
    param([string]$PathA, [string]$PathB)
    $filesA = @(Get-ChildItem $PathA -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)
    $filesB = @(Get-ChildItem $PathB -Recurse -File -Force -ErrorAction SilentlyContinue | Sort-Object FullName)
    if ($filesA.Count -ne $filesB.Count) { return $false }
    if ($filesA.Count -eq 0) { return $true }
    $sha = [Security.Cryptography.SHA256]::Create()
    for ($i = 0; $i -lt $filesA.Count; $i++) {
        $relA = $filesA[$i].FullName.Substring($PathA.Length).TrimStart([char[]]@('\', '/'))
        $relB = $filesB[$i].FullName.Substring($PathB.Length).TrimStart([char[]]@('\', '/'))
        if ($relA -ne $relB) { return $false }
        $hA = [Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($filesA[$i].FullName)))
        $hB = [Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($filesB[$i].FullName)))
        if ($hA -ne $hB) { return $false }
    }
    return $true
}

# ---------- 读取配置 ----------
if (-not (Test-Path $ConfigPath)) {
    throw "找不到配置文件: $ConfigPath`n请先执行: copy config\agents.example.json config\agents.json 并填写你的路径。"
}
Write-Host "读取配置: $ConfigPath" -ForegroundColor Cyan
$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $config.sharedRoot) { throw '配置缺少 sharedRoot 字段' }

$sharedRoot = [IO.Path]::GetFullPath($config.sharedRoot)
Write-Host "共享技能库: $sharedRoot" -ForegroundColor Cyan

# 收集 Agent 路径（键名是备注；同一路径去重）
$agentPaths = @($config.agents.PSObject.Properties | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; Path = [IO.Path]::GetFullPath([string]$_.Value) }
} | Sort-Object Path -Unique)

if ($agentPaths.Count -eq 0) { throw '配置中没有任何 Agent 路径，请先编辑 agents.json' }

# ---------- 创建共享库 ----------
if (-not (Test-Path $sharedRoot)) {
    if ($PSCmdlet.ShouldProcess($sharedRoot, '创建共享技能库目录')) {
        New-Item -ItemType Directory -Path $sharedRoot -Force | Out-Null
        Write-Host "[OK] 已创建共享库: $sharedRoot" -ForegroundColor Green
    }
} else {
    Write-Host "[OK] 共享库已存在: $sharedRoot" -ForegroundColor Green
}

# ---------- 逐个 Agent 处理 ----------
foreach ($a in $agentPaths) {
    $root  = $a.Path
    $name  = $a.Name
    $conflicted = 0
    Write-Host "`n===== Agent: $name" -ForegroundColor Cyan

    if (Test-Path $root) {
        $item = Get-Item $root -Force
        if ($item.LinkType -eq 'Junction') {
            $target = [string](($item.Target) -join '')
            if ($target -eq $sharedRoot) {
                Write-Host "[SKIP] 已是指向共享库的联接" -ForegroundColor Yellow
            } else {
                Write-Warning "[WARN] 是联接但目标不是共享库: $target`n      跳过该目录，请手动确认其用途。"
            }
            continue
        }
        if (-not $item.PSIsContainer) {
            Write-Warning "[WARN] $root 不是目录，跳过。"
            continue
        }

        # 真实目录：迁移内容到共享库
        $children = @(Get-ChildItem $root -Force)
        $moved = 0; $deduped = 0
        if ($children.Count -gt 0) {
            Write-Host "迁移 $($children.Count) 项已有内容到共享库…"
            foreach ($c in $children) {
                $dest = Join-Path $sharedRoot $c.Name
                if (Test-Path $dest) {
                    if (Test-DirSame -PathA $c.FullName -PathB $dest) {
                        Write-Host "  [去重] $($c.Name) 与共享库内容一致，移除冗余副本" -ForegroundColor Yellow
                        if ($PSCmdlet.ShouldProcess($c.FullName, '移除与共享库内容一致的冗余副本')) {
                            Remove-Item -Path $c.FullName -Recurse -Force
                            $deduped++
                        }
                    } else {
                        Write-Warning "  [冲突] 共享库已有同名「$($c.Name)」但内容不同；保留原处 `n         $($c.FullName)`n         请人工决定（保留哪份），处理后再运行。"
                        $conflicted++
                    }
                    continue
                }
                if ($PSCmdlet.ShouldProcess($c.FullName, '迁移到共享库')) {
                    Move-Item -Path $c.FullName -Destination $dest
                    Write-Host "  已迁移: $($c.Name)" -ForegroundColor Green
                    $moved++
                }
            }
        }

        # 目录已空才能删除并建联接
        if ($conflicted -gt 0) {
            Write-Warning "[跳过] $name 存在 $conflicted 项内容冲突（见上方），目录未清空，请人工处理后重跑。"
            continue
        }
        if ($PSCmdlet.ShouldProcess($root, '删除空目录（内容已迁移）')) {
            Remove-Item -Path $root -Force
        }
        if (Test-Path $root) {
            Write-Warning "[跳过] $root 未能清空（可能有隐藏文件），请手动处理后再运行。"
            continue
        }
    }

    # 创建 Junction
    if ($PSCmdlet.ShouldProcess($root, "创建目录联接 -> $sharedRoot")) {
        $out = & cmd /c ('mklink /J "' + $root + '" "' + $sharedRoot + '"') 2>&1
        $out | ForEach-Object { Write-Host "  $_" }
        $check = Get-Item $root -Force -ErrorAction SilentlyContinue
        $checkTarget = if ($check) { [string](($check.Target) -join '') } else { '' }
        if ($check -and $check.LinkType -eq 'Junction' -and $checkTarget -eq $sharedRoot) {
            Write-Host "[OK] 联接已建立: $root" -ForegroundColor Green
        } else {
            Write-Warning "[FAIL] 联接创建失败，请检查目标路径与权限。"
        }
    }
}

# ---------- 收尾 ----------
Write-Host "`n========== 搭建完成 ==========" -ForegroundColor Cyan
Write-Host "请运行验证: .\scripts\verify.ps1"
Write-Host "然后重启各 Agent 会话（新开会话）使技能生效。"
