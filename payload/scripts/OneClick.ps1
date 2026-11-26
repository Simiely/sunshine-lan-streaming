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
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File OneClick.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

Write-Host ''
Write-Host '==== 一键部署：Sunshine → 虚拟屏 → 分辨率卡片 ====' -ForegroundColor Cyan
Write-Host "设备      $(Get-DeviceId)"
Write-Host ''
Assert-Admin -Hint '请双击包内的「一键部署.cmd」，由它提权运行。'

$steps = [ordered]@{ install = $null; vdd = $null; cards = $null }

function Invoke-Step {
    param([string]$Label, [string]$Script)
    Write-Host ''
    Write-Host "---- $Label ----" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script)
    $rc = $LASTEXITCODE
    if ($null -eq $rc) { $rc = 0 }
    Write-Host "---- $Label 退出码 $rc ----" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })
    return [int]$rc
}

$steps.install = Invoke-Step '1/3 安装宿主' 'Install.ps1'
if ($steps.install -eq 0) {
    $steps.vdd = Invoke-Step '2/3 启用虚拟屏' 'Install-Vdd.ps1'
    $steps.cards = Invoke-Step '3/3 分辨率卡片' 'Install-Cards.ps1'
} else {
    Write-Host ''
    Write-Host '宿主安装未通过，跳过虚拟屏与卡片步骤。' -ForegroundColor Red
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

$failures = @($obj['failures'] | Where-Object { $_ })
if ($steps.install -ne 0) {
    $failures += '虚拟屏与分辨率卡片已跳过（宿主安装未通过）'
} else {
    if ($steps.vdd -ne 0) { $failures += "虚拟屏步骤未通过（退出码 $($steps.vdd)）" }
    if ($steps.cards -ne 0) { $failures += "分辨率卡片步骤未通过（退出码 $($steps.cards)）" }
}
$obj['failures'] = @($failures | Select-Object -Unique)
[System.IO.File]::WriteAllText($resultFile, ($obj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

$rc = 0
if ($steps.install -ne 0 -or $steps.vdd -ne 0 -or $steps.cards -ne 0) { $rc = 1 }
Write-Host ''
Write-Host "==== 一键部署完成：install=$($steps.install)  vdd=$($steps.vdd)  cards=$($steps.cards) ====" -ForegroundColor $(if ($rc -eq 0) { 'Green' } else { 'Red' })

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Show-Result.ps1') -ExitCode $rc
# Show-Result 保存 TXT 返回 0，直接关闭返回 3；部署是否成功只看步骤结果，
# 弹窗关闭方式不影响入口的退出码，避免成功后被误判为“未完成”。
if ($rc -ne 0) { exit 1 }
exit 0
