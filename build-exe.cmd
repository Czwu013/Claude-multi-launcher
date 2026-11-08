@echo off
rem Builds claude-multi-launcher.exe on THIS computer with the C# compiler that ships with Windows.
rem Nothing is downloaded or installed. The exe is only a small starter for claude-multi-server.ps1,
rem so keep it in this folder (next to claude-multi-server.ps1, the src and ui folders).
setlocal
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo Could not find csc.exe ^(.NET Framework 4 compiler^). Run claude-multi-server.ps1 with PowerShell instead.
  pause
  exit /b 1
)
"%CSC%" /nologo /target:winexe /optimize+ /out:claude-multi-launcher.exe /reference:System.Windows.Forms.dll tools\Launcher.cs
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)
echo.
echo Done: %~dp0claude-multi-launcher.exe
echo Double-click it to open the window. You can drag it to the desktop as a shortcut ^(right-click, Send to, Desktop^).
pause
