@echo off
setlocal
title Sunshine LAN Stream - One Click + Web Panel

rem Standard deployment plus the on-demand no-login panel shortcut.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges, click "Yes" in the prompt...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ============================================
echo   Sunshine LAN Stream - One Click
echo   install + virtual display + cards + panel
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\OneClick.ps1" -WithWebPanel
set RC=%errorlevel%

if "%RC%"=="0" exit /b 0

echo.
echo One-click deployment did not fully complete. Exit code %RC%
echo See the dialog and C:\Program Files\Sunshine\config\sunshine.log
pause
exit /b %RC%