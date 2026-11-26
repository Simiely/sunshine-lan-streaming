@echo off
setlocal
title Sunshine LAN Streaming - Virtual Display Setup

rem Admin required: install a display driver, write Program Files, restart service
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges, click "Yes" in the prompt...
    if "%*"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

cd /d "%~dp0.."

echo ============================================
echo   Sunshine LAN Streaming - Virtual Display
echo ============================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Install-Vdd.ps1" %*
set RC=%errorlevel%

echo.
if %RC% neq 0 (
    echo Setup did not complete. Exit code %RC%
    echo If the virtual display was not detected, sunshine.conf was left untouched.
) else (
    echo Done. If the host screens stay dark, run the restore-display launcher.
)
echo.
pause
exit /b %RC%
