@echo off
setlocal
title Sunshine LAN Streaming - Uninstall

rem Admin required: remove service, driver, firewall rules, Program Files
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges, click "Yes" in the prompt...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ============================================
echo   Sunshine LAN Streaming - Uninstall
echo ============================================
echo This will remove:
echo   - Sunshine service, program and config
echo   - Virtual display driver (physical screen restored)
echo   - ViGEmBus (unless you edit the command below)
echo   - Cards, firewall rules, shortcuts, state files
echo.
set /p GO=Type Y to continue, any other key cancels: 
if /i not "%GO%"=="Y" (
    echo Cancelled.
    pause
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1" -Yes
set RC=%errorlevel%

rem 0 = result saved in the dialog, close this console with it.
if "%RC%"=="0" exit /b 0

echo.
echo Uninstall did not fully complete. Exit code %RC%
pause
exit /b %RC%
