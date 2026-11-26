@echo off
setlocal
title Sunshine LAN Streaming - Install Resolution Cards

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
echo   Install Moonlight Resolution Cards
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Install-Cards.ps1" %*
set RC=%errorlevel%

echo.
if %RC% neq 0 (
    echo Install did not complete. Exit code %RC%
) else (
    echo Done.
)
echo.
pause
exit /b %RC%
