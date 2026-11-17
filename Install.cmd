@echo off
rem Double-click to install the Neat ND-1000 on Windows 10/11 (x64).
rem Starts Install.ps1 with the execution policy bypassed for this one run only.
rem If Windows SmartScreen says "Windows protected your PC": More info -> Run anyway.
title Neat ND-1000 installer
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
echo.
pause
