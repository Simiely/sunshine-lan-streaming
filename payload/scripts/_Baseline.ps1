#Requires -Version 5.1
<#
.SYNOPSIS
    Sunshine 配置与显示输出的共享工具函数。被 Restore-Baseline.ps1 / Install-Vdd.ps1 点源引用。

.DESCRIPTION
    抽出来的理由：配置键集合、合并写回、服务重启、端口轮询这几段逻辑
    一旦被复制到多个脚本里，就会各自漂移。本机已经因为「每次只写一部分键」
    丢过两次基线配置，见 docs/配置写入覆盖.md。

    两套 profile：
      physical —— 不接管显示拓扑，只固定捕获物理屏。安全，但分辨率不随客户端自适应。
      vdd      —— 捕获虚拟屏，连上时禁用其余所有屏（显示器无信号自动待机）。
                  干净，但会用到 ensure_only_display，见 docs/显示拓扑卡死.md 的风险。

    两套都只写 dd_* 与网络相关的键，不动 output_name 之外的用户键。
#>

$script:SunshineService = 'SunshineService'
$script:RequiredPorts   = @(47984, 47989, 47990)

# ---------- 设备维度 ----------
# 一台机器一个 ID 与一个状态目录，避免多设备互相覆盖。
# COMPUTERNAME 用于命名，UUID 用于识别克隆镜像（见 docs/设备硬件标准.md）。
$script:DeviceIdCache = $null
function Get-DeviceId {
    if ($script:DeviceIdCache) { return $script:DeviceIdCache }
    $id = ([string]$env:COMPUTERNAME).ToLowerInvariant() -replace '[^a-z0-9-]', '-'
    if (-not $id) { $id = 'unknown-host' }
    $script:DeviceIdCache = $id
    return $id
}

function Get-DeviceStateRoot {
    return (Join-Path $env:ProgramData ("sunshine-lan-streaming\devices\" + (Get-DeviceId)))
}

function Get-DeviceFingerprint {
    $cs  = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    # 虚拟适配器不算宿主 GPU，否则 AMD / Intel 机器会被 Oray / RayLink 顶掉
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -notmatch '(?i)oray|raylink|virtual display|mttvdd|parsec|spacedesk' } |
              ForEach-Object { [pscustomobject]@{ name = $_.Name; driver = $_.DriverVersion } })
    return [pscustomobject]@{
        device_id = Get-DeviceId
        hostname  = $env:COMPUTERNAME
        uuid      = [string]$cs.UUID
        vendor    = [string]$cs.Vendor
        model     = [string]$cs.Name
        cpu       = [string]$cpu.Name
        os        = [string]$os.Caption
        os_build  = [string]$os.BuildNumber
        gpu       = @($gpus)
    }
}

<#
    设备配置：conf\devices\defaults.json + conf\devices\<device_id>.json，
    后者覆盖前者。所有原本写死在本机的值都从这里取，未配置时回落到 $Default。
#>
function Get-DeviceConfig {
    $dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'conf\devices'
    $cfg = @{}
    foreach ($f in @((Join-Path $dir 'defaults.json'), (Join-Path $dir ((Get-DeviceId) + '.json')))) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
        } catch { Write-Host "WARN 设备配置读取失败 $f ：$($_.Exception.Message)" }
    }
    return $cfg
}

function Get-DeviceConfigValue {
    param([string]$Name, $Default = $null, $Config = $null)
    if (-not $Config) { $Config = Get-DeviceConfig }
    if ($Config.ContainsKey($Name)) { return $Config[$Name] }
    return $Default
}

function Get-SunshineConfPath {
    return (Join-Path $env:ProgramFiles 'Sunshine\config\sunshine.conf')
}

function Get-SunshineLogPath {
    return (Join-Path $env:ProgramFiles 'Sunshine\config\sunshine.log')
}

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    param([string]$Hint = '请以管理员身份重新运行，或通过对应的 .cmd 启动器双击运行。')
    if (-not (Test-Admin)) {
        Write-Host 'FAIL 需要管理员权限：Program Files 下的配置不可写，服务也无法重启。'
        Write-Host "     $Hint"
        exit 3
    }
}

<#
    返回指定 profile 的基线键集合。
    -OutputName 为 $null 时不设置 output_name（保持文件里已有的值）。
#>
function Get-BaselineProfile {
    param(
        [ValidateSet('physical', 'vdd')]
        [string]$Name = 'physical',
        [string]$OutputName
    )

    $set = [ordered]@{}

    # Web UI 中文：装完即生效，不需要用户进设置页手选。
    # 真机实证见 docs/reports/2026-11-24-安卓真机验证.md 中 sunshine.conf 的 locale = zh。
    $set['locale'] = 'zh'

    switch ($Name) {
        'physical' {
            # 不接管显示拓扑。dd_configuration_option 为 disabled 时，其余 dd_* 全部失效。
            $set['origin_web_ui_allowed']   = 'lan'
            $set['upnp']                    = 'disabled'
            $set['dd_configuration_option'] = 'disabled'
            $set['dd_resolution_option']    = 'disabled'
            $set['dd_refresh_rate_option']  = 'disabled'
            $set['dd_hdr_option']           = 'disabled'
        }
        'vdd' {
            # 切屏交给 Sunshine 原生 ensure_only_display：它在 configure_display
            # 阶段执行，早于 probe_encoders，时序正确。
            # 不要改成 disabled——那会触发 revert_configuration() 后台回滚，
            # 与编码器探测抢设备，实测让连接卡死（docs/prep命令改不了捕获屏.md）。
            # output_name 必须是稳定的 device_id（GUID），不是 \\.\DISPLAYn：
            # 编号在设备重新启用后会变，导致找不到屏、静默回退物理屏。
            $set['origin_web_ui_allowed']       = 'lan'
            $set['upnp']                        = 'disabled'
            $set['dd_configuration_option']     = 'ensure_only_display'
            $set['dd_resolution_option']        = 'auto'
            $set['dd_refresh_rate_option']      = 'auto'
            $set['dd_hdr_option']               = 'disabled'
            # 断开即回滚：缺省 disabled，Sunshine 只在应用关闭/最后会话终止时回滚，
            # 客户端断开不一定触发。2026-11-26 实测日志只有 CLIENT DISCONNECTED，
            # 没有 Trying to revert applied display device settings，物理屏不复位。
            $set['dd_config_revert_on_disconnect'] = 'enabled'
        }
    }

    if ($OutputName) { $set['output_name'] = $OutputName }
    return $set
}

<#
    读 sunshine.conf 成有序字典。忽略空行与注释，保留原有顺序。
#>
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

<#
    合并写回：只覆盖传入的键，其余键（locale 等）原样保留。
    无 BOM —— 带 BOM 时 Sunshine 会把 BOM 并进第一个键名，该键静默失效。
#>
function Write-ConfMap {
    param([string]$Path, $Map)
    $lines = @()
    foreach ($k in @($Map.Keys)) { $lines += "$k = $($Map[$k])" }
    if (-not $lines) { return }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), $utf8)
}

<#
    合并 + 备份 + 写盘 + 回读校验，返回未落盘的键列表（空数组即成功）。
    调用前须已确保服务已停止（否则服务退出时会用内存里的旧配置覆盖文件）。
#>
function Set-ConfKeys {
    param(
        [string]$Path,
        $Keys,
        [switch]$SkipBackup
    )

    if (-not $SkipBackup) {
        $backup = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-Host "备份      $backup"
    }

    $before = Read-ConfMap -Path $Path
    $merged = [ordered]@{}
    foreach ($k in @($before.Keys)) { $merged[$k] = $before[$k] }
    foreach ($k in @($Keys.Keys)) { $merged[$k] = $Keys[$k] }

    Write-ConfMap -Path $Path -Map $merged
    Write-Host "写入配置  OK（$($merged.Keys.Count) 个键）"

    $verify = Read-ConfMap -Path $Path
    $bad = @()
    foreach ($k in @($Keys.Keys)) {
        if (-not $verify.Contains($k) -or $verify[$k] -ne $Keys[$k]) { $bad += $k }
    }
    return $bad
}

function Get-ListeningPorts {
    param([int[]]$Ports = $script:RequiredPorts)
    $hit = @()
    foreach ($p in $Ports) {
        if (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) { $hit += $p }
    }
    return $hit
}

<#
    停止 + 启动服务，并轮询常驻端口。端口要 3-5 秒才起监听，不能启动后立刻判定。
#>
function Restart-SunshineService {
    param([int]$PortTimeoutSeconds = 30)

    $svc = Get-Service -Name $script:SunshineService -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host 'FAIL 找不到 SunshineService，无法重启。'
        return $false
    }

    if ($svc.Status -eq 'Running') {
        Write-Host '停止服务  进行中…'
        try {
            Stop-Service -Name $script:SunshineService -Force -ErrorAction Stop
            (Get-Service -Name $script:SunshineService).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            Write-Host '停止服务  OK'
        } catch {
            Write-Host "停止服务  FAIL $($_.Exception.Message)"
            return $false
        }
    }

    Write-Host '启动服务  进行中…'
    try {
        Start-Service -Name $script:SunshineService -ErrorAction Stop
        (Get-Service -Name $script:SunshineService).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
        Write-Host '启动服务  OK'
    } catch {
        Write-Host "启动服务  FAIL $($_.Exception.Message)"
        return $false
    }

    $deadline = (Get-Date).AddSeconds($PortTimeoutSeconds)
    $live = @()
    while ((Get-Date) -lt $deadline) {
        $live = Get-ListeningPorts
        if ($live.Count -eq $script:RequiredPorts.Count) { break }
        Start-Sleep -Milliseconds 500
    }

    $missing = @($script:RequiredPorts | Where-Object { $_ -notin $live })
    Write-Host "常驻端口  $($live -join ', ')$(if ($missing.Count -gt 0) { "（缺 $($missing -join ', ')）" })"
    return ($missing.Count -eq 0)
}

<#
    用 Sunshine 自带的 dxgi-info.exe 枚举「适配器 → \\.\DISPLAYn」映射。
    这是唯一不依赖 P/Invoke 的可靠枚举方式，且工具随 Sunshine 一起装好。
    输出按字段宽度折行，所以逐行独立匹配两个模式，不假设它们不在同一行。
#>
function Get-DxgiOutputs {
    $exe = Join-Path $env:ProgramFiles 'Sunshine\tools\dxgi-info.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return @() }

    $rows = @()
    $adapter = ''
    $lastIdx = -1
    # 用 2>&1 收流再丢掉 ErrorRecord，而不是 2>$null。
    # PS 5.1 在 $ErrorActionPreference='Stop' 下，原生程序往 stderr 写一行就会抛
    # NativeCommandError 把整个脚本打断——这正是"等设备之后突然没输出"的成因。
    $raw = & $exe 2>&1
    foreach ($line in $raw) {
        if ($line -is [System.Management.Automation.ErrorRecord]) { continue }
        $line = [string]$line
        if ($line -match 'Device Name\s*:\s*(.+?)\s*$') {
            $adapter = $Matches[1].Trim()
        }
        # 不要写成 '\\.\\DISPLAY\d+'：第三段 \\ 要求字面反斜杠，而那里其实是点号，
        # 结果永远匹配不到。用 \S* 吃掉 "\\.\" 前缀，不关心转义层数。
        if ($line -match 'Output Name\s*:\s*(\S*DISPLAY\d+)') {
            $rows += [pscustomobject]@{ Adapter = $adapter; Output = $Matches[1]; Attached = $null; Resolution = $null }
            $lastIdx = $rows.Count - 1
        }
        # AttachedToDesktop 排在 Output Name 之后，回填到最近一条
        if ($lastIdx -ge 0 -and $line -match 'AttachedToDesktop\s*:\s*(yes|no)') {
            $rows[$lastIdx].Attached = $Matches[1]
        }
        if ($lastIdx -ge 0 -and $line -match 'Resolution\s*:\s*(\d+)\s*x\s*(\d+)') {
            $rows[$lastIdx].Resolution = "$($Matches[1])x$($Matches[2])"
        }
    }
    return $rows
}

<#
    在 dxgi 输出里找虚拟屏对应的 \\.\DISPLAYn。

    判别顺序（逐级放宽，任何一级有歧义就返回 null，绝不猜）：
      0. 上次已识别过的输出名（存在即可复用）—— 重跑时零猜测
      1. 排除第三方虚拟屏后，适配器名精确指向 MTT / Virtual Display Driver
      2. 排除第三方虚拟屏后，与安装前的输出集合做差集，恰好多出一个
      3. 排除第三方虚拟屏且已连接桌面的输出里，分辨率等于驱动初始模式，恰好一个
      4. 同上范围内 GDI 编号 >= 10 的恰好一个（IddCx 的典型编号段）
      5. 交给调用方用 -OutputName 显式指定

    两个必须记住的实测事实：
      a) VDD 用显卡渲染，dxgi 里那块屏的适配器名是 "NVIDIA GeForce RTX 4070 SUPER"，
         与物理屏完全相同 —— 靠适配器名永远认不出它，只能靠差集。
      b) 本机同时装着向日葵 OrayIddDriver 与 RayLink Virtual Display Adapter。
         只要 RayLink 一运行，它就会以 "RayLink Virtual Display Adapter" 的身份
         出现在 dxgi 里，任何 'virtual|idd' 模糊匹配都会优先命中它。
         所以先按品牌把它们剔出候选池，而不是指望关键字唯一。

    第 3 级为什么成立：vdd_settings.xml 的 <resolutions> 第一项就是驱动启动时
    启用的模式（本机实测 800x600，DXGI 里那块屏正好是 800x600），
    而物理屏是 2560x1440 —— 安装完成后对不上，但重跑时能对上。
#>
function Find-VddOutput {
    param(
        [object[]]$Current,
        [string[]]$BeforeOutputs = @(),
        [string]$Known,
        [string]$ExpectedResolution
    )

    if (-not $Current -or $Current.Count -eq 0) { return $null }

    if ($Known) {
        $k = @($Current | Where-Object { $_.Output -eq $Known })
        if ($k.Count -eq 1) { return $k[0].Output }
    }

    # 第三方虚拟屏品牌黑名单：这些是别人的 IDD，绝不能被当成我们自己装的 VDD。
    # 名单来自设备配置，不再把第一台机器上装的软件当成全局真相。
    $otherIdd = [string](Get-DeviceConfigValue -Name 'other_idd_pattern' -Default '(?i)raylink|oray|sunlogin|parsec|spacedesk|usbmmidd|iddsample|duet|twomon')
    $pool = @($Current | Where-Object { $_.Adapter -notmatch $otherIdd })
    if ($pool.Count -eq 0) { $pool = $Current }

    $strict = @($pool | Where-Object { $_.Adapter -match '(?i)mtt|virtual display driver' })
    if ($strict.Count -eq 1) { return $strict[0].Output }

    $new = @($pool | Where-Object { $_.Output -notin $BeforeOutputs })
    if ($new.Count -eq 1) { return $new[0].Output }

    # 只在"已连桌面"的候选里比对，避免把未激活的输出算进来
    $live = @($pool | Where-Object { $_.Attached -ne 'no' })

    if ($ExpectedResolution) {
        $byRes = @($live | Where-Object { $_.Resolution -eq $ExpectedResolution })
        if ($byRes.Count -eq 1) { return $byRes[0].Output }
    }

    # DISPLAYn>=10 是第一台机器的经验值，换机后编号取决于已有输出数量。
    # 默认关闭；只有设备显式声明 vdd_output_strategy = display-number 才启用。
    $strategy = [string](Get-DeviceConfigValue -Name 'vdd_output_strategy' -Default 'snapshot-diff')
    if ($strategy -eq 'display-number') {
        $minNum = [int](Get-DeviceConfigValue -Name 'vdd_display_number_min' -Default 10)
        $highNum = @($live | Where-Object {
            $m = [regex]::Match([string]$_.Output, 'DISPLAY(\d+)$')
            $m.Success -and [int]$m.Groups[1].Value -ge $minNum
        })
        if ($highNum.Count -eq 1) { return $highNum[0].Output }
    }

    return $null
}

<#
    按 Sunshine/libdisplaydevice 的算法直接计算 VDD 的 device_id（GUID）。
    源码依据（libdisplaydevice win_api_layer.cpp getDeviceId）：
      data = EDID + instance_id[0 .. 第二个 '&') + instance_id[第三个 '&' .. 末尾]（含结尾 NUL）
      device_id = "{" + UUIDv5(SHA1, 空命名空间, data) + "}"
    已用 Sunshine verbose 日志的字节转储逐字节验证（4070S，2026-11-26）：
      324 字节 = 256 EDID + UTF-16LE("DISPLAY\MTT1337\1&15ECD195") + UTF-16LE("&UID256\0")
      -> {5eb52002-659f-5729-bdd8-9cdc4efd1bf5}
    能算出来就不必等 DXGI 激活、识别 DISPLAYn 或重启服务解析日志。
#>
function Get-VddDeviceIdFromPnp {
    param([string]$Pattern = '(?i)VDD by MTT|MTT1337')
    $mons = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue |
              Where-Object { $_.FriendlyName -match $Pattern -or $_.InstanceId -match $Pattern })
    if ($mons.Count -eq 0) { return $null }
    $ok = @($mons | Where-Object { $_.Status -eq 'OK' })
    $pick = if ($ok.Count -gt 0) { $ok[0] } else { $mons[0] }
    $inst = [string]$pick.InstanceId
    $i1 = $inst.IndexOf('&')
    if ($i1 -lt 0) { return $null }
    $i2 = $inst.IndexOf('&', $i1 + 1)
    if ($i2 -lt 0) { return $null }
    $i3 = $inst.IndexOf('&', $i2 + 1)
    if ($i3 -lt 0) { return $null }
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters"
    try { $edid = (Get-ItemProperty -LiteralPath $reg -Name EDID -ErrorAction Stop).EDID } catch { return $null }
    if (-not $edid -or @($edid).Count -lt 128) { return $null }
    $uni = New-Object System.Text.UnicodeEncoding($false, $true)
    $prefix = $inst.Substring(0, $i2)
    $suffix = $inst.Substring($i3) + [char]0
    $name = New-Object System.Collections.Generic.List[byte]
    $name.AddRange([byte[]]$edid)
    $name.AddRange($uni.GetBytes($prefix))
    $name.AddRange($uni.GetBytes($suffix))
    $all = New-Object byte[] (16 + $name.Count)
    [Array]::Copy($name.ToArray(), 0, $all, 16, $name.Count)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try { $h = $sha1.ComputeHash($all) } finally { $sha1.Dispose() }
    $b = New-Object byte[] 16
    [Array]::Copy($h, 0, $b, 0, 16)
    $b[6] = ($b[6] -band 0x0F) -bor 0x50
    $b[8] = ($b[8] -band 0x3F) -bor 0x80
    $hex = ($b | ForEach-Object { $_.ToString('x2') }) -join ''
    return "{$($hex.Substring(0,8))-$($hex.Substring(8,4))-$($hex.Substring(12,4))-$($hex.Substring(16,4))-$($hex.Substring(20,12))}"
}

<#
    读写 display-state.json。Install-Vdd / Restore-Baseline 共用，
    避免两处各自拼 JSON 导致字段名漂移。
#>
function Get-DisplayState {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Set-DisplayState {
    param([string]$Path, $State)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

<#
    枚举已安装的 MTT VDD 设备实例。

    为什么不走 Get-PnpDevice：实测它会在提权会话里静默返回空集。
    2026-11-24 15:23 那次运行，`ROOT\DISPLAY\0001` 明明已存在且 Status=OK，
    但脚本调用时拿到 0 个，于是又跑了一遍 devcon install；devcon 对同一个
    hw-id 是「新建实例」而不是「复用」，结果多出 ROOT\DISPLAY\0002，
    DXGI 里凭空多了第二块 800x600 虚拟屏，识别直接因歧义中止。

    注册表 Enum 分支是设备的权威来源，不受 PnP 枚举缓存影响，且更快。
    判据用 HardwareID（REG_MULTI_SZ，值为 {Root\MttVDD}），不会和
    OrayIddDriver、RayLink 混淆。注意不是 MatchingDeviceId ——
    那个值在 Control\Video\{GUID}\0000 下，Enum 分支里读不到。
#>
function Get-VddDeviceInstances {
    $root = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ROOT\DISPLAY'
    $out = @()
    if (-not (Test-Path -LiteralPath $root)) { return $out }

    foreach ($child in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        $hw = $props.HardwareID
        if (-not $hw) { continue }
        $hwStr = (@($hw) -join ';')
        if ($hwStr -notmatch '(?i)MttVDD') { continue }

        $desc = [string]$props.DeviceDesc
        if ($desc -match ';(.+)$') { $desc = $Matches[1] } else { $desc = 'Virtual Display Driver' }

        # ConfigFlags 0 = 已启用；CONFIGFLAG_DISABLED(0x1) / CONFIGFLAG_REMOVED(0x8)
        $flags = 0
        if ($null -ne $props.ConfigFlags) { $flags = [int]$props.ConfigFlags }
        $status = if ($flags -eq 0) { 'OK' } elseif ($flags -band 0x8) { 'Removed' } else { "ConfigFlags=$flags" }

        $out += [pscustomobject]@{
            InstanceId   = "ROOT\DISPLAY\$($child.PSChildName)"
            FriendlyName = $desc.Trim()
            Status       = $status
            HardwareId   = $hwStr
        }
    }
    return $out
}

<#
    按预设文件同步 vdd_settings.xml 的显示模式。

    为什么需要这个函数：
      VDD 只能切到 xml 里声明过的模式。dd_resolution_option = auto 会按客户端
      请求改分辨率，请求到列表外的模式就静默失败，画面停在原分辨率——手机端
      表现为"只有 800x600 的小画面"，而且日志里不会有明显报错。

    为什么不能用全局刷新率：
      <global> 里的 g_refresh_rate 会复制到每一个分辨率上。原来那里列了
      60/90/120/144/165/244，结果每块屏都同时拥有 244Hz，没法做到
      "iPad 120Hz、其它 60Hz"。所以这里把 global 收敛成只有 60，
      需要更高刷新率的分辨率自己在 <resolution> 里写。

    预设文件每行「设备名|宽x高|刷新率」，后两段可省略刷新率、可省略名称。
    本文件是唯一真相：不在列表里的分辨率会被删除。

    【锚点约定】预设文件的第一条会被排到 <resolutions> 首位，它同时承担
    识别虚拟屏的职责（Find-VddOutput 比对"当前分辨率 == xml 第一条"）。
    所以第一条必须是物理屏不会用到的分辨率。原来硬编码保护 800x600 的做法
    已废弃：现在只要第一条在预设列表里，清理逻辑就不会删它。

    返回：Plan（每项一条记录）、Removed（被删掉的分辨率）、Changed。
#>
function Merge-VddResolutions {
    param(
        [string]$ConfPath,
        [string]$PresetPath
    )

    $empty = [pscustomobject]@{ Plan = @(); Removed = @(); Changed = $false }
    if (-not (Test-Path -LiteralPath $ConfPath))  { return $empty }
    if (-not (Test-Path -LiteralPath $PresetPath)) { return $empty }

    # 带 BOM 的文件 VDD 解析不了，会回退到内置默认值（800x600）。
    # 这跟内容变没变无关，必须无条件重写一次修掉。
    $hasBom = $false
    try {
        $head = [System.IO.File]::ReadAllBytes($ConfPath)
        if ($head.Length -ge 3 -and $head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF) { $hasBom = $true }
    } catch { }
    if ($hasBom) {
        Write-Host '配置编码  检测到 UTF-8 BOM（VDD 无法解析），重写为无 BOM'
    }

    try {
        [xml]$xml = Get-Content -LiteralPath $ConfPath -Raw -Encoding UTF8
    } catch {
        Write-Host "WARN 读取 $ConfPath 失败：$($_.Exception.Message)"
        return $empty
    }

    $root = $xml.vdd_settings
    if (-not $root -or -not $root.resolutions) { return $empty }

    # 一律用 SelectNodes 取节点。
    # PowerShell 的 XML adapter 会把「只有文本的子元素」当成属性值暴露，
    # $root.global.g_refresh_rate 拿到的是一串字符串而不是 XmlNode，
    # 传给 RemoveChild 会抛类型转换错误。
    $resNodes = @($root.resolutions.SelectNodes('resolution'))

    $changed = $hasBom
    $plan    = @()
    $target  = @{}

    foreach ($line in @(Get-Content -LiteralPath $PresetPath -Encoding UTF8)) {
        $t = ([string]$line).Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }

        $parts = @($t -split '\|' | ForEach-Object { $_.Trim() })

        # 末段是纯数字就当刷新率，剩下的最后一段是分辨率，再前面的是名称
        $refresh = 60
        if ($parts.Count -ge 2 -and $parts[-1] -match '^\d{2,3}$') {
            $refresh = [int]$parts[-1]
            $parts = @($parts[0..($parts.Count - 2)])
        }
        if ($parts.Count -eq 0) { continue }

        $spec = $parts[-1]
        if ($spec -notmatch '^(\d{3,5})\s*[xX]\s*(\d{3,5})$') { continue }

        $w = $Matches[1]
        $h = $Matches[2]
        $key = "${w}x${h}"
        $name = if ($parts.Count -ge 2) { ($parts[0..($parts.Count - 2)] -join '|').Trim() } else { $null }
        $target[$key] = $true

        $existing = $null
        foreach ($r in $resNodes) {
            if ("$($r.width)x$($r.height)" -eq $key) { $existing = $r; break }
        }

        if ($existing) {
            # 已存在：只校正刷新率
            $rateChanged = $false
            $rn = $existing.SelectSingleNode('refresh_rate')
            if ($rn) {
                if ([string]$rn.InnerText -ne [string]$refresh) {
                    $rn.InnerText = [string]$refresh
                    $rateChanged = $true
                    $changed = $true
                }
            }
            $action = if ($rateChanged) { '已更新' } else { '已有' }
        } else {
            $node = $xml.CreateElement('resolution')
            foreach ($pair in @(@('width', $w), @('height', $h), @('refresh_rate', [string]$refresh))) {
                $e = $xml.CreateElement($pair[0])
                $e.InnerText = $pair[1]
                $node.AppendChild($e) | Out-Null
            }
            $root.resolutions.AppendChild($node) | Out-Null
            $action = '已写入'
            $changed = $true
        }

        $plan += [pscustomobject]@{
            Name       = $(if ($name) { $name } else { $key })
            Resolution = $key
            Width      = [int]$w
            Height     = [int]$h
            Refresh    = $refresh
            Action     = $action
        }
    }

    # 清理：不在目标集里的一律删掉。
    # 不硬编码保护任何分辨率——锚点改成「预设文件第一条」，它本来就在目标集里，
    # 天然不会被删。唯一要防的是目标集为空时把驱动清空（虚拟屏就彻底没模式了）。
    $removed = @()
    if ($target.Count -gt 0) {
        foreach ($r in $resNodes) {
            $k = "$($r.width)x$($r.height)"
            if ($target.ContainsKey($k)) { continue }
            $root.resolutions.RemoveChild($r) | Out-Null
            $removed += $k
            $changed = $true
        }
    } else {
        Write-Host 'WARN 预设文件里没有有效分辨率，跳过清理，避免驱动没有任何可用模式'
    }

    # 把预设文件的第一条顶到 <resolutions> 首位。
    # 识别逻辑比对的是"虚拟屏当前分辨率 == xml 第一条"，所以顺序必须有保证，
    # 不能指望删除后自然排成想要的样子。
    if ($plan.Count -gt 0) {
        $firstKey  = $plan[0].Resolution
        $firstNode = $null
        foreach ($r in $root.resolutions.SelectNodes('resolution')) {
            if ("$($r.width)x$($r.height)" -eq $firstKey) { $firstNode = $r; break }
        }
        $head = $root.resolutions.FirstChild
        if ($firstNode -and $head -and $firstNode -ne $head) {
            $root.resolutions.InsertBefore($firstNode, $head) | Out-Null
            $changed = $true
        }
    }

    # 全局刷新率收敛成只有 60，否则每块屏都会被塞进 244Hz
    if ($root.global) {
        $gNodes = @($root.global.SelectNodes('g_refresh_rate'))
        $needFix = ($gNodes.Count -ne 1) -or ([string]$gNodes[0].InnerText -ne '60')
        if ($needFix) {
            foreach ($g in $gNodes) { $root.global.RemoveChild($g) | Out-Null }
            $e = $xml.CreateElement('g_refresh_rate')
            $e.InnerText = '60'
            $root.global.AppendChild($e) | Out-Null
            $changed = $true
        }
    }

    if ($changed) {
        try {
            # 必须写成「无 BOM 的 UTF-8」。
            # XmlDocument.Save() 默认套 XmlWriter，会写出 UTF-8 BOM（EF BB BF），
            # 而 VDD 原始配置是无 BOM 的，它的解析器读不了带 BOM 的文件，
            # 会静默回退到内置默认配置（第一项 800x600）。
            # 这正是 2026-11-24 那次"配置全对但设备一直是 800x600"的根因：
            # 改文件、disable/enable、remove+install 全都无效，因为文件根本没被解析。
            $ws = New-Object System.Xml.XmlWriterSettings
            $ws.Encoding    = New-Object System.Text.UTF8Encoding($false)
            $ws.Indent      = $true
            $ws.IndentChars = '    '
            $ws.NewLineChars = "`r`n"
            $writer = [System.Xml.XmlWriter]::Create($ConfPath, $ws)
            try { $xml.Save($writer) } finally { $writer.Close() }
        }
        catch {
            Write-Host "WARN 写入 $ConfPath 失败：$($_.Exception.Message)"
            return $empty
        }
    }

    return [pscustomobject]@{ Plan = $plan; Removed = $removed; Changed = $changed }
}

<#
    只更新状态文件里的单个字段，其余字段原样保留。
    vdd_output 一旦识别成功就再也不该被覆盖成 null。
#>
function Set-DisplayStateField {
    param([string]$Path, [string]$Name, $Value)
    $s = Get-DisplayState -Path $Path
    if (-not $s) { $s = [pscustomobject]@{} }
    if ($s.PSObject.Properties.Name -contains $Name) {
        $s.$Name = $Value
    } else {
        $s | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
    Set-DisplayState -Path $Path -State $s
    return $s
}
