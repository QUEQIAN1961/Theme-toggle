@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create-Shortcut.ps1"
if errorlevel 1 (
    echo Failed to create the shortcut.
    pause
    exit /b 1
)
