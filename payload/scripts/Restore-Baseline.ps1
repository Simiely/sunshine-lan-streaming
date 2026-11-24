#Requires -Version 5.1
<#
.SYNOPSIS
    把基线配置键合并写回 sunshine.conf，并按需重启 Sunshine 服务。

.DESCRIPTION
    M2 产物。解决的坑：Sunshine 的 POST /api/config 是整体替换，不是增量合并。
    任何一次只提交部分键的写入，都会把未提交的键清空。本机已因此丢失
    origin_web_ui_allowed / upnp / dd_configuration_option 两次。

    所以本脚本不调用 API，而是直接对 sunshine.conf 做「合并写回」：
    先读出全部现有键，再覆盖式设置基线键，其余键（locale、output_name 等）原样保留。
    可反复执行，不会丢失已有配置。

    基线键及其理由：
      origin_web_ui_allowed = lan        Web UI 只对局域网开放，默认值 wan 过宽
      upnp                  = disabled   禁止向路由器 UPnP 打洞，默认值 enabled 会主动开端口
      dd_configuration_option = disabled 关闭 Sunshine 的自动显示切换，串流绝不改显示设置

.PARAMETER NoRestart
    只写配置并校验文件内容，不重启服务。用于预置配置、等下次重启生效。

.PARAMETER ConfPath
    配置文件路径，默认 %ProgramFiles%\Sunshine\config\sunshine.conf。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Restore-Baseline.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Restore-Baseline.ps1 -NoRestart
#>
[CmdletBinding()]
param(
    [switch]$NoRestart,
    [string]$ConfPath = (Join-Path $env:ProgramFiles 'Sunshine\config\sunshine.conf')
)

$ErrorActionPreference = 'Stop'

$ServiceName   = 'SunshineService'
$RequiredPorts = @(47984, 47989, 47990)
$Baseline      = [ordered]@{
    'origin_web_ui_allowed'   = 'lan'
    'upnp'                    = 'disabled'
    'dd_configuration_option' = 'disabled'
}

$ExitCode = 0

function Write-Step { param([string]$Text) Write-Host $Text }

function Read-ConfMap {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    return $map
}

function Write-ConfMap {
    param([string]$Path, $Map)
    $lines = @()
    foreach ($k in @($Map.Keys)) { $lines += "$k = $($Map[$k])" }
    if (-not $lines) { return }
    # 无 BOM：Sunshine 解析 conf 时会把 BOM 并进第一个键名，导致该键失效
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), $utf8)
}

function Get-ListeningPorts {
    param([int[]]$Ports)
    $hit = @()
    foreach ($p in $Ports) {
        if (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) { $hit += $p }
    }
    return $hit
}

# ---------- 0 环境 ----------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Step '==== 恢复基线配置 ===='
Write-Step "配置文件  $ConfPath"
Write-Step "管理员    $IsAdmin"
Write-Step ''

if (-not (Test-Path -LiteralPath $ConfPath)) {
    Write-Step 'FAIL 找不到 sunshine.conf，请先运行 Install.ps1'
    exit 1
}

# sunshine.conf 在 Program Files 下，写它和重启服务都需要管理员。
# 非管理员时提前退出，不留半截状态。
if (-not $IsAdmin) {
    Write-Step 'FAIL 需要管理员权限：Program Files 下的配置不可写，服务也无法重启。'
    Write-Step '     请双击 payload\恢复基线.cmd，它会在 UAC 提示里请求提权后重新运行本脚本。'
    exit 3
}

# ---------- 1 备份 ----------
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$ConfPath.bak-$stamp"
Copy-Item -LiteralPath $ConfPath -Destination $backup -Force
Write-Step "备份      $backup"

# ---------- 2 读现状 ----------
$before = Read-ConfMap -Path $ConfPath
$beforeKeys = @($before.Keys)
Write-Step "现有键    $($beforeKeys.Count) 个：$($beforeKeys -join ', ')"

$drift = @()
foreach ($k in $Baseline.Keys) {
    $want = $Baseline[$k]
    if (-not $before.Contains($k)) {
        $drift += "$k 缺失"
    } elseif ($before[$k] -ne $want) {
        $drift += "$k = $($before[$k])（应为 $want）"
    }
}
if ($drift.Count -eq 0) {
    Write-Step '偏离项    无，三个键都已是目标值'
} else {
    Write-Step "偏离项    $($drift.Count) 项：$($drift -join '；')"
}
Write-Step ''

# ---------- 3 合并写回 ----------
# 只覆盖基线键，其余键原样保留 —— 这是与 POST /api/config 的关键差别
$after = [ordered]@{}
foreach ($k in $beforeKeys) { $after[$k] = $before[$k] }
foreach ($k in $Baseline.Keys) { $after[$k] = $Baseline[$k] }

if (-not $after.Contains('output_name')) {
    Write-Step 'WARN 配置里没有 output_name。多显示器下这是黑屏的常见原因，建议在 Web UI 指定捕获屏。'
}

# 服务运行中先停，避免它退出时用内存里的旧配置覆盖文件
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running' -and -not $NoRestart) {
    Write-Step '停止服务  进行中…'
    try {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        (Get-Service -Name $ServiceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
        Write-Step '停止服务  OK'
    } catch {
        Write-Step "停止服务  FAIL $($_.Exception.Message)"
        $ExitCode = 1
    }
}

Write-ConfMap -Path $ConfPath -Map $after
Write-Step "写入配置  OK（$($after.Keys.Count) 个键）"

# ---------- 4 回读校验 ----------
$verify = Read-ConfMap -Path $ConfPath
$bad = @()
foreach ($k in $Baseline.Keys) {
    if (-not $verify.Contains($k) -or $verify[$k] -ne $Baseline[$k]) { $bad += $k }
}
if ($bad.Count -eq 0) {
    Write-Step '回读校验  OK，三个基线键落盘正确'
} else {
    Write-Step "回读校验  FAIL，未落盘：$($bad -join ', ')"
    $ExitCode = 1
}
Write-Step ''

# ---------- 5 重启与端口 ----------
if ($NoRestart) {
    Write-Step '按 -NoRestart 跳过重启。配置已预置，下次服务启动时生效。'
    exit $ExitCode
}

Write-Step '启动服务  进行中…'
try {
    Start-Service -Name $ServiceName -ErrorAction Stop
    (Get-Service -Name $ServiceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    Write-Step '启动服务  OK'
} catch {
    Write-Step "启动服务  FAIL $($_.Exception.Message)"
    exit 1
}

# 端口要 3-5 秒才起监听，轮询而不是死等
$deadline = (Get-Date).AddSeconds(30)
$live = @()
while ((Get-Date) -lt $deadline) {
    $live = Get-ListeningPorts -Ports $RequiredPorts
    if ($live.Count -eq $RequiredPorts.Count) { break }
    Start-Sleep -Milliseconds 500
}

Write-Step "常驻端口  $($live -join ', ')$(if ($live.Count -ne $RequiredPorts.Count) { "（缺 $(($RequiredPorts | Where-Object { $_ -notin $live }) -join ', ')）" })"
if ($live.Count -ne $RequiredPorts.Count) { $ExitCode = 1 }

Write-Step ''
if ($ExitCode -eq 0) {
    Write-Step '结果      基线已恢复并生效'
} else {
    Write-Step '结果      配置已写入，但服务或端口未完全就绪，请查看 sunshine.log'
}
exit $ExitCode
