#Requires -Version 5.1
<#
.SYNOPSIS
    一键部署：安装宿主 → 启用虚拟屏 → 分辨率卡片，最后统一弹出结果。
.DESCRIPTION
    分步入口（安装.cmd / 安装虚拟屏.cmd / 安装分辨率卡片.cmd）保持不变；
    本脚本只是按顺序调用同一个目录下的 Install.ps1、Install-Vdd.ps1、
    Install-Cards.ps1，并把各步退出码合并进 install-result.json，交给
    Show-Result.ps1 展示。

    自适应行为完全由子脚本决定：Sunshine/ViGEmBus 已装则只同步；
    单屏/多屏、物理屏布局、虚拟屏是否存在都由各脚本自行判断。
    宿主安装失败时跳过后续两步；虚拟屏或卡片失败不影响其它步骤完成，
    所有失败项都会在结果窗口中列出。
.PARAMETER Username
    Sunshine Web UI 用户名，默认 admin；未提供时交互询问。
.PARAMETER Password
    Sunshine Web UI 密码；未提供时交互询问，直接回车随机生成 16 位。
.PARAMETER WithWebPanel
    额外安装按需免登录面板：只把面板脚本复制到 ProgramData；
    不创建桌面快捷方式、不注册服务、不开机自启。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File OneClick.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File OneClick.ps1 -WithWebPanel
#>
[CmdletBinding()]
param(
    [string]$Username = '',
    [string]$Password = '',
    [switch]$WithWebPanel
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')
$PayloadRoot = Split-Path $PSScriptRoot -Parent

Write-Host ''
Write-Host '==== 一键部署：Sunshine → 虚拟屏 → 分辨率卡片 ====' -ForegroundColor Cyan
Write-Host "设备      $(Get-DeviceId)"
Write-Host ''
Assert-Admin -Hint '请双击包内的「一键部署.cmd」，由它提权运行。'

# Web UI 凭据：直接回车 = 用户名 admin、密码随机 16 位
if (-not $Username) {
    $inputUser = Read-Host 'Sunshine 用户名（回车用 admin）'
    if ([string]::IsNullOrWhiteSpace($inputUser)) { $Username = 'admin' } else { $Username = $inputUser.Trim() }
}
if (-not $Password) {
    $inputPass = Read-Host 'Sunshine 密码（回车随机生成 16 位）'
    if (-not [string]::IsNullOrWhiteSpace($inputPass)) { $Password = $inputPass }
}
Write-Host "凭据      $Username / $(if ($Password) { $Password } else { '随机生成' })"
Write-Host ''

$steps = [ordered]@{ install = $null; vdd = $null; cards = $null }

function Invoke-Step {
    param([string]$Label, [string]$Script, [string[]]$ScriptArgs = @())
    Write-Host ''
    Write-Host "---- $Label ----" -ForegroundColor Cyan
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot $Script)) + $ScriptArgs
    # 子脚本输出直接送控制台，不能进管道；否则会被当成函数返回值，
    # 让调用方拿到字符串数组而不是退出码。
    & powershell @argList 2>&1 | Out-Host
    $rc = $LASTEXITCODE
    if ($null -eq $rc) { $rc = 0 }
    Write-Host "---- $Label 退出码 $rc ----" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })
    return [int]$rc
}

# 按需免登录面板：脚本装到 ProgramData，不建桌面快捷方式。
# 只是个本地转发器，不注册服务、不写防火墙、不开机自启。
function Install-WebPanel {
    $panelRoot = 'C:\ProgramData\sunshine-lan-streaming\panel'
    $panelScripts = Join-Path $panelRoot 'scripts'
    New-Item -ItemType Directory -Path $panelScripts -Force | Out-Null
    foreach ($f in @('打开Sunshine面板.cmd', '停止Sunshine面板.cmd')) {
        $src = Join-Path $PayloadRoot $f
        if (-not (Test-Path -LiteralPath $src)) { throw "部署包缺少 $f" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $panelRoot $f) -Force
    }
    foreach ($f in @('Open-WebUI.ps1', 'Panel.ps1', '_Baseline.ps1')) {
        $src = Join-Path $PSScriptRoot $f
        if (-not (Test-Path -LiteralPath $src)) { throw "部署包缺少 scripts\$f" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $panelScripts $f) -Force
    }
    return $panelRoot
}

$installArgs = @('-Username', $Username)
if ($Password) { $installArgs += @('-Password', $Password) }
$steps.install = Invoke-Step '1/3 安装宿主' 'Install.ps1' $installArgs
# ViGEmBus 属可选项：宿主有失败项但服务/配置已就绪时，仍继续虚拟屏与卡片
$hostReady = (Get-Service -Name $script:SunshineService -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Get-SunshineConfPath))
if ($steps.install -eq 0 -or $hostReady) {
    if ($steps.install -ne 0) {
        Write-Host ''
        Write-Host '宿主存在失败项，但服务与配置已就绪，继续虚拟屏与卡片步骤。' -ForegroundColor Yellow
    }
    $steps.vdd = Invoke-Step '2/3 启用虚拟屏' 'Install-Vdd.ps1'
    $steps.cards = Invoke-Step '3/3 分辨率卡片' 'Install-Cards.ps1'
} else {
    Write-Host ''
    Write-Host '宿主安装未通过且服务不可用，跳过虚拟屏与卡片步骤。' -ForegroundColor Red
    $steps.vdd = -1
    $steps.cards = -1
}

# 合并结果：保留 Install.ps1 写的字段，追加一键步骤状态与失败项
$stateDir = Get-DeviceStateRoot
$resultFile = Join-Path $stateDir 'install-result.json'
$data = $null
if (Test-Path -LiteralPath $resultFile) {
    try { $data = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
if (-not $data) {
    $data = [pscustomobject]@{
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        device_id = Get-DeviceId
        host      = $env:COMPUTERNAME
        failures  = @()
        warnings  = @()
    }
}
$obj = [ordered]@{}
foreach ($p in $data.PSObject.Properties.Name) { $obj[$p] = $data.$p }
$obj['one_click'] = $true
$obj['steps'] = [ordered]@{ install = $steps.install; vdd = $steps.vdd; cards = $steps.cards }

$panelPath = $null
$panelError = $null
if ($WithWebPanel) {
    if ($hostReady) {
        try { $panelPath = Install-WebPanel } catch { $panelError = $_.Exception.Message }
    } else {
        $panelError = '宿主未就绪'
    }
    $obj['web_panel'] = [bool]$panelPath
}

$failures = @($obj['failures'] | Where-Object { $_ })
if ($steps.install -ne 0) {
    $failures += '虚拟屏与分辨率卡片已跳过（宿主安装未通过）'
} else {
    if ($steps.vdd -ne 0) { $failures += "虚拟屏步骤未通过（退出码 $($steps.vdd)）" }
    if ($steps.cards -ne 0) { $failures += "分辨率卡片步骤未通过（退出码 $($steps.cards)）" }
}
if ($panelError) { $failures += "免登录面板未安装：$panelError" }
$obj['failures'] = @($failures | Select-Object -Unique)
[System.IO.File]::WriteAllText($resultFile, ($obj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

$rc = 0
if ($steps.install -ne 0 -or $steps.vdd -ne 0 -or $steps.cards -ne 0 -or $panelError) { $rc = 1 }
Write-Host ''
Write-Host "==== 一键部署完成：install=$($steps.install)  vdd=$($steps.vdd)  cards=$($steps.cards) ====" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })
if ($panelPath) {
    Write-Host "免登录面板  已安装到 $panelPath" -ForegroundColor Green
    Write-Host '             在图形控制台点「启动免登录面板」打开，空闲 10 分钟自动退出。'
}

$resultArgs = @('-ExitCode', $rc)
if ($env:SUNSHINE_GUI -eq '1') { $resultArgs += '-PrintOnly' }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Show-Result.ps1') @resultArgs
# Show-Result 保存 TXT 返回 0，直接关闭返回 3；部署是否成功只看步骤结果，
# 弹窗关闭方式不影响入口的退出码，避免成功后被误判为“未完成”。
if ($rc -ne 0) { exit 1 }
exit 0
