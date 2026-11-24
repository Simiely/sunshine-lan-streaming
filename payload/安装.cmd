@echo off
setlocal
title Sunshine LAN Streaming - Install

rem Admin required: install service, write Program Files, firewall rules
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges, click "Yes" in the prompt...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ============================================
echo   Sunshine LAN Streaming - Install
echo ============================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1" %*
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
