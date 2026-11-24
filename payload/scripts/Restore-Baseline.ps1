#Requires -Version 5.1
<#
.SYNOPSIS
    按指定 profile 把基线配置合并写回 sunshine.conf，并重启服务。

.DESCRIPTION
    解决的坑：Sunshine 的 POST /api/config 是整体替换而非增量合并，任何一次
    只提交部分键的写入都会把其余键清空。本机已因此丢过两次基线配置，
    见 docs/配置写入覆盖.md。

    所以这里不调用 API，而是直接对 sunshine.conf 做「合并写回」：读出全部现有键，
    覆盖式设置目标键，其余键（locale 等）原样保留。可反复执行。

    两套 profile 见 _Baseline.ps1 的注释：physical 不接管显示，vdd 捕获虚拟屏。

.PARAMETER Profile
    physical（默认）—— 固定捕获物理屏，dd_* 全部 disabled，不动显示拓扑。
    vdd         —— 捕获虚拟屏，连上时禁用其余所有屏，断流立即回滚。

.PARAMETER OutputName
    显式指定 output_name（如 \\.\DISPLAY3）。省略时保持文件里已有的值。

.PARAMETER NoRestart
    只写配置并校验文件，不重启服务。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Restore-Baseline.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Restore-Baseline.ps1 -Profile vdd -OutputName '\\.\DISPLAY3'
#>
[CmdletBinding()]
param(
    [ValidateSet('physical', 'vdd')]
    [string]$Profile = 'physical',
    [string]$OutputName,
    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

$Conf     = Get-SunshineConfPath
$ExitCode = 0

Write-Host '==== 应用基线配置 ===='
Write-Host "配置文件  $Conf"
Write-Host "profile   $Profile"
Write-Host "管理员    $(Test-Admin)"
Write-Host ''

if (-not (Test-Path -LiteralPath $Conf)) {
    Write-Host 'FAIL 找不到 sunshine.conf，请先运行 Install.ps1'
    exit 1
}

Assert-Admin -Hint '请双击 payload\恢复基线.cmd；切换虚拟屏方案请用 payload\安装虚拟屏.cmd。'

# ---------- 1 目标键 ----------
# 回退到 physical 时必须纠正 output_name。
# 从 vdd 方案退回来时，conf 里的 output_name 是虚拟屏；若原样保留，
# 服务重启后仍然去捕获那块屏，"恢复基线"就没起到恢复作用。
# 只有在调用方没有显式指定 -OutputName 时才做这个自动纠正，并明确打印出来。
$effOutputName = $OutputName
if (-not $effOutputName -and $Profile -eq 'physical') {
    $cur = Read-ConfMap -Path $Conf
    $curName = if ($cur.Contains('output_name')) { $cur['output_name'] } else { $null }
    $st = Get-DisplayState -Path (Join-Path 'C:\ProgramData\sunshine-lan-streaming' 'display-state.json')

    if ($curName -and $st) {
        $vddName = if ($st.PSObject.Properties.Name -contains 'vdd_output') { $st.vdd_output } else { $null }
        $phyName = if ($st.PSObject.Properties.Name -contains 'physical_output') { $st.physical_output } else { $null }

        if ($vddName -and $curName -eq $vddName) {
            if ($phyName) {
                $now = @(Get-DxgiOutputs)
                $ok  = @($now | Where-Object { $_.Output -eq $phyName })
                if ($ok.Count -gt 0) {
                    $effOutputName = $phyName
                    Write-Host "纠正输出  当前指向虚拟屏 $curName，自动改回物理屏 $phyName"
                } else {
                    Write-Host "WARN 当前指向虚拟屏 $curName，但记录的物理屏 $phyName 已不存在。"
                    Write-Host "     请手动指定：-OutputName '\\.\DISPLAY1'（先看下面的可用输出）"
                    $now | ForEach-Object { Write-Host "       $($_.Output)  [attached=$($_.Attached)]  ←  $($_.Adapter)" }
                }
            } else {
                Write-Host "WARN 当前指向虚拟屏 $curName，但快照里没有物理屏记录，无权擅自更改。"
            }
            Write-Host ''
        }
    }
}

$keys = Get-BaselineProfile -Name $Profile -OutputName $effOutputName

# ---------- 2 现状与偏离 ----------
$before = Read-ConfMap -Path $Conf
$beforeKeys = @($before.Keys)
Write-Host "现有键    $($beforeKeys.Count) 个：$($beforeKeys -join ', ')"

$drift = @()
foreach ($k in @($keys.Keys)) {
    $want = $keys[$k]
    if (-not $before.Contains($k)) {
        $drift += "$k 缺失"
    } elseif ($before[$k] -ne $want) {
        $drift += "$k = $($before[$k])（应为 $want）"
    }
}
if ($drift.Count -eq 0) {
    Write-Host '偏离项    无，目标键都已是目标值'
} else {
    Write-Host "偏离项    $($drift.Count) 项：$($drift -join '；')"
}
Write-Host ''

if (-not $before.Contains('output_name') -and -not $keys.Contains('output_name')) {
    Write-Host 'WARN 配置里没有 output_name。多显示器下这是黑屏的常见原因，必须显式指定捕获屏。'
}

# ---------- 3 停服务（避免它退出时用内存旧配置覆盖文件） ----------
if (-not $NoRestart) {
    $svc = Get-Service -Name $SunshineService -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host '停止服务  进行中…'
        try {
            Stop-Service -Name $SunshineService -Force -ErrorAction Stop
            (Get-Service -Name $SunshineService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            Write-Host '停止服务  OK'
        } catch {
            Write-Host "停止服务  FAIL $($_.Exception.Message)"
            $ExitCode = 1
        }
    }
}

# ---------- 4 合并写回 + 回读 ----------
$bad = Set-ConfKeys -Path $Conf -Keys $keys
if ($bad.Count -eq 0) {
    Write-Host '回读校验  OK，目标键落盘正确'
} else {
    Write-Host "回读校验  FAIL，未落盘：$($bad -join ', ')"
    $ExitCode = 1
}
Write-Host ''

# ---------- 5 重启 ----------
if ($NoRestart) {
    Write-Host '按 -NoRestart 跳过重启。配置已预置，下次服务启动时生效。'
    exit $ExitCode
}

if (-not (Restart-SunshineService)) { $ExitCode = 1 }

Write-Host ''
if ($ExitCode -eq 0) {
    Write-Host "结果      基线已按 profile=$Profile 生效"
} else {
    Write-Host '结果      配置已写入，但服务或端口未完全就绪，请查看 sunshine.log'
}
exit $ExitCode
