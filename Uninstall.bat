@echo off
echo Removing Mordhau Auto Demo...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Uninstall
pause
