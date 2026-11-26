#Requires -Version 5.1
<#
.SYNOPSIS
    构建图形控制台（PySide6 / PyInstaller onedir）。

.DESCRIPTION
    产物：dist\gui-<版本>\Sunshine控制台\Sunshine控制台.exe + _internal\
    随后由 Build-Package.ps1 把该目录的内容铺到离线包根目录：
    exe 保持根级可双击，_internal 是运行库，不能单独删除。
    输出目录带版本号，避免上一版 GUI 正在运行时锁住 exe、导致重建失败。
    用 onedir 而不是 onefile：onefile 每次启动都要把几十兆依赖解压到 Temp，
    实测冒烟启动约 5 秒；onedir 不落地解压，启动接近源码运行。
    构建完自动跑一次 --smoke-test，确保 exe 能加载 Qt 并正常退出。

.PARAMETER NoClean
    保留 PyInstaller 缓存，缩短重复构建时间。
#>
[CmdletBinding()]
param(
    [switch]$NoClean
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Source   = Join-Path $RepoRoot 'tools\gui\sunshine_gui.py'
$Manifest = Join-Path $RepoRoot 'manifest\components.json'
$version  = [string](Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 |
                     ConvertFrom-Json).package.version
if (-not $version) {
    Write-Host 'FAIL manifest 缺少 package.version' -ForegroundColor Red
    exit 1
}
$DistDir  = Join-Path $RepoRoot "dist\gui-$version"
$WorkDir  = Join-Path $RepoRoot 'build\gui'

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Host "FAIL 找不到 $Source" -ForegroundColor Red
    exit 1
}

# 清掉上一次的单文件 exe / 目录，避免新旧两种产物混在一起。
if (Test-Path -LiteralPath $DistDir) {
    Remove-Item -LiteralPath $DistDir -Recurse -Force
}

$pyInstallerArgs = @(
    '-m', 'PyInstaller',
    '--noconfirm',
    '--onedir',
    '--windowed',
    '--name', 'Sunshine控制台',
    '--distpath', $DistDir,
    '--workpath', $WorkDir,
    '--specpath', $WorkDir,
    '--exclude-module', 'PyQt5',
    '--exclude-module', 'PyQt6',
    '--exclude-module', 'matplotlib',
    '--exclude-module', 'numpy',
    '--exclude-module', 'pandas',
    '--exclude-module', 'tkinter'
)
if (-not $NoClean) { $pyInstallerArgs += '--clean' }
$pyInstallerArgs += $Source

Write-Host ''
Write-Host '==== 构建图形控制台 ====' -ForegroundColor White
& python @pyInstallerArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "FAIL PyInstaller 退出码 $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

$appDir = Join-Path $DistDir 'Sunshine控制台'
$exe = Join-Path $appDir 'Sunshine控制台.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "FAIL 未生成 $exe" -ForegroundColor Red
    exit 1
}

# --smoke-test 会跳过提权、使用 offscreen 平台，构造窗口后自动退出。
$smoke = Start-Process -FilePath $exe -ArgumentList '--smoke-test' -PassThru -Wait
if ($smoke.ExitCode -ne 0) {
    Write-Host "FAIL 冒烟测试退出码 $($smoke.ExitCode)" -ForegroundColor Red
    exit $smoke.ExitCode
}

$sizeMb = [math]::Round(
    ((Get-ChildItem -LiteralPath $appDir -Recurse -File |
      Measure-Object -Property Length -Sum).Sum / 1MB), 1)
Write-Host ''
Write-Host "OK   $exe  目录 ${sizeMb} MB  冒烟测试通过" -ForegroundColor Green
