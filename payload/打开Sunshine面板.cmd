@echo off
setlocal
title Sunshine Web Panel
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Panel.ps1"
set RC=%errorlevel%
if not "%RC%"=="0" pause
exit /b %RC%