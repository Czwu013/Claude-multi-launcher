@echo off
setlocal
if not exist "%~dp0claude-multi-launcher.exe" (
  call "%~dp0build-exe.cmd"
  if errorlevel 1 exit /b 1
)
start "" "%~dp0claude-multi-launcher.exe"
exit /b 0
