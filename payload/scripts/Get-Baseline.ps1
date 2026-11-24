#Requires -Version 5.1
<#
.SYNOPSIS
    只读体检：按 docs/配置清单.md 的 36 项采集当前值，输出状态表。

.DESCRIPTION
    M2 产物。不需要管理员权限，不修改任何东西。
    能自动采集的项给出实测值与状态；依赖外部条件（路由器、手机、手柄）的项标为「需人工」。

.PARAMETER Json
    以 JSON 输出，便于其他脚本消费。

.PARAMETER Quiet
    只输出汇总行，不打印明细表。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Get-Baseline.ps1
    powershell -ExecutionPolicy Bypass -File Get-Baseline.ps1 -Json
#>
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'
$rows = New-Object System.Collections.ArrayList

function Add-Row {
    param([string]$Id, [string]$Item, [string]$Actual, [string]$Status, [string]$Note = '')
    [void]$rows.Add([pscustomobject]@{
        Id     = $Id
        Item   = $Item
        Actual = $Actual
        Status = $Status
        Note   = $Note
    })
}

$Conf = Join-Path $env:ProgramFiles 'Sunshine\config\sunshine.conf'
$ConfData = @{}
if (Test-Path $Conf) {
    foreach ($line in Get-Content $Conf -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') {
            $ConfData[$Matches[1]] = $Matches[2]
        }
    }
}

# ---------- A 版本与来源 ----------
$inst = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                         'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Sunshine*' } | Select-Object -First 1
if ($inst) {
    Add-Row 'A-01' '宿主版本' "$($inst.DisplayVersion)" '✅' ''
} else {
    Add-Row 'A-01' '宿主版本' '未安装' '❓' ''
}

# A-02 只在安装包仍在时可校验。zip 装完后包可能已清理，属正常，不算失败。
$msiCandidates = @(
    (Join-Path $PSScriptRoot '..\..\dist\cache\Sunshine-Windows-AMD64-installer.msi'),
    (Join-Path $PSScriptRoot 'Sunshine-Windows-AMD64-installer.msi')
)
$msi = $msiCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($msi) {
    $h = (Get-FileHash $msi -Algorithm SHA256).Hash.ToLower()
    Add-Row 'A-02' '安装包完整性' $h.Substring(0, 12) '✅' '仅显示前 12 位'
} else {
    Add-Row 'A-02' '安装包完整性' '安装包未保留' '⏸' '需要时按 manifest 重新下载'
}

$vdd = @(Get-PnpDevice -Class Display -ErrorAction SilentlyContinue |
         Where-Object { $_.FriendlyName -notmatch 'NVIDIA|Intel|AMD|Radeon' })
if ($vdd.Count -eq 0) {
    Add-Row 'A-03' '虚拟显示适配器' '0 个' '✅' ''
} else {
    Add-Row 'A-03' '虚拟显示适配器' "$($vdd.Count) 个" '⚠️' (($vdd.FriendlyName) -join ' / ')
}

$vigem = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
         Where-Object { $_.DisplayName -match 'ViGEmBus' } | Select-Object -First 1
if ($vigem) { Add-Row 'A-04' '虚拟手柄驱动' "$($vigem.DisplayVersion)" '✅' '' }
else { Add-Row 'A-04' '虚拟手柄驱动' '未安装' '⏸' '无手柄需求则不必装' }

$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon' } | Select-Object -First 1
if ($gpu) { Add-Row 'A-05' '显卡驱动' "$($gpu.DriverVersion)" '✅' $gpu.Name }

# ---------- B 服务 ----------
$svc = Get-Service SunshineService -ErrorAction SilentlyContinue
if ($svc) {
    Add-Row 'B-01' '服务在跑' "$($svc.Status)" $(if ($svc.Status -eq 'Running') { '✅' } else { '⚠️' })
    Add-Row 'B-02' '开机自启' "$($svc.StartType)" $(if ($svc.StartType -eq 'Automatic') { '✅' } else { '⚠️' })
    $wmi = Get-CimInstance Win32_Service -Filter "Name='SunshineService'" -ErrorAction SilentlyContinue
    if ($wmi) {
        Add-Row 'B-03' '运行账户' "$($wmi.StartName)" $(if ($wmi.StartName -eq 'LocalSystem') { '✅' } else { '⚠️' })
    }
} else {
    Add-Row 'B-01' '服务在跑' '服务不存在' '❓'
    Add-Row 'B-02' '开机自启' '服务不存在' '❓'
    Add-Row 'B-03' '运行账户' '服务不存在' '❓'
}

# ---------- C 端口与防火墙 ----------
$listen = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -in 47984..47990 })
$ports = @($listen.LocalPort | Sort-Object -Unique)
$need = @(47984, 47989, 47990)
$missing = @($need | Where-Object { $_ -notin $ports })
if ($missing.Count -eq 0) {
    Add-Row 'C-01' '常驻端口' "$($ports -join ', ')" '✅' ''
} elseif ($ports.Count -gt 0) {
    Add-Row 'C-01' '常驻端口' "$($ports -join ', ')" '⚠️' "缺 $($missing -join ', ')"
} else {
    Add-Row 'C-01' '常驻端口' '无监听' '❓' ''
}

$fw = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'Sunshine' -and $_.Enabled -eq 'True' })
if ($fw.Count -gt 0) { Add-Row 'C-02' '防火墙规则' "$($fw.Count) 条启用" '✅' '' }
else { Add-Row 'C-02' '防火墙规则' '无启用规则' '⚠️' '' }

Add-Row 'C-03' '路由器端口转发' '需人工核对' '❓' '登录路由器确认无 47984-47990 映射'

# ---------- D 网络 ----------
$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
$biz = $ips | Where-Object { $_.InterfaceAlias -notmatch 'ZeroTier|VMware|Loopback|vgate|本地连接' } | Select-Object -First 1
if ($biz) {
    # 只能证明宿主侧地址已识别；"与客户端同一广播域"必须由客户端侧验证，不能在这里判绿
    Add-Row 'D-01' '业务网段' "$($biz.IPAddress)/$($biz.PrefixLength)" '❓' "$($biz.InterfaceAlias)；需客户端侧确认同网段"
} else {
    Add-Row 'D-01' '业务网段' '未识别' '❓' ''
}

if ($ConfData.ContainsKey('origin_web_ui_allowed')) {
    Add-Row 'D-02' 'Web UI 来源' $ConfData['origin_web_ui_allowed'] $(if ($ConfData['origin_web_ui_allowed'] -eq 'lan') { '✅' } else { '⚠️' })
} else { Add-Row 'D-02' 'Web UI 来源' '未设置（默认 wan）' '⚠️' '' }

if ($ConfData.ContainsKey('upnp')) {
    Add-Row 'D-03' 'UPnP' $ConfData['upnp'] $(if ($ConfData['upnp'] -eq 'disabled') { '✅' } else { '⚠️' })
} else { Add-Row 'D-03' 'UPnP' '未设置（默认开启）' '⚠️' '' }

if ($ips.Count -le 1) {
    Add-Row 'D-04' '干扰网卡' '仅 1 个接口' '✅' ''
} else {
    Add-Row 'D-04' '干扰网卡' "$($ips.Count) 个接口" '⚠️' (($ips.InterfaceAlias) -join ', ')
}

# ---------- E 显示 ----------
# 判据是「活动显示输出数」，不是「显卡数」：一块屏可能同时被核显与独显枚举，
# 也可能真的接了两个输出。数错会直接影响 output_name 的选择，所以宁可标出来让人确认。
$activeMon = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue |
               Where-Object { $_.Active -eq $true })
$monNames = @($activeMon | ForEach-Object {
    ($_.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
} | Sort-Object -Unique)
$pos = @(Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution })
$res = ($pos | ForEach-Object { "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)@$($_.CurrentRefreshRate)" } | Sort-Object -Unique) -join ' + '

if ($activeMon.Count -eq 0) {
    Add-Row 'E-01' '活动显示输出' '无活动输出' '⚠️' '无头状态，需外部手段确认'
} elseif ($activeMon.Count -eq 1) {
    Add-Row 'E-01' '活动显示输出' "1 个（$($monNames -join ', ')）" '✅' $res
} else {
    Add-Row 'E-01' '活动显示输出' "$($activeMon.Count) 个" '⚠️' "同名屏多实例: $($monNames -join ', '); $res"
}

if ($ConfData.ContainsKey('output_name')) {
    $on = $ConfData['output_name']
    Add-Row 'E-02' '输出屏绑定' $(if ($on) { $on } else { '空（自动）' }) '✅' ''
} else { Add-Row 'E-02' '输出屏绑定' '空（自动）' '✅' '' }

if ($ConfData.ContainsKey('dd_configuration_option')) {
    $dd = $ConfData['dd_configuration_option']
    Add-Row 'E-03' '内置切屏' $dd $(if ($dd -eq 'disabled') { '✅' } else { '⚠️' }) ''
} else { Add-Row 'E-03' '内置切屏' '未设置（默认 disabled）' '✅' '' }

$hdr = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name EnableHDR -ErrorAction SilentlyContinue
if ($hdr) { Add-Row 'E-04' 'HDR' "$($hdr.EnableHDR)" '❓' '需在显示设置中确认实际状态' }
else { Add-Row 'E-04' 'HDR' '未显式设置' '❓' '需在显示设置中确认' }

$hags = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue
if ($hags) {
    $hs = $hags.HwSchMode
    Add-Row 'E-05' 'HAGS' $(if ($hs -eq 1) { '1（关闭）' } else { "$hs（开启）" }) $(if ($hs -eq 1) { '✅' } else { '⚠️' })
} else {
    Add-Row 'E-05' 'HAGS' '未设置' '❓' 'Win11 可能默认开启，需实测'
}

# ---------- F 编码 ----------
Add-Row 'F-01' '编码器' '需 Web UI 读取' '❓' 'Audio/Video 页确认 nvenc'
Add-Row 'F-02' '码率' '需 Web UI 读取' '❓' ''
Add-Row 'F-03' '帧率' '需 Web UI 读取' '❓' ''
Add-Row 'F-04' '色彩' '需 Web UI 读取' '❓' ''

# ---------- G 冲突软件 ----------
$map = @{ 'G-01' = @('AweSunService', '向日葵'); 'G-02' = @('RayLinkService', 'RayLink'); 'G-03' = @('ToDesk_Service', 'ToDesk') }
foreach ($k in @('G-01', 'G-02', 'G-03')) {
    $name = $map[$k][0]; $label = $map[$k][1]
    $s = Get-Service $name -ErrorAction SilentlyContinue
    if (-not $s) { Add-Row $k $label '未安装' '✅' '' }
    elseif ($s.Status -eq 'Running') { Add-Row $k $label 'Running' '⚠️' '串流前应停用' }
    else { Add-Row $k $label "$($s.Status)" '✅' '' }
}

# ---------- H 电源与系统 ----------
$pcfg = (powercfg /a) -join "`n"
if ($pcfg -match '待机 \(S3\)' -or $pcfg -match '休眠') {
    Add-Row 'H-01' '睡眠/休眠' '可用' '⚠️' '串流宿主应禁用'
} else { Add-Row 'H-01' '睡眠/休眠' '已禁用' '✅' '' }
if ($pcfg -match '快速启动') {
    Add-Row 'H-02' '快速启动' '可用（即开启）' '⚠️' ''
} else { Add-Row 'H-02' '快速启动' '已关闭' '✅' '' }

$sac = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue
if ($sac) {
    Add-Row 'H-03' '智能应用控制' "$($sac.VerifiedAndReputablePolicyState)" $(if ($sac.VerifiedAndReputablePolicyState -eq 0) { '✅' } else { '⚠️' })
} else { Add-Row 'H-03' '智能应用控制' '未设置' '✅' '' }

# ---------- I / J 需人工 ----------
Add-Row 'I-01' '客户端版本' '需手机确认' '❓' 'Moonlight 需 ≥ 6.2.0'
Add-Row 'I-02' '客户端分辨率' '需手机确认' '❓' ''
Add-Row 'I-03' '客户端网络' '需手机确认' '❓' ''
Add-Row 'J-01' '配置快照' '需人工' '❓' 'config 目录备份'
Add-Row 'J-02' '显示快照' '需人工' '❓' '两份 cfg'
Add-Row 'J-03' '恢复演练' '需人工' '❓' ''

# ---------- 输出 ----------
$ok = @($rows | Where-Object { $_.Status -eq '✅' }).Count
$warn = @($rows | Where-Object { $_.Status -eq '⚠️' }).Count
$unk = @($rows | Where-Object { $_.Status -in @('❓', '⏸') }).Count

if ($Json) {
    [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        host      = $env:COMPUTERNAME
        summary   = [pscustomobject]@{ ok = $ok; warn = $warn; unknown = $unk; total = $rows.Count }
        checks    = $rows
    } | ConvertTo-Json -Depth 5
    exit 0
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "==== 配置体检 · $env:COMPUTERNAME · $(Get-Date -Format 'yyyy-MM-dd HH:mm') ====" -ForegroundColor White
    Write-Host ""
    # 逐行输出而非 Format-Table：中文与符号混排时 Format-Table 的列宽计算会错位
    foreach ($r in $rows) {
        $color = switch ($r.Status) {
            '✅'    { 'Green' }
            '⚠️'    { 'Yellow' }
            '⏸'    { 'DarkGray' }
            default { 'Gray' }
        }
        $line = "{0}  {1}  |  {2}  |  {3}" -f $r.Id, $r.Item, $r.Actual, $r.Status
        if ($r.Note) { $line = "$line  |  $($r.Note)" }
        Write-Host $line -ForegroundColor $color
    }
    Write-Host ""
}

Write-Host ("合格 {0} · 偏离 {1} · 待测 {2} · 共 {3}" -f $ok, $warn, $unk, $rows.Count) -ForegroundColor $(if ($warn -gt 0) { 'Yellow' } else { 'Green' })
exit 0
