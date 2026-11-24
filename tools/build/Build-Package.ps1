#Requires -Version 5.1
<#
.SYNOPSIS
    组装离线安装包：把 payload 与随包资产打成单个 zip。

.DESCRIPTION
    产物是**唯一交付物**。用户拿到 zip 之后：解压 → 双击 安装.cmd → 完成，
    全程不需要联网，也不需要另外下载任何东西。

    所以 zip 必须自包含：
      - Sunshine 安装包（msi）
      - Moonlight 便携版（客户端自取）
      - MTT VDD 驱动包
      - 第三方许可证全文（GPL-3.0 再分发要求）
      - manifest/components.json（安装脚本据此校验版本与哈希）

    为什么要带 manifest：Install.ps1 会用它校验 msi 的 SHA256 再安装，
    防止包被替换或传输损坏；顺带也让安装日志能说清装的是哪个版本。

.PARAMETER SkipFetch
    跳过随包资产检查（资产已确认就绪时可加快出包，不建议在正式出包时使用）。

.PARAMETER NoClean
    保留 staging 目录，便于排查打包内容。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build\Build-Package.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipFetch,
    [switch]$NoClean
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Payload  = Join-Path $RepoRoot 'payload'
$Manifest = Join-Path $RepoRoot 'manifest\components.json'
$DistDir  = Join-Path $RepoRoot 'dist'

function Info($m) { Write-Host "    $m" -ForegroundColor Gray }
function Ok($m)   { Write-Host "    OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    WARN $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "    FAIL $m" -ForegroundColor Red }

Write-Host ''
Write-Host '==== 组装离线安装包 ====' -ForegroundColor White

# ---------- 1. 清单 ----------
if (-not (Test-Path -LiteralPath $Manifest)) {
    Fail "找不到 $Manifest"
    exit 1
}
$m = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$m.package.version
if (-not $version) { Fail 'manifest 缺少 package.version'; exit 1 }
# 说明文件与自检清单从 manifest 派生，避免"构建脚本不得硬编码版本"被自己违反
$moonAsset = [string]$m.components.moonlight.asset
Info "版本: $version"

if (-not $SkipFetch) {
    Write-Host ''
    Write-Host '  提示：资产是否就绪由下面逐项校验；缺任何一项都会中止出包。'
}

# ---------- 2. 随包资产 ----------
Write-Host ''
Write-Host '[1] 随包资产校验' -ForegroundColor Cyan

$missing = @()
$vendorDir = Join-Path $Payload 'vendor'
$totalBytes = 0

foreach ($name in @($m.components.PSObject.Properties.Name)) {
    $c = $m.components.$name
    $f = Join-Path $vendorDir $c.asset

    if (-not (Test-Path -LiteralPath $f)) {
        Fail "$name 缺少 $($c.asset)"
        $missing += "${name}:$($c.asset)"
        continue
    }

    $len = (Get-Item -LiteralPath $f).Length
    $totalBytes += $len

    # 先比大小：不完整的下载能被立刻抓住，不必等到算完哈希
    if ($c.size_bytes -and $len -ne [long]$c.size_bytes) {
        Fail "$name 大小不符：实际 $len，期望 $($c.size_bytes)（下载不完整）"
        $missing += "${name}:size"
        continue
    }

    $sha = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower()
    if ($c.sha256 -and $sha -ne ([string]$c.sha256).ToLower()) {
        Fail "$name 哈希不符"
        Info "  实际 $sha"
        Info "  期望 $($c.sha256)"
        $missing += "${name}:sha256"
        continue
    }

    Ok ("{0,-10} {1}  {2} MB" -f $name, $c.asset, [math]::Round($len / 1MB, 2))
}

if ($missing.Count -gt 0) {
    Write-Host ''
    Fail "资产不齐（$($missing.Count) 项），拒绝出包。"
    Info '先运行 tools\build\Fetch-Vendor.ps1 补齐。'
    exit 1
}

# ---------- 3. 许可证 ----------
Write-Host ''
Write-Host '[2] 许可证全文' -ForegroundColor Cyan

$licenseDir = Join-Path $Payload 'licenses'
$licenseNeeded = @($m.components.PSObject.Properties | Where-Object { $_.Value.license } | ForEach-Object { $_.Value.license } | Sort-Object -Unique)
$licenseBad = @()

foreach ($lic in $licenseNeeded) {
    $f = Join-Path $licenseDir "$lic.txt"
    if (-not (Test-Path -LiteralPath $f)) {
        Fail "缺少 $lic.txt"
        $licenseBad += $lic
        continue
    }
    $len = (Get-Item -LiteralPath $f).Length
    if ($len -lt 200) {
        Fail "$lic.txt 只有 $len 字节，不像完整文本"
        $licenseBad += $lic
        continue
    }
    Ok "$lic.txt  $len 字节"
    $totalBytes += $len
}

if ($licenseBad.Count -gt 0) {
    Write-Host ''
    Fail 'GPL-3.0 再分发必须随附完整许可证文本，缺了不能发布。'
    Info '先运行 tools\build\Fetch-Vendor.ps1 补齐。'
    exit 1
}

# ---------- 4. 组装 staging ----------
Write-Host ''
Write-Host '[3] 组装 staging' -ForegroundColor Cyan

$stage = Join-Path $DistDir "build\$version"
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

# payload 的全部内容直接铺到 zip 根，解压后就能看到 安装.cmd
Copy-Item -Path (Join-Path $Payload '*') -Destination $stage -Recurse -Force
Ok "payload → staging"

# manifest 供 Install.ps1 校验版本与哈希
$stageManifestDir = Join-Path $stage 'manifest'
New-Item -ItemType Directory -Path $stageManifestDir -Force | Out-Null
Copy-Item -LiteralPath $Manifest -Destination (Join-Path $stageManifestDir 'components.json') -Force
Ok 'manifest → staging\manifest\components.json'

# 使用说明：用户第一次打开 zip 会先看这个
$readme = @"
Sunshine 局域网串流 · 离线安装包 v$version
================================================================

本包已包含全部所需文件，安装过程不需要联网。
第三方组件的许可证全文见 licenses\ 目录。

一、安装宿主（需要管理员）
    双击  安装.cmd
    装完即可用：Web UI 已是中文（locale=zh），局域网安全基线、
    显示与编码开关全部写入，服务自启并就绪，不需要进设置页手选。

二、启用虚拟显示器
    双击  安装虚拟屏.cmd
    装完会把 Sunshine 切到虚拟屏捕获；单屏笔记本若 DXGI 暂时看不到
    新屏，脚本会自动执行一次 DisplaySwitch /extend 让它出现。
    连上时只保留虚拟屏（物理屏息屏），断开自动回滚物理屏。

    前提：Moonlight 客户端打开「优化游戏设置」，否则客户端请求的
    分辨率不会切换，画面会停在预设的第一档。

    分辨率是静态预设（conf\vdd-resolutions.txt），客户端请求表外档位
    会静默失败。新设备请先确认它的分辨率在表里。

三、分辨率卡片（可选，推荐）
    双击  安装分辨率卡片.cmd
    会多出 6 张「桌面 · 1080p / 2K / 4K / 720p / 手机 / 平板」卡。
    Moonlight 按卡分别记住分辨率：在每张卡的设置里选好对应档位、
    打开「优化游戏设置」，之后点卡即用该分辨率，不用每次改设置。
    前提：档位必须在 conf\vdd-resolutions.txt 里，表外会静默失败。

四、客户端
    vendor\$moonAsset  解压即用（Windows 端）。
    手机 / 平板 / 电视请自行在各自应用商店安装 Moonlight。
    已知可用：Moonlight for Android（含 axixi 第三方构建）。

五、出问题时
    物理屏黑掉不恢复   → 双击  恢复显示.cmd
    想退回物理屏方案   → 双击  恢复基线.cmd
    只是想看当前状态   → powershell -ExecutionPolicy Bypass -File scripts\Get-Baseline.ps1
    驱动日志           → C:\VirtualDisplayDriver\Logs\

六、目录说明
    scripts\    全部 PowerShell 脚本
    conf\       虚拟屏分辨率预设（按设备名列出）
    licenses\   第三方许可证全文
    vendor\     随包二进制（安装包与驱动）

由 tools\build\Build-Package.ps1 生成于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $stage '使用说明.txt'), $readme, $utf8NoBom)
Ok '使用说明.txt'

$stageFiles = @(Get-ChildItem -LiteralPath $stage -Recurse -File)
$stageBytes = ($stageFiles | Measure-Object -Property Length -Sum).Sum
Info "staging: $($stageFiles.Count) 个文件，$([math]::Round($stageBytes/1MB,2)) MB"

# ---------- 5. 打包 ----------
Write-Host ''
Write-Host '[4] 打 zip' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }
$zipName = "sunshine-lan-streaming-$version.zip"
$zipPath = Join-Path $DistDir $zipName
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath -CompressionLevel Optimal
$sw.Stop()

$zipItem = Get-Item -LiteralPath $zipPath
$zipSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
Ok ("$zipName  {0} MB  耗时 {1:N1}s" -f [math]::Round($zipItem.Length/1MB,2), $sw.Elapsed.TotalSeconds)

# ---------- 6. 解压自检 ----------
# 用 Expand-Archive 而不是 ZipFile.OpenRead：本机策略禁止 Add-Type，
# 而且真解一遍还能顺带验证中文文件名在解压后是否正常。
Write-Host ''
Write-Host '[5] 解压自检' -ForegroundColor Cyan

$check = Join-Path $env:TEMP ("pkgcheck-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $check -Force

    $must = @(
        '安装.cmd',
        '安装虚拟屏.cmd',
        '安装分辨率卡片.cmd',
        '使用说明.txt',
        'manifest\components.json',
        'scripts\Install.ps1',
        'scripts\Install-Vdd.ps1',
        'scripts\Install-Cards.ps1',
        'scripts\_Baseline.ps1',
        'conf\vdd-resolutions.txt',
        'conf\devices\defaults.json'
    )
    foreach ($lic in $licenseNeeded) { $must += ('licenses\' + $lic + '.txt') }
    foreach ($n in @($m.components.PSObject.Properties.Name)) {
        $must += ('vendor\' + $m.components.$n.asset)
    }

    $lost = @()
    foreach ($rel in $must) {
        if (-not (Test-Path -LiteralPath (Join-Path $check $rel))) { $lost += $rel }
    }

    if ($lost.Count -gt 0) {
        Fail "解压后缺少 $($lost.Count) 个关键文件："
        $lost | ForEach-Object { Info "  - $_" }
        exit 1
    }
    Ok "关键文件齐全（$($must.Count) 项），中文文件名正常"
}
catch {
    Fail "解压自检失败：$($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $check) { Remove-Item -LiteralPath $check -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------- 7. 汇总 ----------
if (-not $NoClean) {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '==== 出包完成 ====' -ForegroundColor Green
Info "文件  : $zipPath"
Info "大小  : $([math]::Round($zipItem.Length/1MB,2)) MB"
Info "SHA256: $zipSha"
Write-Host ''
Info '分发时请连同上面的 SHA256 一起给出，接收方可自行核对。'
exit 0
