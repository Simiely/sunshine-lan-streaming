@echo off
setlocal
title Sunshine LAN Streaming - One Click

rem Admin required: install service, driver, write Program Files, firewall rules
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges, click "Yes" in the prompt...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ============================================
echo   Sunshine LAN Streaming - One Click
echo   install + virtual display + cards
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\OneClick.ps1"
set RC=%errorlevel%

rem 0 = result saved in the dialog, close this console with it.
if "%RC%"=="0" exit /b 0

echo.
echo One-click deployment did not fully complete. Exit code %RC%
echo See the dialog and C:\Program Files\Sunshine\config\sunshine.log
pause
exit /b %RC%
