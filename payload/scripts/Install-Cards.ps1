#Requires -Version 5.1
<#
.SYNOPSIS
    生成 Moonlight 分辨率卡片：每张卡名字带分辨率，客户端按卡独立记住分辨率设置。

.DESCRIPTION
    原理：Moonlight 把分辨率/帧率/码率按「应用卡片」分别保存。只要 Sunshine
    的 apps.json 里有多个名字不同的 Desktop 卡，就能在 Moonlight 里给每张卡
    设一次分辨率，之后点卡即用对应档位。

    注意：本脚本不写 prep 命令。Sunshine v2026.516 的 launch_session 分辨率
    完全来自客户端的 mode 参数（见 nvhttp.cpp make_launch_session），app prep
    在 configure_display / probe_encoders 之后才跑，改不了显示模式。
    分辨率切换由 dd_resolution_option = auto 完成，静态表是候选集，
    见 docs/Moonlight卡片分辨率.md。

    幂等：已有同名卡不重复添加；「Desktop」「Steam Big Picture」保留不动。

.PARAMETER Force
    同名卡存在时也用当前定义覆盖（默认跳过，保护用户在 Moonlight 侧的设置习惯）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install-Cards.ps1
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

$ConfDir  = Join-Path $env:ProgramFiles 'Sunshine\config'
$AppsFile = Join-Path $ConfDir 'apps.json'
$backup   = Join-Path $ConfDir "apps.json.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"

Write-Host '==== Moonlight 分辨率卡片 ===='
Write-Host "设备      $(Get-DeviceId)"
Write-Host "配置文件  $AppsFile"
Write-Host ''
Assert-Admin -Hint '请从 payload\安装分辨率卡片.cmd 启动。'

if (-not (Test-Path -LiteralPath $AppsFile)) {
    Write-Host "FAIL 找不到 $AppsFile，请先安装 Sunshine。"
    exit 2
}

# 卡片名 = 设备名 + 分辨率@刷新率，一眼能看出这张卡对应哪台客户端、哪个档位。
# Moonlight 按卡保存分辨率设置；卡片名就是识别依据，不要用「1080p」这类会被
# 误读成"分辨率已固定"的写法。
$cards = @(
    [pscustomobject]@{ Name = 'Find X9 Pro 2772x1272@60'; Note = 'OPPO 手机竖屏原生' }
    [pscustomobject]@{ Name = 'iPhone 17 Pro Max 2868x1320@60'; Note = 'iPhone 竖屏原生' }
    [pscustomobject]@{ Name = 'iPad Pro 12.9 2732x2048@120'; Note = 'iPad 平板' }
    [pscustomobject]@{ Name = 'Switch 底座 1920x1080@60'; Note = 'Switch / 电视 1080p' }
    [pscustomobject]@{ Name = '电视 4K 3840x2160@60'; Note = '4K 大屏' }
    [pscustomobject]@{ Name = '通用 1280x720@60'; Note = '低带宽 / 远距离' }
    [pscustomobject]@{ Name = '通用 2560x1440@60'; Note = '2K 桌面' }
    [pscustomobject]@{ Name = '通用 1440x900@60'; Note = '16:10 笔记本' }
)

try { $json = Get-Content -LiteralPath $AppsFile -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Write-Host "FAIL 解析 apps.json 失败：$($_.Exception.Message)"; exit 2 }

$apps = @($json.apps)
$existing = @{}
foreach ($a in $apps) { $existing[[string]$a.name] = $a }

# 清理 v0.5.4 的旧命名（「桌面 · xxx」）。那一版名字里没有设备名和刷新率，
# 认不出对应哪台客户端；保留会和新卡重复。
$legacy = @($apps | Where-Object { [string]$_.name -like '桌面 · *' })
if ($legacy.Count -gt 0) {
    $apps = @($apps | Where-Object { [string]$_.name -notlike '桌面 · *' })
    foreach ($l in $legacy) { Write-Host "移除旧卡  $($l.name)" }
}

$added = 0
$skipped = 0
foreach ($c in $cards) {
    if ($existing.ContainsKey($c.Name)) {
        if ($Force) {
            $idx = 0
            for ($i = 0; $i -lt $apps.Count; $i++) { if ($apps[$i].name -eq $c.Name) { $idx = $i; break } }
            $apps[$idx] = [pscustomobject]@{ name = $c.Name; 'image-path' = 'desktop.png' }
            Write-Host "覆盖卡片  $c.Name"
        } else {
            Write-Host "已存在    $c.Name（跳过）"
            $skipped++
        }
        continue
    }
    $apps += [pscustomobject]@{ name = $c.Name; 'image-path' = 'desktop.png' }
    Write-Host "新增卡片  $c.Name  ← $($c.Note)"
    $added++
}

Copy-Item -LiteralPath $AppsFile -Destination $backup -Force
Write-Host "备份      $backup"

# 停服务再写，避免它退出时用内存里的旧 apps 覆盖文件
$svc = Get-Service -Name $script:SunshineService -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host '停止服务  进行中…'
    Stop-Service -Name $script:SunshineService -Force -ErrorAction Stop
    (Get-Service -Name $script:SunshineService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
}

$out = [ordered]@{ env = $(if ($json.env) { $json.env } else { @{} }); apps = @($apps) }
$text = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($AppsFile, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "写入      OK（$($apps.Count) 张卡，新增 $added，跳过 $skipped）"

Start-Service -Name $script:SunshineService -ErrorAction Stop
(Get-Service -Name $script:SunshineService).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
$live = @(Get-ListeningPorts)
Write-Host "常驻端口  $($live -join ', ')"

Write-Host ''
Write-Host '==== 完成 ===='
Write-Host '下一步（在 Moonlight 里，每个设备各做一次）：'
Write-Host '  1. 点开每张「桌面 · xxx」卡的设置'
Write-Host '  2. 把分辨率设成卡名对应的档位，帧率按需'
Write-Host '  3. 打开「优化游戏设置」——不开的话 Sunshine 不改分辨率'
Write-Host '  4. 之后点卡即用该档位，不需要每次改设置'
exit 0
