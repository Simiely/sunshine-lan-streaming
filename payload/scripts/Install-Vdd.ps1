#Requires -Version 5.1
<#
.SYNOPSIS
    从随包文件安装 Virtual Display Driver（MTT VDD），并把 Sunshine 切到 vdd 基线。

.DESCRIPTION
    目标：连上串流时激活虚拟屏、禁用两块物理屏（显示器无信号自动待机），
    断流后立即回滚。手机拿到与自身比例匹配的屏，人离开时桌面不亮。

    为什么不用 winget：
      实测 winget 把这个包当成 portable(zip)，装完会去启动 GUI 控制程序。
      在提权脚本里这一步会静默挂死（CPU 0.2s、零 I/O、日志 0 字节），
      而且一旦断网整个安装就废了。交付目标是"解压即装"，运行时不允许联网。

      改为：驱动包在构建阶段下载并按 SHA256 锁定，随 zip 分发；
      安装时只做本地解压 + pnputil，全程零网络请求。

    为什么用 MTT VDD 而不是复用现成 IDD：
      向日葵的 OrayIddDriver 与 RayLink Virtual Display Adapter 都已装在本机，
      但按 G-01/G-02 它们必须在串流前停用。服务一停虚拟屏可能跟着消失，
      与串流流程自相矛盾。MTT VDD 是独立驱动，不受这两个软件影响。

    安全闸：识别不到虚拟屏输出时，在**改写 sunshine.conf 之前**退出。
    绝不允许把 output_name 指向一个不存在的设备——那正好会复现黑屏。

.PARAMETER OutputName
    跳过自动识别，显式指定虚拟屏的 \\.\DISPLAYn。

.PARAMETER BundlePath
    指定驱动包 zip 路径。默认在上两级目录的 vendor\ 里找 VDD.Control.*.zip。

.PARAMETER Uninstall
    回滚：卸载驱动并把 Sunshine 切回 physical 基线。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install-Vdd.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Install-Vdd.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$OutputName,
    [string]$BundlePath,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Baseline.ps1')

# 显式 -OutputName 可能经 cmd / Start-Process 传入带引号的值，先剥掉包裹引号，
# 否则写进 sunshine.conf 的会是 '\\.\DISPLAYn'（含引号），Sunshine 认不出输出屏。
if ($OutputName) {
    $OutputName = ([string]$OutputName).Trim()
    if ($OutputName.Length -ge 2) {
        $first = $OutputName[0]
        $last  = $OutputName[$OutputName.Length - 1]
        if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
            $OutputName = $OutputName.Substring(1, $OutputName.Length - 2).Trim()
        }
    }
}

# 版本、URL、SHA、size 只认 manifest（单一真源），脚本内不再复制一份。
# 发行 zip 里 manifest 在包根，仓库里 manifest 在上一级目录。
$manifestPath = @(
    (Join-Path (Split-Path $PSScriptRoot -Parent) 'manifest\components.json'),
    (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'manifest\components.json')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $manifestPath) {
    Write-Host 'FAIL 找不到 manifest/components.json，无法校验 VDD 资产。'
    exit 2
}
$m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ExpectedSha  = [string]$m.components.vdd.sha256
$ExpectedSize = [long]$m.components.vdd.size_bytes

$Conf      = Get-SunshineConfPath
$Sibling   = Join-Path $PSScriptRoot 'Restore-Baseline.ps1'
$StateDir  = Get-DeviceStateRoot
$StateFile = Join-Path $StateDir 'display-state.json'
$WorkDir   = Join-Path $StateDir 'vdd'
$ExitCode  = 0

Write-Host '==== 虚拟显示器方案 ===='
Write-Host "管理员    $(Test-Admin)"
Write-Host ''

Assert-Admin -Hint '请双击 payload\安装虚拟屏.cmd，它会在 UAC 提示里请求提权。'

# 全量落盘日志：控制台被关掉、或脚本半路退出，都能事后定位停在哪一步
$LogFile = Join-Path $StateDir 'install-vdd.log'
try { Start-Transcript -Path $LogFile -Force | Out-Null } catch { }

# 未捕获的终止错误不能静默吞掉 —— 否则表现就是"停在那儿，什么也不显示"
trap {
    Write-Host ''
    Write-Host "FAIL 未预期的错误：$($_.Exception.Message)"
    Write-Host "     $($_.InvocationInfo.PositionMessage)"
    Write-Host "     详细日志：$LogFile"
    exit 1
}

# ---------- 0 安装前快照 ----------
$before = @(Get-DxgiOutputs)
Write-Host "当前输出  $(if ($before.Count) { ($before | ForEach-Object { "$($_.Output)[$($_.Attached)]←$($_.Adapter)" }) -join ' | ' } else { '未取到' })"

if (-not (Test-Path -LiteralPath $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
}
$confBefore = Read-ConfMap -Path $Conf
$prevName = $null
if ($confBefore.Contains('output_name')) { $prevName = $confBefore['output_name'] }

# 快照必须"只记一次"。
# 首次安装时 conf 里的 output_name 一定是物理屏，而 before 里也还没有虚拟屏；
# 但第二次运行时 conf 已经是虚拟屏名——若照抄就会把虚拟屏记成"原物理屏"，
# 将来 -Uninstall 会把 output_name 还原到虚拟屏上，等于卸载后仍然黑屏。
$prevState   = Get-DisplayState -Path $StateFile
$knownOut    = $null
$physicalOut = $null
if ($prevState) {
    if ($prevState.PSObject.Properties.Name -contains 'vdd_output')     { $knownOut    = $prevState.vdd_output }
    if ($prevState.PSObject.Properties.Name -contains 'physical_output') { $physicalOut = $prevState.physical_output }
}
# physical_output 必须是本次快照里真实存在的输出：
# 旧快照缺字段时不能拿当前 output_name 顶上——重跑时它已经是虚拟屏 GUID，
# 会把虚拟屏记成"原物理屏"，卸载时还原到已移除的设备。
if ($physicalOut -and -not @($before | Where-Object { $_.Output -eq $physicalOut }).Count) {
    $physicalOut = $null
}
if (-not $physicalOut) { $physicalOut = @($before | Select-Object -First 1).Output }

$state = [ordered]@{
    saved_at        = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    physical_output = $physicalOut
    vdd_output      = $knownOut
    outputs         = @($before | ForEach-Object {
        [ordered]@{ output = $_.Output; adapter = $_.Adapter; attached = $_.Attached }
    })
}
Set-DisplayState -Path $StateFile -State $state
Write-Host "状态快照  $StateFile"
Write-Host "          物理屏归位目标 = $(if ($physicalOut) { $physicalOut } else { '未记录' })"
if ($knownOut) { Write-Host "          上次识别的虚拟屏 = $knownOut" }
Write-Host ''

function Get-VddAdapter {
    # 保留这个名字给展示用，实际来源换成注册表（见 _Baseline.ps1 的说明：
    # Get-PnpDevice 在提权会话里可能静默返回空，导致误判"未安装"而重复装驱动）
    return @(Get-VddDeviceInstances)
}

<#
    在 pnputil /enum-drivers 的输出里找 VDD 的驱动包，返回其 oemXX.inf 发布名。
    输出是空行分隔的块，每块含「发布名称 / 原始名称 / 提供程序名称」，中英文都要认。
#>
function Get-VddPublishedName {
    $txt = & pnputil.exe /enum-drivers 2>&1
    $blocks = @()
    $cur = @{}
    foreach ($line in $txt) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($cur.Count -gt 0) { $blocks += ,$cur; $cur = @{} }
            continue
        }
        if     ($line -match '^\s*(?:发布名称|Published Name)\s*:\s*(\S+)')    { $cur['pub']  = $Matches[1] }
        elseif ($line -match '^\s*(?:原始名称|Original Name)\s*:\s*(\S+)')     { $cur['orig'] = $Matches[1] }
        elseif ($line -match '^\s*(?:提供程序名称|Provider Name)\s*:\s*(.+?)\s*$') { $cur['prov'] = $Matches[1] }
    }
    if ($cur.Count -gt 0) { $blocks += ,$cur }

    $hit = @($blocks | Where-Object {
        ($_.ContainsKey('prov') -and $_.prov -match '(?i)virtual display|pyrosoft|mike') -or
        ($_.ContainsKey('orig') -and $_.orig -match '(?i)vdd|virtual.*display')
    })
    return @($hit | ForEach-Object { $_.pub })
}

# ---------- 回滚模式 ----------
if ($Uninstall) {
    Write-Host '模式      卸载并回滚'

    # 先移除设备节点，再删驱动包。顺序反了会留下一个找不到驱动的残设备。
    $devs = @(Get-VddAdapter)
    foreach ($d in $devs) {
        Write-Host "移除设备  $($d.FriendlyName)  $($d.InstanceId)"
        & pnputil.exe /remove-device $d.InstanceId 2>&1 | ForEach-Object { "          $_" }
    }

    $names = Get-VddPublishedName
    if ($names.Count -gt 0) {
        foreach ($n in $names) {
            Write-Host "卸载驱动  pnputil /delete-driver $n"
            & pnputil.exe /delete-driver $n /uninstall /force 2>&1 | ForEach-Object { "          $_" }
        }
    } else {
        Write-Host '卸载驱动  未在驱动库里找到 VDD 包，跳过'
    }

    Write-Host ''
    # 还原 output_name：优先用快照里的 physical_output（安装前那块物理屏），
    # 且必须确认它现在还真实存在，否则宁可不写——指向不存在的设备正是黑屏成因。
    # 注意不能读 output_name 字段：那是"当前值"，重跑后被写成虚拟屏名，
    # 拿它还原等于卸载完还指着已经消失的虚拟屏。
    $restoreName = $null
    $saved = Get-DisplayState -Path $StateFile
    if ($saved) {
        $want = $null
        if ($saved.PSObject.Properties.Name -contains 'physical_output') { $want = $saved.physical_output }
        if (-not $want -and $saved.PSObject.Properties.Name -contains 'output_name') { $want = $saved.output_name }

        if ($want) {
            $now  = @(Get-DxgiOutputs)
            $hitN = @($now | Where-Object { $_.Output -eq $want })
            if ($hitN.Count -gt 0) {
                $restoreName = $want
                Write-Host "还原输出  用记录的 $restoreName（当前适配器：$($hitN[0].Adapter)）"
            } else {
                Write-Host "还原输出  记录的 $want 当前不存在，保留现有 output_name"
                $alt = @($now | Where-Object { $_.Attached -eq 'yes' })
                if ($alt.Count -gt 0) {
                    Write-Host "         当前可用：$(($alt | ForEach-Object { $_.Output }) -join ', ')"
                }
            }
        } else {
            Write-Host '还原输出  快照里没有物理屏记录，保留现有 output_name'
        }
    } else {
        Write-Host '还原输出  无安装前快照，保留现有 output_name'
    }

    $siblingArgs = @('-Profile', 'physical')
    if ($restoreName) { $siblingArgs += @('-OutputName', $restoreName) }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $Sibling @siblingArgs
    exit $LASTEXITCODE
}

# ---------- 1 定位并校验随包驱动 ----------
if (-not $BundlePath) {
    # 兼容两种布局：仓库内 payload\scripts 与解压后的 scripts\（zip 根即 payload 内容）
    $candidates = @(
        (Join-Path (Split-Path $PSScriptRoot -Parent) 'vendor'),
        (Join-Path $PSScriptRoot 'vendor'),
        (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'payload\vendor')
    )
    foreach ($vendorDir in $candidates) {
        if (-not (Test-Path -LiteralPath $vendorDir)) { continue }
        $cand = @(Get-ChildItem $vendorDir -Filter 'VDD.Control.*.zip' -File -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending)
        if ($cand.Count -gt 0) { $BundlePath = $cand[0].FullName; break }
    }
}

if (-not $BundlePath -or -not (Test-Path -LiteralPath $BundlePath)) {
    Write-Host 'FAIL 找不到随包驱动 VDD.Control.*.zip。'
    Write-Host '     它应当位于 payload\vendor\ 下并随 zip 一起分发。'
    Write-Host '     构建阶段由 tools\build\Build-Package.ps1 拉取并校验，安装时不得联网下载。'
    exit 2
}

$fi = Get-Item -LiteralPath $BundlePath
Write-Host "驱动包    $($fi.Name)  $([math]::Round($fi.Length/1MB,2)) MB"
if ($fi.Length -ne $ExpectedSize) {
    Write-Host "FAIL 大小不符：实际 $($fi.Length)，期望 $ExpectedSize。包不完整，拒绝安装。"
    exit 2
}

# 68 MB 读哈希要一会儿，不报进度就是"卡住"
Write-Host '校验      SHA256 计算中…' -NoNewline
$swHash = [System.Diagnostics.Stopwatch]::StartNew()
$actualSha = (Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256).Hash.ToLower()
$swHash.Stop()
Write-Host (" {0:N1}s" -f $swHash.Elapsed.TotalSeconds)
if ($actualSha -ne $ExpectedSha) {
    Write-Host 'FAIL SHA256 不符。'
    Write-Host "     实际 $actualSha"
    Write-Host "     期望 $ExpectedSha"
    exit 2
}
Write-Host '          SHA256 与 manifest 一致'
Write-Host ''

# ---------- 2 解包 ----------
# PS 5.1 的 Expand-Archive 默认走进度条，解 71 MB 包会慢好几倍；
# 关掉进度显示能显著缩短这一段，也避免控制台被进度帧刷屏。
$ProgressPreference = 'SilentlyContinue'

if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
Write-Host '解包      进行中…' -NoNewline
$swZip = [System.Diagnostics.Stopwatch]::StartNew()
Expand-Archive -LiteralPath $BundlePath -DestinationPath $WorkDir -Force
$swZip.Stop()
Write-Host (" {0:N1}s  → {1}" -f $swZip.Elapsed.TotalSeconds, $WorkDir)

$infFiles = @(Get-ChildItem $WorkDir -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue)
if ($infFiles.Count -eq 0) {
    Write-Host 'FAIL 驱动包里没有 .inf，无法用 pnputil 安装。'
    Write-Host '     包内文件（用于判断打包结构是否变了）：'
    Get-ChildItem $WorkDir -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 25 |
        ForEach-Object { "       $($_.FullName.Substring($WorkDir.Length + 1))" }
    exit 2
}

# 包里有多个 INF：MttVDD.inf（显示类）与 VirtualAudioDriver.inf（虚拟音频）。
# 绝不能靠 'vdd|virtual' 模糊匹配——两者都会命中，装错的后果是多出一个音频设备。
$archDir = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'ARM64' } else { 'x86' }
$inf = @($infFiles | Where-Object { $_.FullName -match "(?i)\\$archDir\\VDD\\" -and $_.Name -match '(?i)^mttvdd\.inf$' })
if ($inf.Count -eq 0) {
    $inf = @($infFiles | Where-Object { $_.Name -match '(?i)^mttvdd\.inf$' -and $_.Name -notmatch '(?i)audio|vad' })
}
if ($inf.Count -eq 0) {
    $inf = @($infFiles | Where-Object { $_.Name -notmatch '(?i)audio|vad' })
}
if ($inf.Count -eq 0) {
    Write-Host 'FAIL 找不到显示类驱动的 .inf（包里只有音频驱动？结构可能变了）。'
    $infFiles | ForEach-Object { "       $($_.FullName.Substring($WorkDir.Length + 1))" }
    exit 2
}
$inf = $inf[0]

# 二次确认 Class 为 Display，防止包结构变化时装错驱动
$infText = Get-Content -LiteralPath $inf.FullName -Raw
if ($infText -notmatch '(?im)^\s*Class\s*=\s*Display\s*$') {
    Write-Host "FAIL $($inf.Name) 不是显示类驱动（Class != Display），拒绝安装。"
    exit 2
}
Write-Host "驱动 INF  $($inf.FullName.Substring($WorkDir.Length + 1))（Class=Display）"

# 驱动默认配置：count=1、gpu=default、含 1080p 与 1440p。
# 只在目标不存在时落位，避免覆盖用户已有配置。
$VddConfTarget = 'C:\VirtualDisplayDriver\vdd_settings.xml'
$vddConfSrc    = Join-Path $WorkDir 'Dependencies\vdd_settings.xml'
if ((Test-Path -LiteralPath $vddConfSrc) -and -not (Test-Path -LiteralPath $VddConfTarget)) {
    New-Item -ItemType Directory -Path (Split-Path $VddConfTarget) -Force | Out-Null
    Copy-Item -LiteralPath $vddConfSrc -Destination $VddConfTarget -Force
    Write-Host "驱动配置  已落位 $VddConfTarget（1 块屏，含 1080p/1440p）"
} elseif (Test-Path -LiteralPath $VddConfTarget) {
    Write-Host "驱动配置  保留既有 $VddConfTarget"
} else {
    Write-Host 'WARN 包里没有 Dependencies\vdd_settings.xml，驱动将使用内置默认值'
}

# 打印配置里的模式清单，便于核对。
# 初始分辨率由驱动版本与 EDID 决定，不再假设恒为 800x600；
# 设备若需声明预期值，写在 conf/devices/<device_id>.json 的 expected_initial_resolution。
# 判据是模式列表是否覆盖目标分辨率，不是当前分辨率等于列表第一项。
$expectedRes = $null
if (Test-Path -LiteralPath $VddConfTarget) {
    try {
        [xml]$vddXml = Get-Content -LiteralPath $VddConfTarget -Raw -Encoding UTF8
        $r0 = @($vddXml.SelectNodes('//resolution'))
        if ($r0.Count -gt 0) {
            $expectedRes = "$($r0[0].width)x$($r0[0].height)"
            Write-Host "配置模式  $($r0.Count) 项，第一项 $expectedRes"
        }
    } catch {
        Write-Host "WARN 解析 vdd_settings.xml 失败：$($_.Exception.Message)"
    }
}
Write-Host ''

# ---------- 3 本地安装（零网络） ----------
# 这是 ROOT 枚举的 UMDF/IddCx 设备（INF 里 hw-id 是 Root\MttVDD）。
# pnputil /add-driver 只把驱动包塞进驱动库，不会创建这个设备节点；
# 缺了建节点这步，后面的 90 秒等不到任何显示适配器。所以用包里自带的 devcon。
$already = @(Get-VddAdapter)

# 重复实例必须清掉。devcon install 对同一个 hw-id 是「新建实例」而不是「复用」，
# 所以一次误判就会多出一块虚拟屏，识别随即因为"多出 2 个新输出"中止。
# 保留 InstanceId 最小的那个，删掉其余的；删完不重装，避免再分配新的 GDI 编号。
if ($already.Count -gt 1) {
    $keep = @($already | Sort-Object InstanceId)[0]
    $drop = @($already | Where-Object { $_.InstanceId -ne $keep.InstanceId })
    Write-Host "安装驱动  检测到 $($already.Count) 个 VDD 实例，保留 $($keep.InstanceId)，清理其余 $($drop.Count) 个"
    foreach ($d in $drop) {
        Write-Host "          移除 $($d.InstanceId)"
        & pnputil.exe /remove-device $d.InstanceId 2>&1 | ForEach-Object { "            $_" }
    }
    Start-Sleep -Seconds 2
    $already = @(Get-VddAdapter)
    Write-Host "          清理后剩余 $($already.Count) 个"

    # 设备正在被桌面占用时 pnputil 会拒绝移除，静默失败后再往下走，
    # 只会在识别阶段报"多出 2 个新输出"，让人摸不着头脑。这里直接说清楚。
    if ($already.Count -gt 1) {
        Write-Host ''
        Write-Host "FAIL 清理后仍有 $($already.Count) 个 VDD 实例，无法唯一定位虚拟屏。"
        Write-Host "     逐个残留：$(($already | ForEach-Object { $_.InstanceId }) -join ', ')"
        Write-Host '     处理办法：打开「设备管理器 → 显示适配器」，把多余的「Virtual Display Driver」逐个右键卸载，然后重跑。'
        exit 2
    }
}

# ---------- 3.5 同步设备分辨率 ----------
# dd_resolution_option=auto 只能切到 xml 里声明过的模式，请求到列表外会静默
# 失败（手机端表现为停在 800x600）。各设备的原生分辨率必须先写进驱动配置。
$presetPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'conf\vdd-resolutions.txt'
$resSync    = Merge-VddResolutions -ConfPath $VddConfTarget -PresetPath $presetPath
$resPlan    = @($resSync.Plan)
$resRemoved = @($resSync.Removed)

if ($resPlan.Count -gt 0) {
    Write-Host "设备模式  $($resPlan.Count) 项"
    foreach ($p in $resPlan) {
        Write-Host "            $($p.Name)  $($p.Resolution)@$($p.Refresh)Hz  $($p.Action)"
    }
    if ($resRemoved.Count -gt 0) {
        Write-Host "            移除多余模式：$($resRemoved -join ', ')"
    }
} else {
    Write-Host '设备模式  无预设文件，跳过（auto 只能用到驱动内置模式）'
}

# 是否要重建设备。
# 只看配置是否改动过。不再检查"设备分辨率是否等于配置第一项"——
# 初始分辨率由 hardcoded EDID 决定（恒为 800x600），那个判据必然误报，
# 会导致每次重跑都白白重建设备一次。
$needRebuild = [bool]$resSync.Changed

if ($needRebuild) {
    Write-Host '分辨率    重建虚拟显示设备以让驱动重读配置'
    if ($already.Count -gt 0) {
        # 为什么不用 pnputil disable/enable：
        #   实测 2026-11-24 16:18 那次，disable/enable 确实让设备编号从 43 变成 44
        #   （说明设备栈重建了），但 DXGI 里依旧是 800x600 —— VDD 在没有任何可用
        #   配置时用的兜底值。也就是说 UMDF 宿主进程没退出，配置仍读的是缓存。
        # 改成移除设备节点再重新创建，迫使驱动完整重新加载并重读 vdd_settings.xml。
        Write-Host '分辨率    移除旧设备节点…'
        foreach ($d in $already) {
            $rmOut = & pnputil.exe /remove-device $d.InstanceId 2>&1
            $rmOut | ForEach-Object { "          $_" }
        }
        Start-Sleep -Seconds 2

        $devcon = Join-Path $WorkDir 'Dependencies\devcon.exe'
        if (Test-Path -LiteralPath $devcon) {
            Write-Host '分辨率    重新创建虚拟显示设备…'
            $mkOut = & $devcon install $inf.FullName 'Root\MttVDD' 2>&1
            $mkOut | ForEach-Object { "          $_" }
            Start-Sleep -Seconds 2
        } else {
            Write-Host 'WARN 包里没有 devcon.exe，无法重建设备；配置已写入，重启系统后生效'
        }

        $already = @(Get-VddAdapter)
        Write-Host "          重建后实例：$(if ($already.Count) { ($already | ForEach-Object { $_.InstanceId }) -join ', ' } else { '未取到' })"
    }
} else {
    Write-Host '分辨率    无需变更'
}

if ($already.Count -gt 0) {
    Write-Host "安装驱动  已存在，跳过：$(($already | ForEach-Object { "$($_.FriendlyName)[$($_.Status)] $($_.InstanceId)" }) -join ', ')"
} else {
    $devcon = Join-Path $WorkDir 'Dependencies\devcon.exe'
    if (Test-Path -LiteralPath $devcon) {
        Write-Host '安装驱动  devcon install 进行中…'
        $swDev = [System.Diagnostics.Stopwatch]::StartNew()
        $devOut = & $devcon install $inf.FullName 'Root\MttVDD' 2>&1
        $devOut | ForEach-Object { "          $_" }
        $rc = $LASTEXITCODE
        $swDev.Stop()
        Write-Host ("安装驱动  返回码 {0}，耗时 {1:N1}s" -f $rc, $swDev.Elapsed.TotalSeconds)
        # devcon: 0 成功；1 需重启；其余为失败
        if ($rc -ne 0 -and $rc -ne 1) {
            Write-Host "FAIL devcon 返回 $rc。若是签名或策略拦截，先确认 H-03 智能应用控制为关闭。"
            exit 2
        }
        if ($rc -eq 1) { Write-Host '          OK（提示需重启，继续等设备枚举）' }
        else { Write-Host '          OK' }
    } else {
        Write-Host 'WARN 包里没有 Dependencies\devcon.exe，退回 pnputil（可能不会创建设备节点）'
        & pnputil.exe /add-driver $inf.FullName /install 2>&1 | ForEach-Object { "          $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAIL pnputil 返回 $LASTEXITCODE。"
            exit 2
        }
    }
}

# ---------- 4 等虚拟屏真正激活 ----------
# devcon 返回 0 只代表"驱动包装好、设备节点已建"；UMDF 宿主启动、
# IddCx 加入桌面还要再等几秒，这段时间表现就是"装完卡住不动"。
#
# 判据用 DXGI 输出而不是 PnP 设备：Get-PnpDevice 单次约 2.3 秒，
# 塞进紧轮询会把等待时间直接翻倍；而 dxgi-info 只要约 0.2 秒，
# 且它反映的才是"这块屏能不能被 Sunshine 捕获"这个真正关心的状态。
# 实测本机 OrayIddDriver 设备状态是 OK，却在 DXGI 里没有任何输出——
# 设备存在 ≠ 输出可用，这个坑必须绕开。
$beforeOut = @($before | ForEach-Object { $_.Output })

# ---------- 4a 优先用确定性算法取 device_id ----------
# 设备节点建好后，从 PnP 监视器实例 + EDID 直接复算 Sunshine 的 device_id。
# 成功时整段"等 DXGI 激活 + 识别 DISPLAYn"都可以跳过：不依赖编号、
# 不需要把虚拟屏接回桌面，也不会因为日志写入时序而退回易变编号。
$pnpId = $null
for ($i = 0; $i -lt 8; $i++) {
    $pnpId = Get-VddDeviceIdFromPnp
    if ($pnpId) { break }
    Start-Sleep -Seconds 2
}
$target = $null
if ($pnpId) {
    Write-Host "稳定 ID   $pnpId（EDID + 实例 ID 复算，跳过 DXGI 识别）"
    $target = $pnpId
} else {
Write-Host '等待激活  轮询 DXGI 输出（最多 60 秒）…'

# 单屏笔记本实测（redmibookpro15x，AMD 780M）：设备节点 OK、驱动已加载，
# 但 IddCx 输出不会自动加入桌面，DXGI 一直只报物理屏。DisplaySwitch /extend
# 一次就能让虚拟屏出现，且是可逆动作——不改变任何 Sunshine 配置。
#
# 重装/重建设备后还有另一种情况（4070S，2026-11-26）：设备与显示器对象都是 OK，
# 但 Windows 按显示数据库把这块屏保持为"未接入"，DXGI 始终不枚举。
# 这时 DisplaySwitch 不一定生效，需要用 CCD 把 VDD 显式接回桌面（Hide-Vdd -Show）。
$extendTried = $false
$ccdTried    = $false
$ccdRetried  = $false

$deadline = (Get-Date).AddSeconds(60)
$outputs  = @()
$tick     = 0
while ((Get-Date) -lt $deadline) {
    $tick++
    $outputs = @(Get-DxgiOutputs)

    if (-not $ccdTried -and $tick -ge 3) {
        $newOut = @($outputs | Where-Object { $_.Output -notin $beforeOut })
        if ($newOut.Count -eq 0) {
            $ccdTried = $true
            Write-Host '          尝试通过 CCD 把虚拟屏接回桌面…'
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Hide-Vdd.ps1') -Show 2>&1 |
                ForEach-Object { Write-Host "          $_" }
            Start-Sleep -Seconds 2
            $outputs = @(Get-DxgiOutputs)
        }
    }

    if (-not $extendTried -and $ccdTried -and $tick -ge 8) {
        $newOut = @($outputs | Where-Object { $_.Output -notin $beforeOut })
        if ($newOut.Count -eq 0) {
            $extendTried = $true
            Write-Host '          CCD 未生效，尝试 DisplaySwitch /extend…'
            & DisplaySwitch.exe /extend 2>$null
            Start-Sleep -Seconds 3
            $outputs = @(Get-DxgiOutputs)
        }
    }

    # 布局被系统重置时再试一次 CCD
    if (-not $ccdRetried -and $extendTried -and $tick -ge 14) {
        $newOut = @($outputs | Where-Object { $_.Output -notin $beforeOut })
        if ($newOut.Count -eq 0) {
            $ccdRetried = $true
            Write-Host '          再次通过 CCD 接回虚拟屏…'
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Hide-Vdd.ps1') -Show 2>&1 |
                ForEach-Object { Write-Host "          $_" }
            Start-Sleep -Seconds 2
            $outputs = @(Get-DxgiOutputs)
        }
    }

    if ($knownOut -and $outputs.Count -gt 0) {
        if (@($outputs | Where-Object { $_.Output -eq $knownOut }).Count -eq 1) {
            Write-Host "          虚拟屏 $knownOut 已就绪（沿用上次识别结果）"
            break
        }
    }
    $newOut = @($outputs | Where-Object { $_.Output -notin $beforeOut })
    if ($newOut.Count -gt 0) {
        Write-Host "          新输出 $($newOut[0].Output) 已出现"
        break
    }
    # 重跑场景：虚拟屏本来就在 before 快照里，差集为空、也没有"新输出"。
    # 这种情况必须靠 knownOut（上次识别结果）判断，不能只看"设备存在且能枚举到
    # 任意输出"——虚拟屏被数据库保持为未接入时，设备 OK、物理屏也有输出，
    # 但 VDD 并不在 DXGI 里，提前放行会让后面的识别直接失败（4070S 实测）。

    # 每 5 秒报一次，让人知道还活着、还要等多久
    if ($tick % 5 -eq 0) {
        Write-Host ("          已等 {0,2} 秒  当前输出 {1} 个" -f $tick, $outputs.Count)
    }
    Start-Sleep -Seconds 1
}

# PnP 状态只查一次，用于展示；不参与循环判据
$adapter = @(Get-VddAdapter)
if ($adapter.Count -eq 0) {
    Write-Host 'FAIL 没有 VDD 显示适配器。'
    Write-Host '     打开「设备管理器 → 显示适配器」，看是否有带感叹号的设备。'
    exit 2
}
Write-Host "驱动就绪  $(($adapter | ForEach-Object { "$($_.FriendlyName)[$($_.Status)]" }) -join ', ')"

if (Test-Path -LiteralPath $VddConfTarget) {
    Write-Host "驱动配置  $VddConfTarget（$((Get-Item $VddConfTarget).Length) 字节）"
} else {
    Write-Host 'WARN 驱动配置未落位，虚拟屏可能不会出现'
}
Write-Host ''

# ---------- 5 识别虚拟屏输出 ----------
# 循环是"看到第一个新输出就 break"的，多实例或慢枚举时第二块屏可能晚一拍才出现，
# 直接下去判定会看到 2 个而误判歧义。停 2 秒拿稳定快照。
Start-Sleep -Seconds 2
$outputs = @(Get-DxgiOutputs)
Write-Host '当前输出'
foreach ($o in $outputs) {
    Write-Host ("          {0,-14} {1,-9} {2,-11} ←  {3}" -f $o.Output, "[$($o.Attached)]", $o.Resolution, $o.Adapter)
}

# 驱动启动时启用的模式 = vdd_settings.xml 里 <resolutions> 的第一项。
# 它只在"还没被 Sunshine 改过分辨率"时成立，正好是重跑时用来认屏的抓手。
# （$expectedRes 已在第 2 步算好）

$target = $OutputName
if (-not $target) {
    # 不传 ExpectedResolution：不同机器/驱动版本的初始分辨率并不相同，
    # 默认走差集判定；显式 -OutputName 或设备配置优先。
    $target = Find-VddOutput -Current $outputs -BeforeOutputs $beforeOut -Known $knownOut
    if ($target -and -not $knownOut) {
        $hit = @($outputs | Where-Object { $_.Output -eq $target })[0]
        if ($hit -and $hit.Output -notin $beforeOut) {
            Write-Host "          判定依据：新出现的输出"
        } elseif ($expectedRes -and $hit -and $hit.Resolution -eq $expectedRes) {
            Write-Host "          判定依据：分辨率 $expectedRes 与驱动初始模式一致"
        } else {
            Write-Host '          判定依据：GDI 编号落在 IddCx 段（启发式，可用 -OutputName 覆盖）'
        }
    }
}

if (-not $target) {
    # 已用 device_id 绑定时，DISPLAYn 识别只是可选步骤——output_name 写 GUID
    # 就不依赖编号，设备存在即可直接应用配置（GUID 会在第 6 步重新解析）。
    $curMap = Read-ConfMap -Path $Conf
    $curOut = if ($curMap.Contains('output_name')) { [string]$curMap['output_name'] } else { '' }
    if ($curOut -match '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') {
        Write-Host "识别      跳过 DISPLAYn（output_name 已绑定 device_id $curOut）"
        $target = $curOut
    }
}
}

if ($pnpId) {
    # 复算成功时跳过了 DXGI 识别，但设备本身仍需是就绪状态
    $adapter = @(Get-VddAdapter)
    if ($adapter.Count -eq 0) {
        Write-Host 'FAIL 没有 VDD 显示适配器。'
        Write-Host '     打开「设备管理器 → 显示适配器」，看是否有带感叹号的设备。'
        exit 2
    }
    Write-Host "驱动就绪  $(($adapter | ForEach-Object { "$($_.FriendlyName)[$($_.Status)]" }) -join ', ')"
}

if (-not $target) {
    $newOnes = @($outputs | Where-Object { $_.Output -notin $beforeOut })
    Write-Host ''
    Write-Host 'FAIL 无法唯一确定虚拟屏对应的 \\.\DISPLAYn，已中止，sunshine.conf 未做任何改动。'
    if ($newOnes.Count -gt 1) {
        Write-Host "     本次多出 $($newOnes.Count) 个新输出，无法判断哪一个是虚拟屏："
        $newOnes | ForEach-Object { Write-Host "       $($_.Output)  ←  $($_.Adapter)" }
        Write-Host '     若其中有向日葵 / RayLink 的虚拟屏，先把它们停用再重跑。'
    } else {
        Write-Host '     原因通常是：虚拟屏还没激活（未出现在 DXGI 输出里），或驱动未生效。'
    }
    Write-Host '     处理办法：'
    Write-Host '       1) 打开「显示设置」，确认多显示器布局里有一块新屏；'
    Write-Host "       2) 重跑并显式指定，例如：-OutputName '\\.\DISPLAY25'"
    exit 4
}

Write-Host ''
Write-Host "目标输出  $target"

# 把驱动声明过的模式打出来，便于一眼确认手机的分辨率确实在列
try {
    [xml]$mx = Get-Content -LiteralPath $VddConfTarget -Raw -Encoding UTF8
    $modes = @(@($mx.vdd_settings.resolutions.resolution) | ForEach-Object { "$($_.width)x$($_.height)" })
    if ($modes.Count -gt 0) {
        Write-Host "支持模式  $($modes -join ', ')"
    }
} catch { }
# 识别结果持久化：VDD 用显卡渲染，DXGI 里的适配器名与物理屏完全相同，
# 下一次运行无法靠名字或差集重新认出它，只能靠这次记下的名字。
Set-DisplayStateField -Path $StateFile -Name 'vdd_output' -Value $target | Out-Null
Write-Host ''

# ---------- 6 应用 vdd 基线 ----------
# output_name 不能写 \\.\DISPLAYn：编号在设备重新启用后会变，Sunshine 找不到
# 目标屏就静默回退物理屏，表现为"分辨率怎么选都不变"（2026-11-24 实测）。
# 这里从 Sunshine 启动日志里取虚拟屏的稳定 device_id（GUID）。
# 服务需要先重启一次，日志才会打印包含 VDD 的最新设备列表。
Write-Host ''
if ($pnpId) {
    $stableId = $pnpId
    Write-Host "稳定 ID   $stableId（复算结果，跳过日志解析）"
} else {
Write-Host '稳定 ID   重启服务以获取 device_id…'
try {
    Restart-Service -Name $script:SunshineService -Force -ErrorAction Stop
    (Get-Service -Name $script:SunshineService).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    Start-Sleep -Seconds 2
} catch {
    Write-Host "WARN 重启服务失败：$($_.Exception.Message)"
}

function Get-VddDeviceIdFromLog {
    $log = Join-Path (Join-Path $env:ProgramFiles 'Sunshine\config') 'sunshine.log'
    if (-not (Test-Path -LiteralPath $log)) { return $null }
    $text = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    $marker = 'Currently available display devices:'
    $idx = $text.LastIndexOf($marker)
    if ($idx -lt 0) { return $null }
    $start = $text.IndexOf('[', $idx)
    if ($start -lt 0) { return $null }
    $depth = 0
    $end = -1
    for ($i = $start; $i -lt $text.Length; $i++) {
        if ($text[$i] -eq '[') { $depth++ }
        elseif ($text[$i] -eq ']') { $depth--; if ($depth -eq 0) { $end = $i; break } }
    }
    # 日志是边跑边写的，设备列表可能还没写完整；返回 null 让调用方继续等
    if ($end -lt 0) { return $null }
    try {
        $devices = $text.Substring($start, $end - $start + 1) | ConvertFrom-Json
        $vdd = @($devices | Where-Object { $_.friendly_name -match '(?i)VDD|Virtual Display' }) | Select-Object -First 1
        if ($vdd -and $vdd.device_id) { return [string]$vdd.device_id }
    } catch { }
    return $null
}

# 服务启动后设备列表是异步写入的，固定等 3 秒在慢机器上不够；
# 轮询最多 20 秒，避免解析失败后把 output_name 退回易变的 \\.\DISPLAYn。
$stableId = $null
for ($i = 1; $i -le 20; $i++) {
    $stableId = Get-VddDeviceIdFromLog
    if ($stableId) { break }
    Start-Sleep -Seconds 1
}
if (-not $stableId) {
    # 配置里已经有 GUID 时直接沿用：它是稳定的，比退回 DISPLAYn 安全
    $confNow = Read-ConfMap -Path $Conf
    $curGuid = if ($confNow.Contains('output_name')) { [string]$confNow['output_name'] } else { '' }
    if ($curGuid -match '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') {
        $stableId = $curGuid
        Write-Host "稳定 ID   沿用配置中的 device_id $stableId"
    }
}
if ($stableId) {
    Write-Host "稳定 ID   $stableId（friendly_name 含 VDD）"
    $target = $stableId
} else {
    Write-Host "WARN 日志里没有 VDD 的 device_id，退回 $target —— 重启后编号可能变，需重跑本脚本"
}
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $Sibling -Profile vdd -OutputName $target
$ExitCode = $LASTEXITCODE

# ---------- 7 收尾提示 ----------
Write-Host ''
Write-Host '==== 完成 ===='
if ($ExitCode -eq 0) {
    Write-Host 'Sunshine 已切换为捕获虚拟屏：连上时只保留它，断开回滚物理屏。'
    Write-Host "捕获目标  $target"
    Write-Host ''
    Write-Host '手机端必须做的一件事：'
    Write-Host '  Moonlight → 设置 → 打开「优化游戏设置」'
    Write-Host '  不开的话 dd_resolution_option=auto 会静默失效，画面会停在 800x600。'
    Write-Host ''
    Write-Host '若断开后显示没恢复、或主机卡住，立刻运行 payload\恢复显示.cmd。'
    Write-Host '要退回物理屏方案：本脚本加 -Uninstall。'

    # 待机隐藏：把虚拟屏从桌面拓扑移除，物理屏布局保持不变；
    # Sunshine 连接时用 ensure_only_display 拉起，断开回滚到这个隐藏态。
    Write-Host ''
    Write-Host '待机隐藏  把虚拟屏从桌面拓扑移除…'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Hide-Vdd.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'WARN 虚拟屏隐藏失败；可手动运行 scripts\Hide-Vdd.ps1 重试'
    }
} else {
    Write-Host '配置已写入但服务或端口未就绪，先看 sunshine.log 再重试。'
}
exit $ExitCode
