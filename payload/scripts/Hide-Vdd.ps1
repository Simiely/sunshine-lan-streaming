#Requires -Version 5.1
<#
.SYNOPSIS
    待机时把虚拟显示器（VDD）从桌面拓扑中隐藏，连接串流时由 Sunshine 自行拉起。
.DESCRIPTION
    走 Windows CCD API（QueryDisplayConfig / SetDisplayConfig），按 friendly_name 定位 VDD，
    只把它从活动拓扑中去掉，物理屏的分辨率、刷新率、相对位置完全不动。
    脚本自动识别单屏/多屏：物理屏数量只用于提示，操作始终只针对 VDD。

    为什么用这组参数（均有资料来源与实机验证）：
    - 查询用 QDC_ALL_PATHS | QDC_VIRTUAL_MODE_AWARE，提交时必须带 SDC_VIRTUAL_MODE_AWARE。
      modeInfoIdx 是 16 位打包值（低位 cloneGroupId，高位 sourceModeInfoIdx），
      缺这个标志会被 SetDisplayConfig 判为非法参数（rc=87）。
    - 被停用的 path 必须把 sourceInfo/targetInfo 的 modeInfoIdx 置为 0xFFFFFFFF
      （MS 文档：DISPLAYCONFIG_PATH_MODE_IDX_INVALID），否则会把无效索引写进数据库。
    - 提交时带 SDC_SAVE_TO_DATABASE，让数据库记录的当前配置保持有效；
      否则 Sunshine 的 isApiAccessAvailable（SDC_VALIDATE | SDC_USE_DATABASE_CURRENT）
      会持续失败，applySettings 每 5 秒重试且不停止，表现为客户端一直转圈。
    - Sunshine 拉起时会先用 SDC_TOPOLOGY_SUPPLIED 查数据库里的“仅 VDD”拓扑（约 0.3 秒），
      查不到才回退 SDC_USE_SUPPLIED_DISPLAY_CONFIG + best mode；本脚本会顺带校验数据库条目。
.PARAMETER Show
    反向操作：把 VDD 重新接回桌面（Sunshine 维护/排障时用）。
.PARAMETER Match
    目标显示器的 friendly_name 匹配串，默认 VDD by MTT。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Hide-Vdd.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Hide-Vdd.ps1 -Show
.NOTES
    设计依据见 docs/虚拟屏待机隐藏.md。Install-Vdd.ps1 装完会自动调用一次；
    日常不需要手动运行，显示异常时可用 -Show 把虚拟屏接回来。
#>
[CmdletBinding()]
param(
    [switch]$Show,
    [string]$Match = 'VDD by MTT'
)
$ErrorActionPreference = 'Stop'

$cs = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class DisplayTopology
{
    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RATIONAL { public uint Numerator; public uint Denominator; }

    [StructLayout(LayoutKind.Sequential)]
    public struct SOURCE_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;   // 低 16 位 cloneGroupId，高 16 位 sourceModeInfoIdx
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct TARGET_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;   // 低 16 位 desktopModeInfoIdx，高 16 位 targetModeInfoIdx
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public RATIONAL refreshRate;
        public uint scanLineOrdering;
        public int targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_INFO
    {
        public SOURCE_INFO sourceInfo;
        public TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL { public int x; public int y; }

    // DISPLAYCONFIG_SOURCE_MODE：width, height, pixelFormat, position（无 flags）
    [StructLayout(LayoutKind.Sequential)]
    public struct SOURCE_MODE
    {
        public uint width;
        public uint height;
        public uint pixelFormat;
        public POINTL position;
        public uint reserved;
    }

    // 64 字节 = infoType(4) + id(4) + adapterId(8) + union(48)
    // union 前 24 字节按 SOURCE_MODE 解释，后 24 字节用 tail 原样带回。
    [StructLayout(LayoutKind.Sequential, Size = 64)]
    public struct MODE_INFO
    {
        public uint infoType;
        public uint id;
        public LUID adapterId;
        public SOURCE_MODE sourceMode;
        public ulong tail0;
        public ulong tail1;
        public ulong tail2;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DEVICE_INFO_HEADER
    {
        public uint type;
        public uint size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct TARGET_DEVICE_NAME
    {
        public DEVICE_INFO_HEADER header;
        public uint flags;
        public uint outputTechnology;
        public ushort edidManufactureId;
        public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string monitorDevicePath;
    }

    const uint QDC_ALL_PATHS = 0x1;
    const uint QDC_VIRTUAL_MODE_AWARE = 0x10;
    const uint PATH_ACTIVE = 0x1;
    const uint MODE_IDX_INVALID = 0xFFFFFFFF;

    const uint SDC_TOPOLOGY_SUPPLIED = 0x10;
    const uint SDC_USE_SUPPLIED = 0x20;
    const uint SDC_VALIDATE = 0x40;
    const uint SDC_APPLY = 0x80;
    const uint SDC_SAVE_TO_DATABASE = 0x200;
    const uint SDC_ALLOW_CHANGES = 0x400;
    const uint SDC_ALLOW_PATH_ORDER_CHANGES = 0x2000;
    const uint SDC_VIRTUAL_MODE_AWARE = 0x8000;
    const uint SDC_USE_DATABASE_CURRENT = 0xF;

    const uint GET_TARGET_NAME = 2;

    [DllImport("user32.dll")]
    static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPath, out uint numMode);

    [DllImport("user32.dll")]
    static extern int QueryDisplayConfig(uint flags, ref uint numPath, [Out] PATH_INFO[] paths,
        ref uint numMode, [Out] MODE_INFO[] modes, IntPtr topologyId);

    [DllImport("user32.dll")]
    static extern int SetDisplayConfig(uint numPath, PATH_INFO[] paths, uint numMode, MODE_INFO[] modes, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int DisplayConfigGetDeviceInfo(ref TARGET_DEVICE_NAME packet);

    static string TargetName(PATH_INFO p)
    {
        TARGET_DEVICE_NAME n = new TARGET_DEVICE_NAME();
        n.header.type = GET_TARGET_NAME;
        n.header.size = (uint)Marshal.SizeOf(typeof(TARGET_DEVICE_NAME));
        n.header.adapterId = p.targetInfo.adapterId;
        n.header.id = p.targetInfo.id;
        int rc = DisplayConfigGetDeviceInfo(ref n);
        if (rc != 0) return "";
        string friendly = n.monitorFriendlyDeviceName == null ? "" : n.monitorFriendlyDeviceName;
        string path = n.monitorDevicePath == null ? "" : n.monitorDevicePath;
        return friendly + "|" + path;
    }

    static bool IsMatch(PATH_INFO p, string match)
    {
        string s = TargetName(p);
        if (s.Length == 0) return false;
        return s.IndexOf(match, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    static bool Query(out PATH_INFO[] paths, out MODE_INFO[] modes, out uint pathCount, out uint modeCount)
    {
        uint pc, mc;
        paths = null; modes = null; pathCount = 0; modeCount = 0;
        int rc = GetDisplayConfigBufferSizes(QDC_ALL_PATHS | QDC_VIRTUAL_MODE_AWARE, out pc, out mc);
        if (rc != 0) return false;
        paths = new PATH_INFO[pc];
        modes = new MODE_INFO[mc];
        rc = QueryDisplayConfig(QDC_ALL_PATHS | QDC_VIRTUAL_MODE_AWARE, ref pc, paths, ref mc, modes, IntPtr.Zero);
        if (rc != 0) return false;
        pathCount = pc; modeCount = mc;
        return true;
    }

    // 每个活动输出一行：friendly|path  pos=x,y  WxH
    public static string Layout()
    {
        PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc;
        if (!Query(out paths, out modes, out pc, out mc)) return "FAIL query";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < pc; i++)
        {
            if ((paths[i].flags & PATH_ACTIVE) == 0) continue;
            uint smi = paths[i].sourceInfo.modeInfoIdx >> 16;
            sb.Append(TargetName(paths[i]));
            if (smi == 0xFFFF || smi >= mc)
            {
                sb.Append("  pos=?  ?");
            }
            else
            {
                sb.Append("  pos=");
                sb.Append(modes[smi].sourceMode.position.x);
                sb.Append(",");
                sb.Append(modes[smi].sourceMode.position.y);
                sb.Append("  ");
                sb.Append(modes[smi].sourceMode.width);
                sb.Append("x");
                sb.Append(modes[smi].sourceMode.height);
            }
            sb.Append("\n");
        }
        return sb.ToString();
    }

    // 把匹配的显示器从活动拓扑中移除，其它输出的路径与模式保持不变。
    public static string Hide(string match)
    {
        PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc;
        if (!Query(out paths, out modes, out pc, out mc)) return "FAIL query";

        int hit = -1;
        for (int i = 0; i < pc; i++)
        {
            if ((paths[i].flags & PATH_ACTIVE) != 0 && IsMatch(paths[i], match)) { hit = i; break; }
        }
        if (hit < 0) return "OK already-hidden";

        paths[hit].flags &= ~PATH_ACTIVE;
        paths[hit].sourceInfo.modeInfoIdx = MODE_IDX_INVALID;
        paths[hit].targetInfo.modeInfoIdx = MODE_IDX_INVALID;
        paths[hit].sourceInfo.statusFlags = 0;
        paths[hit].targetInfo.statusFlags = 0;

        int rc = SetDisplayConfig(pc, paths, mc, modes,
            SDC_USE_SUPPLIED | SDC_APPLY | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE | SDC_VIRTUAL_MODE_AWARE);
        if (rc != 0) return "FAIL SetDisplayConfig rc=" + rc;
        return "OK hidden";
    }

    // 把匹配的显示器重新接回桌面（best mode）。
    public static string Show(string match)
    {
        PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc;
        if (!Query(out paths, out modes, out pc, out mc)) return "FAIL query";

        int inactive = -1;
        for (int i = 0; i < pc; i++)
        {
            if ((paths[i].flags & PATH_ACTIVE) != 0 && IsMatch(paths[i], match)) return "OK already-visible";
            if ((paths[i].flags & PATH_ACTIVE) == 0 && inactive < 0 && paths[i].targetInfo.targetAvailable != 0 && IsMatch(paths[i], match))
                inactive = i;
        }
        if (inactive < 0) return "FAIL target-not-found";

        paths[inactive].flags |= PATH_ACTIVE;
        paths[inactive].sourceInfo.modeInfoIdx = 0xFFFF0000; // cloneGroupId=0，source mode 无效
        paths[inactive].targetInfo.modeInfoIdx = MODE_IDX_INVALID;
        paths[inactive].sourceInfo.statusFlags = 0;
        paths[inactive].targetInfo.statusFlags = 0;

        int rc = SetDisplayConfig(pc, paths, mc, modes,
            SDC_USE_SUPPLIED | SDC_APPLY | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE | SDC_VIRTUAL_MODE_AWARE);
        if (rc != 0) return "FAIL SetDisplayConfig rc=" + rc;
        return "OK activated";
    }

    // Sunshine 的 isApiAccessAvailable：校验数据库中的当前配置是否可用。
    public static int ApiCheck()
    {
        return SetDisplayConfig(0, null, 0, null, SDC_VALIDATE | SDC_USE_DATABASE_CURRENT);
    }

    // 校验数据库里是否存在“仅 VDD”的拓扑（Sunshine 第一步 SDC_TOPOLOGY_SUPPLIED 的快路径）。
    public static int FastPathCheck(string match)
    {
        PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc;
        if (!Query(out paths, out modes, out pc, out mc)) return -1;
        for (int i = 0; i < pc; i++)
        {
            if (!IsMatch(paths[i], match)) continue;
            PATH_INFO one = paths[i];
            one.flags = PATH_ACTIVE;
            one.sourceInfo.modeInfoIdx = 0xFFFF0000;
            one.targetInfo.modeInfoIdx = MODE_IDX_INVALID;
            one.sourceInfo.statusFlags = 0;
            one.targetInfo.statusFlags = 0;
            PATH_INFO[] arr = new PATH_INFO[] { one };
            return SetDisplayConfig(1, arr, 0, null,
                SDC_VALIDATE | SDC_TOPOLOGY_SUPPLIED | SDC_ALLOW_PATH_ORDER_CHANGES | SDC_VIRTUAL_MODE_AWARE);
        }
        return -1;
    }

    // 重新保存当前配置，修复数据库当前条目（仅在 ApiCheck 失败时调用）。
    public static int Resave()
    {
        PATH_INFO[] paths; MODE_INFO[] modes; uint pc, mc;
        if (!Query(out paths, out modes, out pc, out mc)) return -1;
        return SetDisplayConfig(pc, paths, mc, modes,
            SDC_USE_SUPPLIED | SDC_APPLY | SDC_ALLOW_CHANGES | SDC_SAVE_TO_DATABASE | SDC_VIRTUAL_MODE_AWARE);
    }
}
'@

if (-not ('DisplayTopology' -as [type])) {
    Add-Type -TypeDefinition $cs -Language CSharp
}

function Get-Layout {
    @([DisplayTopology]::Layout() -split "`n" | Where-Object { $_ })
}

function Get-ScreenInfo {
    param([string[]]$Lines)
    $physical = @($Lines | Where-Object { $_ -notmatch [regex]::Escape($Match) })
    $mode = $(if ($physical.Count -le 1) { 'single' } else { 'multi' })
    return @{ Physical = $physical; Mode = $mode }
}

if ($Show) {
    Write-Host '重新接入前的活动输出：'
    Get-Layout | ForEach-Object { Write-Host "  $_" }
    $r = [DisplayTopology]::Show($Match)
    Write-Host "执行结果  $r"
    if ($r -notlike 'OK*') { exit 1 }
    Start-Sleep -Milliseconds 800
    Write-Host '重新接入后的活动输出：'
    Get-Layout | ForEach-Object { Write-Host "  $_" }
    Write-Host "SUMMARY mode=n/a physical=n/a virtual=1 action=shown"
    exit 0
}

Write-Host '隐藏前的活动输出：'
$before = Get-Layout
$before | ForEach-Object { Write-Host "  $_" }
$infoBefore = Get-ScreenInfo -Lines $before
Write-Host ("检测  物理屏 {0} 块（{1}），虚拟屏 {2}" -f $infoBefore.Physical.Count,
    $(if ($infoBefore.Mode -eq 'single') { '单屏' } else { '多屏' }),
    $(if (@($before | Where-Object { $_ -match [regex]::Escape($Match) }).Count -gt 0) { '活动' } else { '非活动' }))

if ($infoBefore.Physical.Count -eq 0) {
    # 重装 VDD 时 Windows 可能从显示数据库恢复“仅 VDD”的旧拓扑，物理屏会全黑。
    # 先强制切回扩展模式，把物理屏拉回桌面，再隐藏 VDD。
    Write-Host '检测到仅虚拟屏，尝试恢复物理屏扩展布局…'
    $switch = Join-Path $env:SystemRoot 'System32\DisplaySwitch.exe'
    for ($i = 0; $i -lt 3; $i++) {
        & $switch /extend | Out-Null
        Start-Sleep -Seconds 4
        $before = Get-Layout
        $infoBefore = Get-ScreenInfo -Lines $before
        if ($infoBefore.Physical.Count -gt 0) { break }
    }
    Write-Host '恢复后的活动输出：'
    $before | ForEach-Object { Write-Host "  $_" }
    Write-Host ("检测  物理屏 {0} 块（{1}），虚拟屏 {2}" -f $infoBefore.Physical.Count,
        $(if ($infoBefore.Mode -eq 'single') { '单屏' } else { '多屏' }),
        $(if (@($before | Where-Object { $_ -match [regex]::Escape($Match) }).Count -gt 0) { '活动' } else { '非活动' }))
    if ($infoBefore.Physical.Count -eq 0) {
        Write-Host '保持现状：虚拟屏是唯一活动输出，隐藏后没有可用桌面。'
        Write-Host "SUMMARY mode=$($infoBefore.Mode) physical=0 virtual=1 action=skip"
        exit 0
    }
}

$result = [DisplayTopology]::Hide($Match)
Write-Host "执行结果  $result"
if ($result -notlike 'OK*') { exit 1 }

Start-Sleep -Milliseconds 800
Write-Host '隐藏后的活动输出：'
$after = Get-Layout
$after | ForEach-Object { Write-Host "  $_" }

$vddStillActive = @($after | Where-Object { $_ -match [regex]::Escape($Match) }).Count -gt 0
if ($vddStillActive) {
    Write-Host 'FAIL 隐藏后虚拟屏仍在活动拓扑里'
    exit 1
}
$infoAfter = Get-ScreenInfo -Lines $after
if ($infoAfter.Physical.Count -ne $infoBefore.Physical.Count) {
    Write-Host ("FAIL 物理屏数量变化 {0} -> {1}" -f $infoBefore.Physical.Count, $infoAfter.Physical.Count)
    exit 1
}

$api = [DisplayTopology]::ApiCheck()
Write-Host "数据库当前配置校验  rc=$api"
if ($api -ne 0) {
    Write-Host '数据库当前条目无效，重新保存一次…'
    $resave = [DisplayTopology]::Resave()
    Write-Host "重新保存  rc=$resave"
    $api = [DisplayTopology]::ApiCheck()
    if ($api -ne 0) {
        Write-Host 'FAIL 数据库当前配置仍不可用，Sunshine 拉起时会持续重试'
        exit 1
    }
}

$fast = [DisplayTopology]::FastPathCheck($Match)
if ($fast -eq 0) {
    Write-Host '数据库快路径  已存在“仅 VDD”拓扑（Sunshine 拉起走 SDC_TOPOLOGY_SUPPLIED）'
} else {
    Write-Host "数据库快路径  未命中（rc=$fast），Sunshine 会回退 best mode 创建拓扑"
}

Write-Host ("完成：虚拟屏已隐藏，{0} 块物理屏保持不变。" -f $infoAfter.Physical.Count) -ForegroundColor Green
Write-Host "SUMMARY mode=$($infoAfter.Mode) physical=$($infoAfter.Physical.Count) virtual=0 action=hidden"
exit 0
