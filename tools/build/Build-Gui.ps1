#Requires -Version 5.1
<#
.SYNOPSIS
    构建图形控制台（PySide6 / PyInstaller onefile）。

.DESCRIPTION
    产物：dist\gui\Sunshine控制台.exe
    随后由 Build-Package.ps1 复制到离线包根目录，与 一键部署.cmd 同级。
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
$DistDir  = Join-Path $RepoRoot 'dist\gui'
$WorkDir  = Join-Path $RepoRoot 'build\gui'

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Host "FAIL 找不到 $Source" -ForegroundColor Red
    exit 1
}

$pyInstallerArgs = @(
    '-m', 'PyInstaller',
    '--noconfirm',
    '--onefile',
    '--windowed',
    '--name', 'Sunshine控制台',
    '--distpath', $DistDir,
    '--workpath', $WorkDir,
    '--specpath', $WorkDir
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

$exe = Join-Path $DistDir 'Sunshine控制台.exe'
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

$sizeMb = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)
Write-Host ''
Write-Host "OK   $exe  ${sizeMb} MB  冒烟测试通过" -ForegroundColor Green
