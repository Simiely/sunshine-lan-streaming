#Requires -Version 5.1
<#
.SYNOPSIS
    打开/停止按需的 Sunshine 免登录面板。
.DESCRIPTION
    打开时如果代理没在运行，就在后台启动 Open-WebUI.ps1（隐藏窗口），
    等端口就绪后用默认浏览器打开 http://127.0.0.1:<port>/。
    代理空闲会自动退出；也可以运行本脚本 -Action stop 立即停止。
.PARAMETER Action
    open（默认）或 stop。
.PARAMETER NoOpen
    只启动代理，不打开浏览器（测试用）。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Panel.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Panel.ps1 -Action stop
#>
[CmdletBinding()]
param(
    [ValidateSet('open', 'stop')]
    [string]$Action = 'open',
    [switch]$NoOpen
)
$ErrorActionPreference = 'Stop'

$panelDir = Join-Path $env:LOCALAPPDATA 'SunshinePanel'
$pidFile  = Join-Path $panelDir 'webpanel.pid'
$portFile = Join-Path $panelDir 'webpanel.port'
$logFile  = Join-Path $panelDir 'webpanel.log'

function Get-PanelPid {
    if (-not (Test-Path -LiteralPath $pidFile)) { return 0 }
    $v = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue), [ref]$v)
    if ($v -gt 0 -and (Get-Process -Id $v -ErrorAction SilentlyContinue)) { return $v }
    return 0
}
function Get-PanelPort {
    if (-not (Test-Path -LiteralPath $portFile)) { return 0 }
    $v = 0
    [void][int]::TryParse((Get-Content -LiteralPath $portFile -Raw -ErrorAction SilentlyContinue), [ref]$v)
    return $v
}
function Test-LocalPort {
    param([int]$P)
    if ($P -le 0) { return $false }
    try {
        $c = New-Object Net.Sockets.TcpClient
        $c.Connect('127.0.0.1', $P)
        $c.Close()
        return $true
    } catch { return $false }
}

if ($Action -eq 'stop') {
    $old = Get-PanelPid
    if ($old -gt 0) {
        Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
        Write-Host "已停止面板代理（PID $old）"
    } else {
        Write-Host '面板代理没有在运行'
    }
    Remove-Item -LiteralPath $pidFile, $portFile -Force -ErrorAction SilentlyContinue
    exit 0
}

$port = Get-PanelPort
if ((Get-PanelPid) -eq 0 -or -not (Test-LocalPort -P $port)) {
    Remove-Item -LiteralPath $pidFile, $portFile -Force -ErrorAction SilentlyContinue
    $server = Join-Path $PSScriptRoot 'Open-WebUI.ps1'
    if (-not (Test-Path -LiteralPath $server)) {
        Write-Host "找不到 $server"
        exit 2
    }
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$server`"") `
        -WindowStyle Hidden | Out-Null

    $port = 0
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        $p = Get-PanelPort
        if ((Get-PanelPid) -ne 0 -and (Test-LocalPort -P $p)) { $port = $p; break }
        if ((Get-PanelPid) -eq 0 -and $i -ge 6 -and -not (Test-Path -LiteralPath $pidFile)) { break }
    }
}

if ($port -le 0) {
    Write-Host '面板代理启动失败。'
    if (Test-Path -LiteralPath $logFile) {
        Get-Content -LiteralPath $logFile -Tail 12 | ForEach-Object { "  $_" }
    }
    exit 1
}

$url = "http://127.0.0.1:$port/"
Write-Host "面板已就绪：$url"
if (-not $NoOpen) { Start-Process $url | Out-Null }
exit 0
