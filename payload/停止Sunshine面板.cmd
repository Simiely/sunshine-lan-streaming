@echo off
setlocal
title Sunshine Web Panel - Stop
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Panel.ps1" -Action stop
exit /b %errorlevel%
