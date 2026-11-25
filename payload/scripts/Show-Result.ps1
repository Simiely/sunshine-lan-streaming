#Requires -Version 5.1
<#
.SYNOPSIS
    安装结束后弹出结果窗口：成功显示 Web UI 地址与账号密码，失败列出失败项。
.DESCRIPTION
    读取 Install.ps1 写到设备状态目录的 install-result.json；同一份文本也会
    打印到控制台，窗口关闭后日志窗口仍有相同信息。
    窗口为深色主题，可把结果保存为 TXT；保存成功后返回 0，入口 cmd 据此
    连同控制台窗口一起退出。
.PARAMETER ExitCode
    Install.ps1 的退出码。非 0 时按失败展示。
.PARAMETER PrintOnly
    只在控制台输出文本，不弹窗（用于验证文案与取值）。
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File Show-Result.ps1 -ExitCode 0
#>
[CmdletBinding()]
param(
    [int]$ExitCode = 0,
    [switch]$PrintOnly
)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '_Baseline.ps1')

$deviceDir = Get-DeviceStateRoot
$resultFile = Join-Path $deviceDir 'install-result.json'
$data = $null
if (Test-Path -LiteralPath $resultFile) {
    try { $data = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}
$props = @()
if ($data) { $props = @($data.PSObject.Properties.Name) }

$failures = @()
if ($props -contains 'failures') { $failures = @($data.failures | Where-Object { $_ }) }
$warnings = @()
if ($props -contains 'warnings') { $warnings = @($data.warnings | Where-Object { $_ }) }
$user = if ($props -contains 'username' -and $data.username) { [string]$data.username } else { 'admin' }
$pass = if ($props -contains 'password' -and $data.password) { [string]$data.password } else { '见 credentials.txt' }
$ok = ($ExitCode -eq 0) -and ($failures.Count -eq 0)

if ($ok) {
    $urls = @()
    foreach ($k in @('web_ui_lan', 'web_ui_local')) {
        if ($props -contains $k) {
            $u = [string]$data.$k
            if ($u) { $urls += $u }
        }
    }
    if ($urls.Count -eq 0) { $urls = @('https://localhost:47990') }
    $ver  = if ($props -contains 'version') { [string]$data.version } else { '未知' }
    $svc  = if ($props -contains 'service_status') { [string]$data.service_status } else { '未知' }
    $ports = @()
    if ($props -contains 'listen_ports') { $ports = @($data.listen_ports) }
    $vigem = '已跳过'
    if ($props -contains 'vigem_service' -and $data.vigem_service) {
        $vigem = if ($data.vigem_installed_now) { "本次已安装（$($data.vigem_service)）" } else { [string]$data.vigem_service }
    }

    $lines = @(
        'Sunshine 部署完成',
        '',
        '浏览器打开 Web UI（自签证书提示“不安全”属正常）：'
    )
    foreach ($u in $urls) { $lines += "  $u" }
    $lines += @(
        '',
        "账号：$user",
        "密码：$pass",
        '',
        "设备：$($env:COMPUTERNAME)（$(if ($props -contains 'device_id') { $data.device_id } else { 'unknown' })）",
        "版本：$ver",
        "服务：$svc    端口：$(if ($ports) { $ports -join ', ' } else { '未知' })",
        "虚拟手柄：$vigem",
        '',
        '手机端下一步：',
        '  1. Moonlight 添加主机，输入上面的地址',
        '  2. 打开主机 Web UI 的 PIN 页面，输入 Moonlight 显示的配对码',
        '',
        '可选步骤（按需双击）：',
        '  安装虚拟屏.cmd       连上时切换到虚拟屏，断开自动回滚',
        '  安装分辨率卡片.cmd   Moonlight 里按卡片记住分辨率',
        '',
        '配置文件：C:\Program Files\Sunshine\config\sunshine.conf'
    )
    if ($warnings.Count -gt 0) {
        $lines += ''
        $lines += "警告 $($warnings.Count) 条："
        foreach ($w in @($warnings | Select-Object -First 8)) { $lines += "  - $w" }
    }
    $title = 'Sunshine 部署成功'
} else {
    $lines = @(
        'Sunshine 部署未完成',
        '',
        "退出码：$ExitCode"
    )
    if ($failures.Count -gt 0) {
        $lines += ''
        $lines += '失败项：'
        foreach ($f in @($failures | Select-Object -First 12)) { $lines += "  - $f" }
        if ($failures.Count -gt 12) { $lines += "  … 另有 $($failures.Count - 12) 项，见控制台输出" }
    } else {
        $lines += ''
        $lines += '未生成结果文件，脚本可能在预检阶段中止。'
    }
    if ($warnings.Count -gt 0) {
        $lines += ''
        $lines += '警告：'
        foreach ($w in @($warnings | Select-Object -First 6)) { $lines += "  - $w" }
    }
    $lines += @(
        '',
        '日志：C:\Program Files\Sunshine\config\sunshine.log',
        $(if ($data) { "结果：$resultFile" } else { '结果：未生成' }),
        '',
        $(if ($props -contains 'password' -and $data.password) { "若 Sunshine 已启动，Web UI 凭据为 $user / $($data.password)" } else { '凭据已写入设备状态目录的 credentials.txt' })
    )
    $title = 'Sunshine 部署失败'
}

$text = $lines -join "`r`n"
if ($PrintOnly) {
    Write-Output $text
    exit 0
}

Add-Type -AssemblyName System.Drawing
$darkBg     = [System.Drawing.Color]::FromArgb(30, 30, 30)
$darkPanel  = [System.Drawing.Color]::FromArgb(37, 37, 38)
$darkText   = [System.Drawing.Color]::FromArgb(230, 230, 230)
$darkBorder = [System.Drawing.Color]::FromArgb(70, 70, 70)
$darkButton = [System.Drawing.Color]::FromArgb(60, 60, 60)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class SunDarkUi
{
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    static extern int SetWindowTheme(IntPtr hWnd, string subApp, string subId);

    // 未公开接口：让本进程（含系统文件对话框）使用深色模式，值 2 = ForceDark
    [DllImport("uxtheme.dll", EntryPoint = "#135", SetLastError = true)]
    static extern int SetPreferredAppMode(int appMode);

    public static void EnableDarkApp()
    {
        try { SetPreferredAppMode(2); } catch { }
    }

    public static void TitleBar(IntPtr hwnd)
    {
        int v = 1;
        try
        {
            if (DwmSetWindowAttribute(hwnd, 20, ref v, 4) != 0)
            {
                DwmSetWindowAttribute(hwnd, 19, ref v, 4);
            }
        }
        catch { }
    }

    public static void DarkScroll(IntPtr hwnd)
    {
        try { SetWindowTheme(hwnd, "DarkMode_Explorer", null); } catch { }
    }
}
'@
[SunDarkUi]::EnableDarkApp()

$script:SavedOk = $false
$form = New-Object System.Windows.Forms.Form
$form.Text = $title
$form.BackColor = $darkBg
$form.ForeColor = $darkText
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(680, 520)
$form.MinimizeBox = $false
$form.MaximizeBox = $false
$form.TopMost = $true

$box = New-Object System.Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.WordWrap = $true
$box.Dock = 'Fill'
$box.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$box.BackColor = $darkPanel
$box.ForeColor = $darkText
$box.BorderStyle = 'None'
$box.Text = $text

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = 'Fill'
$panel.Padding = New-Object System.Windows.Forms.Padding(12)
$panel.BackColor = $darkBg
$panel.Controls.Add($box)

$bar = New-Object System.Windows.Forms.FlowLayoutPanel
$bar.Dock = 'Fill'
$bar.FlowDirection = 'RightToLeft'
$bar.Padding = New-Object System.Windows.Forms.Padding(8)
$bar.BackColor = $darkBg

$close = New-Object System.Windows.Forms.Button
$close.Text = '关闭'
$close.Size = New-Object System.Drawing.Size(100, 32)
$close.DialogResult = [System.Windows.Forms.DialogResult]::OK

$save = New-Object System.Windows.Forms.Button
$save.Text = '保存为 TXT…'
$save.Size = New-Object System.Drawing.Size(140, 32)
$save.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = '保存部署结果'
    $dlg.Filter = '文本文件 (*.txt)|*.txt|所有文件 (*.*)|*.*'
    $dlg.DefaultExt = 'txt'
    $dlg.AutoUpgradeEnabled = $true
    $dlg.FileName = "Sunshine部署结果-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            [System.IO.File]::WriteAllText($dlg.FileName, $text, (New-Object System.Text.UTF8Encoding($true)))
            # 保存成功：关闭结果窗口，入口脚本收到 0 后连同控制台一起退出
            $script:SavedOk = $true
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($form, "保存失败：$($_.Exception.Message)", '保存失败', 'OK', 'Error') | Out-Null
        }
    }
})

foreach ($btn in @($close, $save)) {
    $btn.FlatStyle = 'Flat'
    $btn.UseVisualStyleBackColor = $false
    $btn.BackColor = $darkButton
    $btn.ForeColor = $darkText
    $btn.FlatAppearance.BorderColor = $darkBorder
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(75, 75, 75)
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(95, 95, 95)
}

$bar.Controls.Add($close)
$bar.Controls.Add($save)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 1
$layout.RowCount = 2
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56))) | Out-Null
$layout.Controls.Add($panel, 0, 0)
$layout.Controls.Add($bar, 0, 1)
$form.Controls.Add($layout)

$form.AcceptButton = $close
$form.CancelButton = $close
$form.Add_Shown({
    [SunDarkUi]::TitleBar($form.Handle)
    [SunDarkUi]::DarkScroll($box.Handle)
})
$form.ShowDialog() | Out-Null
if ($script:SavedOk) { exit 0 }
exit 3
