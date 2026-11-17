@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 %*
if errorlevel 1 pause
if not exist go2rtc.yaml pause
