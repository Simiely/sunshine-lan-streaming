@echo off
setlocal
title Sunshine Web Panel
set "ROOT=%~dp0"
if not exist "%~dp0scripts\Panel.ps1" if exist "%~dp0..\scripts\Panel.ps1" set "ROOT=%~dp0..\"
cd /d "%ROOT%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Panel.ps1"
set RC=%errorlevel%
if not "%RC%"=="0" pause
exit /b %RC%