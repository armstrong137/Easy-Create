@echo off
chcp 65001 >nul
title Easy Create Launcher
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\run_app.ps1"
echo.
pause
