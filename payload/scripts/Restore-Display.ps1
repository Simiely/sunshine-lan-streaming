#Requires -Version 5.1
<#
.SYNOPSIS
    救援脚本：把被禁用的显示输出重新打开，并恢复成「扩展」布局。

.DESCRIPTION
    vdd 基线用了 dd_configuration_option = ensure_only_display，连上时 Sunshine 会
    禁用其余所有显示屏。正常断流会回滚，但如果回滚失败（设备已不在拓扑里，
    见 docs/显示拓扑卡死.md），物理屏可能一直黑着。

    本脚本只做加法：重新启用显示设备 + 把布局设为扩展。它不改 sunshine.conf，
    不重启服务，因此不会覆盖任何配置，可以放心反复运行。

    典型触发时机：断开串流后两块物理屏不亮，或桌面只剩一块虚拟屏。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Restore-Display.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

Write-Host '==== 恢复显示输出 ===='
Write-Host "管理员    $(Test-Admin)"
Write-Host ''

if (-not (Test-Admin)) {
    Write-Host 'WARN 非管理员，设备启用会失败；仅能尝试切换布局。'
}

Write-Host '改前输出  '
$before = @(Get-DxgiOutputs)
if ($before.Count) { foreach ($o in $before) { Write-Host "          $($o.Output)  [attached=$($o.Attached)]  ←  $($o.Adapter)" } }
else { Write-Host '          （未取到）' }
Write-Host ''

# ---------- 1 重新启用被停用的显示设备 ----------
# ensure_only_display 走的是 Windows CCD 接口，通常不落成 PnP 禁用；
# 但回滚失败时可能留下 Error 状态的设备，这里一并处理。
$candidates = @(Get-PnpDevice -Class Display, Monitor -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -ne 'OK' })
if ($candidates.Count -gt 0) {
    Write-Host "启用设备  $($candidates.Count) 个状态异常的设备"
    foreach ($d in $candidates) {
        Write-Host "          $($d.FriendlyName) [$($d.Status)]"
        if (Test-Admin) {
            try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop }
            catch { Write-Host "          启用失败：$($_.Exception.Message)" }
        }
    }
} else {
    Write-Host '启用设备  无需处理，所有显示设备状态正常'
}
Write-Host ''

# ---------- 2 恢复扩展布局 ----------
# DisplaySwitch 是系统自带组件，不依赖 P/Invoke，最稳的一招。
Write-Host '切换布局  设为「扩展」…'
try {
    Start-Process -FilePath 'DisplaySwitch.exe' -ArgumentList '/extend' -Wait -ErrorAction Stop
    Write-Host '切换布局  OK'
} catch {
    Write-Host "切换布局  FAIL $($_.Exception.Message)"
}
Start-Sleep -Seconds 2

# ---------- 3 结果 ----------
Write-Host ''
Write-Host '改后输出  '
$after = @(Get-DxgiOutputs)
if ($after.Count) { foreach ($o in $after) { Write-Host "          $($o.Output)  [attached=$($o.Attached)]  ←  $($o.Adapter)" } }
else { Write-Host '          （未取到）' }

Write-Host ''
if ($after.Count -gt $before.Count) {
    Write-Host "结果      输出数 $($before.Count) → $($after.Count)，已恢复"
} elseif ($after.Count -eq 0) {
    Write-Host '结果      仍取不到输出。若物理屏确实不亮，直接在显示器上按 Win+P 选「扩展」，'
    Write-Host '          或重启一次主机——显示拓扑在登录时会重建。'
} else {
    Write-Host "结果      输出数仍为 $($after.Count)。若物理屏不亮，按 Win+P 手动选「扩展」。"
}
Write-Host ''
Write-Host '注意      本脚本不改 sunshine.conf。要退回物理屏方案，运行 手动工具\安装虚拟屏.cmd -Uninstall。'
