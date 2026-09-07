@echo off
cd /d "%~dp0"
title Odysseus Control Center
powershell.exe -NoExit -ExecutionPolicy Bypass -File ".\dashboard.ps1"
echo.
echo ========================================================
echo Dashboard exited or crashed. Review error details above.
echo ========================================================
pause