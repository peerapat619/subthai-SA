@echo off
rem GTA San Andreas - Thai subtitles: double-click installer.
rem Everything the installer does is in INSTALL.ps1; this only lifts the
rem script execution policy for this one run.
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1" %*
echo.
echo If the window closed too fast, run this from PowerShell:
echo   powershell -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1"
pause
