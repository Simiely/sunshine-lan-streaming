#Requires -Version 5.1
<#
.SYNOPSIS
    安装 Sunshine 宿主，并写入局域网串流基线配置。

.DESCRIPTION
    M1 产物。按 manifest/components.json 校验安装包哈希，静默安装，设置 Web UI 凭据，
    写入三项基线配置（origin_web_ui_allowed / upnp / dd_configuration_option），启动服务并自检。

    幂等：同版本已安装时跳过安装，只做配置与自检。

.PARAMETER MsiPath
    安装包路径。默认按 manifest 版本号在 dist\cache 下查找。

.PARAMETER ManifestPath
    manifest/components.json 路径。默认依次尝试 ..\manifest 与 .\manifest。

.PARAMETER Username
    Web UI 用户名，默认 admin。

.PARAMETER Password
    Web UI 密码，默认随机生成 16 位。

.PARAMETER AllowConflict
    检测到向日葵 / RayLink / ToDesk 正在运行时仍然继续。默认不中止，只警告。

.PARAMETER DryRun
    只做检查与计划输出，不安装、不改配置、不启停服务。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File Install.ps1
#>
[CmdletBinding()]
param(
    [string]$MsiPath,
    [string]$ManifestPath,
    [string]$Username = 'admin',
    [string]$Password,
    [switch]$AllowConflict,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# 共享层：设备 ID 与按设备隔离的状态目录（见 docs/设备硬件标准.md）
. (Join-Path $PSScriptRoot '_Baseline.ps1')
$script:StepNo = 0
$script:Failures = @()
$script:Warnings = @()

# ---------- 输出 ----------
function Step($msg) {
    $script:StepNo++
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $script:StepNo, $msg) -ForegroundColor Cyan
}
function Ok($msg) { Write-Host "    OK   $msg" -ForegroundColor Green }
function Warn($msg) {
    Write-Host "    WARN $msg" -ForegroundColor Yellow
    $script:Warnings += $msg
}
function Fail($msg) {
    Write-Host "    FAIL $msg" -ForegroundColor Red
    $script:Failures += $msg
}
function Info($msg) { Write-Host "         $msg" -ForegroundColor Gray }

# ---------- 环境 ----------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

$Root = Split-Path $PSScriptRoot -Parent          # payload\（发行 zip 解压后即为包根）
$Repo = Split-Path $Root -Parent                   # 仓库根（本地开发时）

# 安装包查找顺序：显式 -MsiPath > 随包 vendor > dist\cache
# 发行 zip 解压后没有 dist 目录，所以 vendor 必须排在 dist\cache 前面，
# 否则用户解压后直接双击 安装.cmd 会报"找不到安装包"。
if (-not $MsiPath) {
    $candidates = @(
        (Join-Path $Root 'vendor\Sunshine-Windows-AMD64-installer.msi'),
        (Join-Path $Repo 'dist\cache\Sunshine-Windows-AMD64-installer.msi')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $MsiPath = $c; break } }
    if (-not $MsiPath) { $MsiPath = $candidates[-1] }
}
if (-not $ManifestPath) {
    foreach ($c in @(
        (Join-Path $Root 'manifest\components.json'),   # 发行 zip 内
        (Join-Path $Repo 'manifest\components.json')
    )) {
        if (Test-Path -LiteralPath $c) { $ManifestPath = $c; break }
    }
}

Write-Host ""
Write-Host "==== Sunshine 局域网串流 · 安装 ====" -ForegroundColor White
Info "管理员: $IsAdmin"
Info "计划模式: $([bool]$DryRun)"

# ---------- 1. 前置检查 ----------
Step "前置检查"

if (-not $IsAdmin -and -not $DryRun) {
    Fail "需要管理员权限（安装服务、写 Program Files）。请右键以管理员身份运行 安装.cmd。"
}

$os = Get-CimInstance Win32_OperatingSystem
Info "系统: $($os.Caption) $($os.Version)"
if ([version]$os.Version -lt [version]'10.0.19041') {
    Fail "Windows 版本过低，Sunshine 需要 10.0.19041 及以上。"
} else { Ok "系统版本满足要求" }

if (-not (Test-Path $MsiPath)) {
    Fail "找不到安装包: $MsiPath"
    Info "先在仓库根执行下载，或把 msi 放到 dist\cache\。"
} else {
    Ok "安装包存在: $(Split-Path $MsiPath -Leaf)"
}

# 冲突软件：只警告，不中止。它们与串流抢屏幕捕获，但也是单屏机器黑屏时唯一的远程通道。
$conflicts = @()
foreach ($svc in @('AweSunService', 'RayLinkService', 'ToDesk_Service')) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq 'Running') { $conflicts += "$svc (Running)" }
}
if ($conflicts.Count -gt 0) {
    Warn "以下软件正在运行，会与串流抢捕获: $($conflicts -join ', ')"
    Info "建议串流前手动停用；本脚本不动它们，避免切断你自己的远程通道。"
    if (-not $AllowConflict) { Info "（继续执行；如需中止按 Ctrl+C）" }
} else {
    Ok "无抢捕获的远程软件在运行"
}

# ---------- 2. 校验安装包 ----------
Step "校验安装包哈希"

$manifest = $null
if ($ManifestPath -and (Test-Path $ManifestPath)) {
    $manifest = Get-Content $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Info "manifest: $ManifestPath"
} else {
    Warn "未找到 manifest，跳过哈希比对"
}

$ExpectedHash = $null
$TargetVersion = $null
if ($manifest) {
    $ExpectedHash = $manifest.components.sunshine.sha256
    $TargetVersion = $manifest.components.sunshine.version
    Info "目标版本: $TargetVersion"
}

if ((Test-Path $MsiPath) -and $ExpectedHash) {
    $actual = (Get-FileHash $MsiPath -Algorithm SHA256).Hash.ToLower()
    if ($actual -eq $ExpectedHash.ToLower()) {
        Ok "SHA256 与 manifest 一致"
    } else {
        Fail "SHA256 不一致"
        Info "期望: $ExpectedHash"
        Info "实际: $actual"
    }
} elseif ((Test-Path $MsiPath)) {
    Info "实际 SHA256: $((Get-FileHash $MsiPath -Algorithm SHA256).Hash.ToLower())"
}

# ---------- 3. 已有安装 ----------
Step "检查已有安装"

$installed = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like '*Sunshine*' } |
             Select-Object -First 1

$NeedInstall = $true
if ($installed) {
    Info "已安装: $($installed.DisplayName) $($installed.DisplayVersion)"
    if ($TargetVersion -and $installed.DisplayVersion -eq $TargetVersion) {
        Ok "版本与目标一致，跳过安装步骤"
        $NeedInstall = $false
    } else {
        Warn "版本与目标不一致，将覆盖安装"
    }
} else {
    Info "未安装"
}

if ($DryRun) {
    Step "计划（DryRun，不做任何修改）"
    if ($NeedInstall) { Info "1. msiexec /i `"$MsiPath`" /qn /norestart" }
    Info "2. 停止 SunshineService"
    Info "3. sunshine.exe --creds $Username <随机密码>"
    Info "4. 写入 sunshine.conf: origin_web_ui_allowed=lan, upnp=disabled, dd_configuration_option=disabled"
    Info "5. 启动 SunshineService 并自检"
    Write-Host ""
    Write-Host "DryRun 结束，未做任何修改。" -ForegroundColor Yellow
    exit 0
}

if ($script:Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "前置检查未通过，中止。请先解决上面的 FAIL 项。" -ForegroundColor Red
    exit 1
}

# ---------- 4. 安装 ----------
if ($NeedInstall) {
    Step "静默安装 Sunshine"
    $msiLog = Join-Path $env:TEMP ("sunshine-install-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Info "安装日志: $msiLog"

    $args = @('/i', "`"$MsiPath`"", '/qn', '/norestart', '/l*v', "`"$msiLog`"")
    $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
    switch ($p.ExitCode) {
        0     { Ok "安装完成" }
        3010  { Ok "安装完成（需重启，本次先继续）" }
        default {
            Fail "msiexec 退出码 $($p.ExitCode)"
            Info "查看日志: $msiLog"
            exit 1
        }
    }
} else {
    Step "跳过安装"
    Ok "沿用已安装版本"
}

# ---------- 5. 定位安装目录 ----------
Step "定位安装目录"

$InstallDir = $null
if ($installed -and $installed.InstallLocation -and (Test-Path $installed.InstallLocation)) {
    $InstallDir = $installed.InstallLocation.TrimEnd('\')
}
foreach ($cand in @($InstallDir, (Join-Path $env:ProgramFiles 'Sunshine'))) {
    if ($cand -and (Test-Path (Join-Path $cand 'sunshine.exe'))) { $InstallDir = $cand; break }
}
if (-not $InstallDir -or -not (Test-Path (Join-Path $InstallDir 'sunshine.exe'))) {
    Fail "找不到 sunshine.exe，安装可能未完成"
    exit 1
}
Ok "安装目录: $InstallDir"

$Exe = Join-Path $InstallDir 'sunshine.exe'
$ConfigDir = Join-Path $InstallDir 'config'
$Conf = Join-Path $ConfigDir 'sunshine.conf'

# ---------- 5b. 虚拟手柄驱动（ViGEmBus） ----------
# Sunshine MSI 自带 scripts\vigembus_installer.exe，但安装器本身不会执行它；
# 这里按需静默安装，让"手柄能用"成为部署结果的一部分。缺失不影响串流。
Step "虚拟手柄驱动"

$ViGEmKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\ViGEmBus'
$vigemSvc = Get-Service -Name 'ViGEmBus' -ErrorAction SilentlyContinue
$vigemReg = Test-Path -LiteralPath $ViGEmKey
$vigemInstalledNow = $false
if ($vigemSvc -and $vigemReg) {
    Ok "ViGEmBus 已安装（服务 $($vigemSvc.Status)）"
} elseif ($vigemSvc -and -not $vigemReg -and $vigemSvc.Status -eq 'StopPending') {
    # 卸载残留：服务对象卡在删除挂起，注册表已无，安装器无法重建服务，只能重启
    Fail 'ViGEmBus 服务处于删除挂起状态（StopPending），请重启 Windows 后重新运行'
} else {
    $vigemSetup = Join-Path $InstallDir 'scripts\vigembus_installer.exe'
    if (-not (Test-Path -LiteralPath $vigemSetup)) {
        Warn '包内没有 scripts\vigembus_installer.exe，跳过虚拟手柄驱动'
    } else {
        Info '未检测到 ViGEmBus，开始静默安装…'
        # Advanced Installer 引导程序：/exenoui 关 UI，/qn 静默，/norestart 不重启
        $vp = Start-Process -FilePath $vigemSetup -Wait -PassThru -ArgumentList '/exenoui','/qn','/norestart'
        if ($vp.ExitCode -ne 0 -and $vp.ExitCode -ne 3010) {
            Fail "ViGEmBus 安装失败（退出码 $($vp.ExitCode)）"
        } else {
            for ($i = 0; $i -lt 60; $i++) {
                Start-Sleep -Seconds 1
                $vigemSvc = Get-Service -Name 'ViGEmBus' -ErrorAction SilentlyContinue
                if ($vigemSvc -and (Test-Path -LiteralPath $ViGEmKey)) { break }
            }
            if ($vigemSvc -and (Test-Path -LiteralPath $ViGEmKey)) {
                $vigemInstalledNow = $true
                Ok "ViGEmBus 安装完成（服务 $($vigemSvc.Status)）"
                if ($vp.ExitCode -eq 3010) { Info '安装器提示需重启后驱动才会完全生效' }
            } else {
                Fail 'ViGEmBus 安装器返回成功，但 60 秒内未出现服务；请重启后重新运行'
            }
        }
    }
}

# ---------- 6. 生成凭据 ----------
Step "设置 Web UI 凭据"

if (-not $Password) {
    $Password = ([guid]::NewGuid().ToString('N')).Substring(0, 16)
    Info "已生成随机密码"
}

$svc = Get-Service SunshineService -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -ne 'Stopped') {
    Stop-Service SunshineService -Force
    (Get-Service SunshineService).WaitForStatus('Stopped', '00:00:20')
    Ok "服务已停止，准备写配置"
}

# --creds 需要写 Program Files；本脚本已提权，可写。
$credOut = & $Exe --creds $Username $Password 2>&1
$credCode = $LASTEXITCODE
$credText = ($credOut | Out-String)
if ($credText -match 'New credentials have been created' -or $credCode -eq 0) {
    Ok "凭据已写入（用户名 $Username）"
} else {
    Warn "sunshine.exe --creds 返回 $credCode"
    Info $credText.Trim()
    Info "可稍后在 Web UI 首次访问时手动设置"
}

# ---------- 7. 写入基线配置 ----------
Step "写入基线配置"

if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
if (-not (Test-Path $Conf)) { New-Item -ItemType File -Path $Conf -Force | Out-Null }

# 用共享 profile 一次写全：locale=zh（Web UI 中文）+ 网络/显示基线。
# 不再在本地复制三键清单——两份清单一旦漂移，装完的机器就会出现"配置看似写了却没生效"。
$baseline = Get-BaselineProfile -Name physical
Info "基线键: $(@($baseline.Keys) -join ', ')"

$lines = @()
if ((Get-Item $Conf).Length -gt 0) { $lines = Get-Content $Conf -Encoding UTF8 }
$changed = 0
foreach ($k in $baseline.Keys) {
    $v = $baseline[$k]
    $pattern = "^\s*$([regex]::Escape($k))\s*="
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { $idx = $i; break } }
    if ($idx -ge 0) {
        if ($lines[$idx] -ne "$k = $v") { $lines[$idx] = "$k = $v"; $changed++; Info "$k -> $v（改写）" }
        else { Info "$k = $v（已一致）" }
    } else {
        $lines += "$k = $v"; $changed++; Info "$k -> $v（新增）"
    }
}
if ($changed -gt 0) {
    # 用无 BOM UTF8 写回，避免 Sunshine 解析配置时把 BOM 当成键名一部分
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Conf, [string[]]$lines, $utf8)
    Ok "已写入 $changed 项"
} else {
    Ok "全部基线键均已是目标值"
}

# ---------- 8. 启动服务 ----------
Step "启动服务"

Set-Service SunshineService -StartupType Automatic
Start-Service SunshineService
try {
    (Get-Service SunshineService).WaitForStatus('Running', '00:00:30')
    Ok "服务 Running，启动类型 Automatic"
} catch {
    Fail "服务未在 30 秒内进入 Running"
    Info "查事件日志与服务日志: $ConfigDir\sunshine.log"
}

# ---------- 9. 自检 ----------
Step "自检"

$s = Get-Service SunshineService -ErrorAction SilentlyContinue
if ($s.Status -eq 'Running') { Ok "B-01 服务在跑" } else { Fail "B-01 服务状态 $($s.Status)" }
if ($s.StartType -eq 'Automatic') { Ok "B-02 开机自启" } else { Fail "B-02 启动类型 $($s.StartType)" }

# 常驻监听只有 47984(HTTPS) / 47989(HTTP) / 47990(Web UI)；
# 47985–47988 是视频/控制/音频/麦克风流端口，仅在串流会话建立时才出现，不能作为启动判据。
$RequiredPorts = @(47984, 47989, 47990)
$deadline = (Get-Date).AddSeconds(30)
$have = @()
$missing = $RequiredPorts
do {
    $listen = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
              Where-Object { $_.LocalPort -in 47984..47990 }
    $have = @($listen.LocalPort | Sort-Object -Unique)
    $missing = @($RequiredPorts | Where-Object { $_ -notin $have })
    if ($missing.Count -eq 0) { break }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)

if ($missing.Count -eq 0) {
    Ok "C-01 常驻端口就绪: $($have -join ', ')"
} else {
    Fail "C-01 30 秒内仍有端口未监听: $($missing -join ', ')"
    Info "当前监听: $(if ($have) { $have -join ', ' } else { '无' })"
}

# Web UI 可用性：PowerShell 5.1 的 TLS 证书回调在无 runspace 的线程上会失败，
# 因此优先用系统自带 curl.exe 验证，没有 curl 就跳过，不做假阴性判断。
$curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curlExe) {
    $code = & $curlExe.Source -k -s -o NUL -w '%{http_code}' -u "${Username}:${Password}" 'https://localhost:47990/api/config' 2>$null
    if ($code -eq '200') { Ok "C-04 Web UI 认证通过（HTTP 200）" }
    else { Warn "C-04 Web UI 返回 HTTP $code，可在浏览器里确认" }
} else {
    Info "未找到 curl.exe，跳过 Web UI 探测"
}

$fw = Get-NetFirewallRule -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match 'Sunshine' -and $_.Enabled -eq 'True' }
if ($fw) { Ok "C-02 防火墙规则 $(@($fw).Count) 条" } else { Warn "C-02 未发现已启用的 Sunshine 防火墙规则" }

$v = (Get-Item $Exe).VersionInfo.ProductVersion
Info "宿主版本: $v"

# ---------- 10. 输出凭据 ----------
Step "登录信息"

$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
       Select-Object -ExpandProperty IPAddress

Write-Host ""
Write-Host "  Web UI : https://localhost:47990" -ForegroundColor White
foreach ($ip in $ips) { Write-Host "           https://${ip}:47990" -ForegroundColor White }
Write-Host "  用户名 : $Username" -ForegroundColor White
Write-Host "  密码   : $Password" -ForegroundColor White
Write-Host ""
Info "自签证书会提示不安全，属正常。"

$credPath = Get-DeviceStateRoot
New-Item -ItemType Directory -Path $credPath -Force | Out-Null
$credFile = Join-Path $credPath 'credentials.txt'
@(
    "Sunshine Web UI 凭据",
    "生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "地址: https://localhost:47990",
    "用户名: $Username",
    "密码: $Password"
) | Set-Content -Path $credFile -Encoding UTF8
Info "已保存到: $credFile"

# ---------- 结果落盘 ----------
# 提权窗口的输出无法被外部读取，因此关键结论另存一份 JSON，供后续核对、报告引用
# 和 Show-Result.ps1 弹窗使用。
$ports = @()
if ($listen) { $ports = @($listen.LocalPort | Sort-Object -Unique) }
# 默认路由所在网卡的地址，才是客户端该填的局域网地址
$lanIp = $null
$route = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
           Sort-Object RouteMetric | Select-Object -First 1)
if ($route.Count -gt 0) {
    $lanIp = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route[0].InterfaceIndex -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '169.254.*' } |
              Select-Object -First 1).IPAddress
}
if (-not $lanIp -and $ips) { $lanIp = @($ips)[0] }
$jsonResult = [ordered]@{
    timestamp           = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    device_id           = Get-DeviceId
    host                = $env:COMPUTERNAME
    version             = $v
    install_dir         = $InstallDir
    username            = $Username
    password            = $Password
    web_ui_local        = 'https://localhost:47990'
    web_ui_lan          = $(if ($lanIp) { "https://${lanIp}:47990" } else { $null })
    credential_file     = $credFile
    service_status      = $(if ($s) { "$($s.Status)" } else { 'Missing' })
    service_start_type  = $(if ($s) { "$($s.StartType)" } else { 'Missing' })
    listen_ports        = $ports
    firewall_rules      = $(if ($fw) { @($fw).Count } else { 0 })
    vigem_service       = $(if ($vigemSvc) { "$($vigemSvc.Status)" } else { $null })
    vigem_installed_now = $vigemInstalledNow
    config_written      = @($baseline.Keys)
    warnings            = @($script:Warnings)
    failures            = @($script:Failures)
}
$jsonPath = Join-Path $credPath 'install-result.json'
$jsonText = $jsonResult | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($jsonPath, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
Info "结果已写入: $jsonPath"

# ---------- 汇总 ----------
Write-Host ""
Write-Host "==== 完成 ====" -ForegroundColor White
if ($script:Warnings.Count -gt 0) {
    Write-Host "警告 $($script:Warnings.Count) 条:" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($script:Failures.Count -gt 0) {
    Write-Host "失败 $($script:Failures.Count) 条:" -ForegroundColor Red
    $script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "下一步：打开 Moonlight，添加主机 localhost，配对时把 PIN 填进 Web UI 的 PIN 页。" -ForegroundColor Green
exit 0
