@echo off
rem Run this once to put a "Claude Multi Launcher" icon on your desktop.
rem After that, open the launcher by double-clicking that desktop icon. Nothing is installed.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\New-DesktopShortcut.ps1" -Root "%~dp0"
if errorlevel 1 (
  echo.
  echo Could not create the shortcut. You can still open the launcher by double-clicking
  echo "Claude Multi Launcher.cmd" in this folder.
  pause
  exit /b 1
)
echo.
echo Done. Look for "Claude Multi Launcher" on your desktop and double-click it.
pause
