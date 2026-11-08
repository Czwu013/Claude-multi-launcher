@echo off
rem Double-click this to open Claude Multi Launcher. No build step, nothing installed.
rem It starts the local window (claude-multi-server.ps1) with no visible console, so the
rem only window you see is the launcher itself. Keep this file next to the src and ui folders.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0claude-multi-server.ps1"
exit /b 0
