@echo off
setlocal
title Sunshine LAN Streaming - Restore Display

rem Admin required: re-enable display devices
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
echo   Sunshine LAN Streaming - Restore Display
echo ============================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\Restore-Display.ps1" %*
set RC=%errorlevel%

echo.
echo If the physical screens are still dark, press Win+P on the host
echo and choose "Extend", or reboot once to rebuild the display topology.
echo.
pause
exit /b %RC%
