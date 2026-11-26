#Requires -Version 5.1
<#
.SYNOPSIS
    一键卸载：虚拟屏、Sunshine、ViGEmBus、卡片、防火墙与部署产物，恢复物理屏。
.DESCRIPTION
    顺序按实机踩坑结果固定，避免把服务/驱动删成 STOP_PENDING：
      1. 虚拟屏：调用 Install-Vdd.ps1 -Uninstall，恢复物理屏并移除驱动；
      2. Sunshine：停服务 → msiexec /x（清单里的 product_code）→ 清残留；
      3. ViGEmBus：删设备节点 → 停服务 → 删服务 → 删驱动包；
      4. 防火墙、快捷方式、自启动项、C:\VirtualDisplayDriver、状态目录。

    只删除本方案安装/写入的内容，不动个人文件、不碰 Oray/RayLink 等其他虚拟屏。
    最后弹出结果窗口；保存 TXT 成功后连同控制台一起关闭。
.PARAMETER Yes
    跳过确认（入口 一键卸载.cmd 已在控制台确认过）。
.PARAMETER KeepViGEmBus
    保留 ViGEmBus（其他手柄工具也在使用它时）。
.PARAMETER KeepState
    保留 C:\ProgramData\sunshine-lan-streaming（保留卸载与安装记录）。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Uninstall.ps1 -Yes
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$KeepViGEmBus,
    [switch]$KeepState
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

$script:Failures = @()
$script:Warnings = @()
$script:Checks   = @()
function Note($m) { Write-Host "         $m" }
function Good($m) { Write-Host "    OK   $m" -ForegroundColor Green; $script:Checks += $m }
function Warn($m) { Write-Host "    WARN $m" -ForegroundColor Yellow; $script:Warnings += $m }
function Bad($m)  { Write-Host "    FAIL $m" -ForegroundColor Red; $script:Failures += $m }

Write-Host ''
Write-Host '==== 一键卸载：虚拟屏 → Sunshine → ViGEmBus → 残留 ====' -ForegroundColor Cyan
Write-Host "设备      $(Get-DeviceId)"
Write-Host ''
Assert-Admin -Hint '请双击包内的「一键卸载.cmd」，由它提权运行。'

if (-not $Yes) {
    $answer = Read-Host '输入 Y 确认卸载（其他任意键取消）'
    if ($answer -ne 'Y' -and $answer -ne 'y') {
        Write-Host '已取消。' -ForegroundColor Yellow
        exit 2
    }
}

$Manifest    = Join-Path (Split-Path $PSScriptRoot -Parent) 'manifest\components.json'
$ProgramData = Join-Path $env:ProgramData 'sunshine-lan-streaming'
$msiProduct  = $null
if (Test-Path -LiteralPath $Manifest) {
    try {
        $m = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
        $msiProduct = [string]$m.components.sunshine.product_code
    } catch { }
}

# ---------- 1. 虚拟屏 ----------
Write-Host ''
Write-Host '[1/4] 虚拟屏'
$vddDevices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                Where-Object { $_.FriendlyName -match 'VDD by MTT' -or ($_.HardwareID -join ';') -match 'MttVDD' })
if ($vddDevices.Count -gt 0 -or (Test-Path -LiteralPath 'C:\VirtualDisplayDriver')) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-Vdd.ps1') -Uninstall
    if ($LASTEXITCODE -eq 0) { Good '虚拟屏已移除，物理屏已恢复' }
    else { Bad "虚拟屏卸载未通过（退出码 $LASTEXITCODE）" }
} else {
    Good '虚拟屏未安装，跳过'
}
# 驱动包与设备残留（Install-Vdd 正常时会清掉，这里兜底）
foreach ($d in $vddDevices) {
    & pnputil.exe /remove-device $d.PNPDeviceID 2>&1 | ForEach-Object { Note $_ }
}
$drv = & pnputil.exe /enum-drivers 2>&1
$pub = $null
foreach ($line in $drv) {
    if ($line -match '(?:发布名称|Published Name)[：:]\s*(\S+\.inf)') { $pub = $Matches[1] }
    elseif ($line -match '(?:原始名称|Original Name)[：:]\s*(mttvdd\.inf)') { if ($pub) { & pnputil.exe /delete-driver $pub /uninstall /force 2>&1 | ForEach-Object { Note $_ } } }
}

# ---------- 2. Sunshine ----------
Write-Host ''
Write-Host '[2/4] Sunshine'
$svc = Get-Service -Name $script:SunshineService -ErrorAction SilentlyContinue
if ($svc) {
    try {
        Stop-Service -Name $script:SunshineService -Force -ErrorAction Stop
        (Get-Service -Name $script:SunshineService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
        Note '服务已停止'
    } catch { Warn "停止服务失败：$($_.Exception.Message)" }
}

if (-not $msiProduct) {
    # 清单缺失时从卸载表反查产品码
    $app = @(
        Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^Sunshine' } | Select-Object -First 1
    )
    if ($app -and $app.PSChildName -match '^\{') { $msiProduct = $app.PSChildName }
}
if ($msiProduct) {
    $msiLog = Join-Path $env:TEMP ("sunshine-uninstall-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $p = Start-Process -FilePath 'msiexec.exe' -Wait -PassThru -ArgumentList @(
        '/x', $msiProduct, '/qn', '/norestart', '/l*v', "`"$msiLog`"")
    if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { Good 'Sunshine 已卸载（MSI）' }
    elseif ($p.ExitCode -eq 1605) { Warn 'MSI 记录显示已不存在（1605），按残留清理' }
    else { Bad "Sunshine 卸载失败（msiexec 退出码 $($p.ExitCode)），日志 $msiLog" }
} else {
    Warn '未找到 Sunshine 的 MSI 产品码，按残留清理'
}

# 服务/目录残留
$svc = Get-Service -Name $script:SunshineService -ErrorAction SilentlyContinue
if ($svc) {
    & sc.exe delete $script:SunshineService 2>&1 | ForEach-Object { Note $_ }
    Start-Sleep -Seconds 1
}
foreach ($dir in @((Join-Path $env:ProgramFiles 'Sunshine'), (Join-Path $env:ProgramData 'Sunshine'))) {
    if (Test-Path -LiteralPath $dir) {
        try { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop; Note "已删除 $dir" }
        catch { Warn "未能删除 $dir：$($_.Exception.Message)" }
    }
}
if (-not (Get-Service -Name $script:SunshineService -ErrorAction SilentlyContinue) -and
    -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Sunshine'))) {
    Good 'Sunshine 服务与程序目录已清理'
}

# ---------- 3. ViGEmBus ----------
Write-Host ''
Write-Host '[3/4] ViGEmBus'
if ($KeepViGEmBus) {
    Good '已按参数保留 ViGEmBus'
} else {
    $vigemSvc = Get-Service -Name 'ViGEmBus' -ErrorAction SilentlyContinue
    $vigemReg = Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\ViGEmBus'
    if (-not $vigemSvc -and -not $vigemReg) {
        Good 'ViGEmBus 未安装，跳过'
    } else {
        # 先删设备节点，避免"驱动正在使用"导致服务删不掉
        $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                     Where-Object { $_.Service -eq 'ViGEmBus' -or $_.FriendlyName -match 'ViGEm' })
        foreach ($d in $devices) {
            & pnputil.exe /remove-device $d.PNPDeviceID 2>&1 | ForEach-Object { Note $_ }
        }
        if ($vigemSvc -and $vigemSvc.Status -ne 'Stopped') {
            & sc.exe stop ViGEmBus 2>&1 | ForEach-Object { Note $_ }
            for ($i = 0; $i -lt 15; $i++) {
                Start-Sleep -Seconds 1
                $vigemSvc = Get-Service -Name 'ViGEmBus' -ErrorAction SilentlyContinue
                if (-not $vigemSvc -or $vigemSvc.Status -eq 'Stopped') { break }
            }
        }
        if ($vigemSvc) { & sc.exe delete ViGEmBus 2>&1 | ForEach-Object { Note $_ } }
        Start-Sleep -Seconds 1
        # 驱动包
        $pub = $null
        foreach ($line in (& pnputil.exe /enum-drivers 2>&1)) {
            if ($line -match '(?:发布名称|Published Name)[：:]\s*(\S+\.inf)') { $pub = $Matches[1] }
            elseif ($line -match '(?:原始名称|Original Name)[：:]\s*(vigembus\.inf)') {
                if ($pub) { & pnputil.exe /delete-driver $pub /uninstall /force 2>&1 | ForEach-Object { Note $_ } }
            }
        }
        $still = Get-Service -Name 'ViGEmBus' -ErrorAction SilentlyContinue
        if ($still -and $still.Status -eq 'StopPending') {
            Warn 'ViGEmBus 服务处于删除挂起（StopPending），重启后自动消失；再次部署前需重启'
        } elseif ($still) {
            Bad "ViGEmBus 服务仍存在（$($still.Status)）"
        } else {
            Good 'ViGEmBus 已移除'
        }
    }
}

# ---------- 4. 防火墙、快捷方式、状态目录 ----------
Write-Host ''
Write-Host '[4/4] 防火墙与残留'
$fw = @(Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Sunshine*' })
if ($fw.Count -gt 0) {
    $fw | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Good "已清理防火墙规则 $($fw.Count) 条"
} else {
    Good '无 Sunshine 防火墙规则'
}

$lnkDirs = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('StartMenu'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
)
$lnkCount = 0
foreach ($d in $lnkDirs) {
    if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
    Get-ChildItem -LiteralPath $d -Filter '*Sunshine*' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        $lnkCount++
    }
}
foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($props) {
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -notmatch '^PS' -and ([string]$p.Value -match 'sunshine')) {
                Remove-ItemProperty -LiteralPath $key -Name $p.Name -ErrorAction SilentlyContinue
                $lnkCount++
            }
        }
    }
}
if ($lnkCount -gt 0) { Good "已清理快捷方式/自启动 $lnkCount 项" } else { Good '无快捷方式或自启动残留' }

if (Test-Path -LiteralPath 'C:\VirtualDisplayDriver') {
    try { Remove-Item -LiteralPath 'C:\VirtualDisplayDriver' -Recurse -Force -ErrorAction Stop; Good '已删除 C:\VirtualDisplayDriver' }
    catch { Warn "未能删除 C:\VirtualDisplayDriver：$($_.Exception.Message)" }
}

if (-not $KeepState) {
    if (Test-Path -LiteralPath $ProgramData) {
        try { Remove-Item -LiteralPath $ProgramData -Recurse -Force -ErrorAction Stop; Good '已删除部署状态目录' }
        catch { Warn "未能删除 $ProgramData：$($_.Exception.Message)" }
    } else {
        Good '无部署状态目录'
    }
}

# ---------- 结果弹窗 ----------
$rc = 0
if ($script:Failures.Count -gt 0) { $rc = 1 }
Write-Host ''
Write-Host "==== 卸载完成：失败 $($script:Failures.Count) 项，警告 $($script:Warnings.Count) 项 ====" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })

$resultFile = Join-Path $env:TEMP ("sunshine-uninstall-result-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$payload = [ordered]@{
    mode      = 'uninstall'
    timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    device_id = Get-DeviceId
    host      = $env:COMPUTERNAME
    checks    = @($script:Checks)
    warnings  = @($script:Warnings)
    failures  = @($script:Failures)
}
[System.IO.File]::WriteAllText($resultFile, ($payload | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Show-Result.ps1') -ResultFile $resultFile -ExitCode $rc
# Show-Result 保存 TXT 返回 0，直接关闭返回 3；卸载没有需要保留的日志，
# 两种都算完成，只有真正有失败项时才让入口暂停。
Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
if ($rc -ne 0) { exit 1 }
exit 0
