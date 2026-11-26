@echo off
setlocal
title Sunshine LAN Streaming - Restore Baseline

rem Admin required: restart the Sunshine service
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
echo   Sunshine LAN Streaming - Restore Baseline
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Restore-Baseline.ps1" %*
set RC=%errorlevel%

echo.
if %RC% neq 0 (
    echo Restore did not complete. Exit code %RC%
) else (
    echo Done.
)
echo.
pause
exit /b %RC%
