#Requires -Version 5.1
<#
.SYNOPSIS
    按 manifest 下载并校验随包第三方资产，为打包做准备。

.DESCRIPTION
    这是整条链路里**唯一允许联网的脚本**。产物落在 payload\vendor\ 与
    payload\licenses\，随后由 Build-Package.ps1 打进 zip；
    安装阶段（用户解压后双击 .cmd）全程零网络。

    为什么把下载挪到构建阶段：
      安装时联网有三个具体问题——GitHub CDN 会间歇性 502、大文件容易中途断流、
      而且目标机可能根本没有外网。实测 VDD 的 71 MB 包第一次只下到 26 MB，
      哈希对不上，装到一半才发现。把它锁在构建阶段，这些风险就只影响出包的人。

    幂等：已存在且 SHA256 匹配的资产直接跳过，可反复执行。

.PARAMETER Force
    忽略已有文件，强制重新下载。

.PARAMETER ManifestPath
    manifest/components.json 路径。默认仓库根下的那份。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build\Fetch-Vendor.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\build\Fetch-Vendor.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$VendorDir  = Join-Path $RepoRoot 'payload\vendor'
$LicenseDir = Join-Path $RepoRoot 'payload\licenses'

if (-not $ManifestPath) { $ManifestPath = Join-Path $RepoRoot 'manifest\components.json' }

$MaxAttempts = 5

function Info($m) { Write-Host "    $m" -ForegroundColor Gray }
function Ok($m)   { Write-Host "    OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    WARN $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "    FAIL $m" -ForegroundColor Red }

<#
    把 GitHub 的 blob 页面地址换成 raw 文本地址。
    components.json 里存的是给人看的 blob 链接（要能直接点开核对），
    但下载许可证得用 raw，否则拿到的是 HTML。
#>
function ConvertTo-RawUrl {
    param([string]$Url)
    if ($Url -match '^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$') {
        return "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])/$($Matches[3])"
    }
    return $Url
}

<#
    带续传和重试的下载。curl.exe 在 Windows 10 1803+ 自带。

    用 curl 而不是 Invoke-WebRequest 的理由：断流后能用 -C - 从断点续，
    不必从头再来；Invoke-WebRequest 只能重下整个文件。
#>
function Invoke-Download {
    param(
        [string]$Url,
        [string]$OutPath,
        [long]$ExpectedSize = 0
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $curlArgs = @('--fail', '--location', '--silent', '--show-error',
                      '--retry', '3', '--retry-delay', '2', '--retry-all-errors',
                      '--connect-timeout', '20', '--max-time', '900')

        # 已有部分文件时续传，否则会被 curl 当成"从第 0 字节开始"而报错
        if ((Test-Path -LiteralPath $OutPath) -and ((Get-Item -LiteralPath $OutPath).Length -gt 0)) {
            $curlArgs += @('-C', '-')
        }
        $curlArgs += @('-o', $OutPath, $Url)

        Info "下载 (第 $attempt/$MaxAttempts 次): $Url"

        # 必须临时降级 ErrorActionPreference：
        # curl 把 502 之类的失败写到 stderr，PS 5.1 在 Stop 模式下会把它包成
        # NativeCommandError 抛出，直接打断整个重试循环——重试次数形同虚设。
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & curl.exe @curlArgs 2>&1 | ForEach-Object {
                $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
                if ($line -and $line.Trim()) { Info "  $($line.Trim())" }
            }
            $rc = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $prevEap
        }

        if ($rc -eq 0 -or $rc -eq 33) {
            # curl 33 = 服务器不支持 Range，等同于重下了完整文件
            if (Test-Path -LiteralPath $OutPath) {
                $len = (Get-Item -LiteralPath $OutPath).Length
                if ($ExpectedSize -le 0 -or $len -eq $ExpectedSize) { return $true }
                Warn "大小不符：实际 $len，期望 $ExpectedSize（可能没下完）"
            }
        } else {
            Warn "curl 返回 $rc"
        }

        # 大小不符时删掉，避免续传接在坏数据后面
        if ($attempt -lt $MaxAttempts) {
            if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
            Start-Sleep -Seconds ([Math]::Min(3 * $attempt, 15))
        }
    }
    return $false
}

<#
    下载小体积文本资产（许可证全文）。

    单独用 Invoke-WebRequest 而不是 curl：许可证只有几十 KB，不需要断点续传，
    而 curl 在本机对 raw.githubusercontent.com 的小文件反而偶发失败。
    大文件（安装包、驱动包）仍走 Invoke-Download 的续传路径。
#>
function Save-TextAsset {
    param([string]$Url, [string]$OutPath)

    for ($i = 1; $i -le 4; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
            if ((Test-Path -LiteralPath $OutPath) -and ((Get-Item -LiteralPath $OutPath).Length -gt 200)) {
                return $true
            }
        } catch { }
        if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force -ErrorAction SilentlyContinue }
        if ($i -lt 4) { Start-Sleep -Seconds 2 }
    }
    return $false
}

Write-Host ''
Write-Host '==== 准备随包资产 ====' -ForegroundColor White
Info "仓库根: $RepoRoot"
Info "manifest: $ManifestPath"
Write-Host ''

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Fail "找不到 $ManifestPath"
    exit 1
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.components) {
    Fail 'manifest 里没有 components 段'
    exit 1
}

foreach ($d in @($VendorDir, $LicenseDir)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

$failures = @()
$licenses = @{}   # license 名 -> 来源组件（用于生成映射说明）

# ---------- 组件资产 ----------
foreach ($name in @($manifest.components.PSObject.Properties.Name)) {
    $c = $manifest.components.$name
    Write-Host "[$name] $($c.version)" -ForegroundColor Cyan

    if (-not $c.asset -or -not $c.url) {
        Warn 'manifest 缺少 asset 或 url，跳过'
        continue
    }

    $target = Join-Path $VendorDir $c.asset
    $expectedSha = if ($c.sha256) { ([string]$c.sha256).ToLower() } else { $null }
    $expectedSize = if ($c.size_bytes) { [long]$c.size_bytes } else { 0 }

    # 已存在且哈希匹配就跳过
    if (-not $Force -and (Test-Path -LiteralPath $target) -and $expectedSha) {
        $cur = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower()
        if ($cur -eq $expectedSha) {
            Ok "$($c.asset) 已存在且校验通过，跳过（$([math]::Round((Get-Item $target).Length/1MB,2)) MB）"
            if ($c.license) { $licenses[$c.license] = @() + $licenses[$c.license] + $name }
            continue
        }
        Warn "已存在但哈希不符，重新下载"
        Remove-Item -LiteralPath $target -Force
    }

    if (-not (Invoke-Download -Url $c.url -OutPath $target -ExpectedSize $expectedSize)) {
        Fail "$($c.asset) 下载失败"
        $failures += $name
        continue
    }

    if ($expectedSha) {
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expectedSha) {
            Fail "$($c.asset) 哈希不符"
            Info "  实际 $actual"
            Info "  期望 $expectedSha"
            Remove-Item -LiteralPath $target -Force
            $failures += $name
            continue
        }
    }

    $sizeMb = [math]::Round((Get-Item -LiteralPath $target).Length / 1MB, 2)
    Ok "$($c.asset)  $sizeMb MB  SHA256 校验通过"
    if ($c.license) { $licenses[$c.license] = @() + $licenses[$c.license] + $name }
}

# ---------- 许可证全文 ----------
# GPL-3.0 再分发必须随附完整文本，MIT 要求保留版权声明，
# 所以不能只写个链接了事。
Write-Host ''
Write-Host '[licenses] 许可证全文' -ForegroundColor Cyan

foreach ($lic in @($licenses.Keys)) {
    if (-not $lic) { continue }

    $fileName = "$lic.txt"
    $target   = Join-Path $LicenseDir $fileName

    if ((Test-Path -LiteralPath $target) -and -not $Force) {
        Ok "$fileName 已存在，跳过"
        continue
    }

    # 找到第一个声明了这个许可证的组件，用它的 license_url
    $src = $null
    foreach ($compName in @($licenses[$lic])) {
        $u = $manifest.components.$compName.license_url
        if ($u) { $src = $u; break }
    }

    if (-not $src) {
        Warn "$lic 没有 license_url，无法取全文"
        continue
    }

    $rawUrl = ConvertTo-RawUrl -Url $src
    Write-Host "    $fileName"
    Info "来源: $rawUrl"
    if (-not (Save-TextAsset -Url $rawUrl -OutPath $target)) {
        Fail "$fileName 下载失败：$rawUrl"
        $failures += "license:$lic"
        continue
    }

    $len = (Get-Item -LiteralPath $target).Length
    if ($len -lt 200) {
        Warn "$fileName 只有 $len 字节，可能不是许可证全文"
    } else {
        Ok "$fileName  $len 字节"
    }
}

# ---------- 许可证映射说明 ----------
$readme = Join-Path $LicenseDir 'README.txt'
$lines = @(
    '本目录随包分发第三方组件的许可证全文，供再分发合规使用。',
    '',
    '组件与许可证对应关系：'
)
foreach ($name in @($manifest.components.PSObject.Properties.Name)) {
    $c = $manifest.components.$name
    if ($c.license) {
        $lines += "- $name $($c.version)  →  $($c.license).txt"
        $lines += "    source: $($c.source_url)"
    }
}
$lines += ''
$lines += "生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += '由 tools/build/Fetch-Vendor.ps1 生成，请勿手工编辑。'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($readme, (($lines -join "`r`n") + "`r`n"), $utf8)
Ok "README.txt 已生成（组件-许可证映射）"

# ---------- 汇总 ----------
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "==== 失败 $($failures.Count) 项 ====" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host '打包会因资产缺失而中止。请排查网络后重跑，已成功的项会自动跳过。'
    exit 1
}

Write-Host '==== 全部就绪 ====' -ForegroundColor Green
$total = (Get-ChildItem -LiteralPath $VendorDir -File | Measure-Object -Property Length -Sum).Sum
Info "payload\vendor\ 共 $((Get-ChildItem -LiteralPath $VendorDir -File).Count) 个文件，合计 $([math]::Round($total/1MB,2)) MB"
exit 0
