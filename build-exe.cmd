@echo off
setlocal
cd /d "%~dp0"
rem First source build downloads the pinned Microsoft WebView2 SDK from official NuGet.
rem This does not install the Runtime, modify the registry, or download Claude.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Build-Native.ps1"
if errorlevel 1 (
  echo Build failed. See the error above.
  pause
  exit /b 1
)
echo Done: claude-multi-launcher.exe
pause
