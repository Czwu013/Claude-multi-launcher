param([string]$Root = (Split-Path -Parent $PSScriptRoot), [string]$DesktopPath = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Puts a "Claude Multi Launcher" icon on the desktop. The icon runs the local window with a
# hidden PowerShell host, so double-clicking it shows only the launcher. Run once; nothing is
# installed. Delete the icon any time to undo.
$root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$server = Join-Path $root 'claude-multi-server.ps1'
if (-not (Test-Path -LiteralPath $server)) {
    throw 'claude-multi-server.ps1 was not found. Keep this tool in the repo folder.'
}

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Import-Module (Join-Path $root 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
$iconPath = Get-CmlIconPath
if (-not $iconPath) { throw (Get-CmlText 'err.icon_missing') }
$desktop = $DesktopPath
if (-not $desktop) { $desktop = [Environment]::GetFolderPath('Desktop', 'DoNotVerify') }
if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
if (-not (Test-Path -LiteralPath $desktop -PathType Container)) {
    throw ('Desktop folder not found: ' + $desktop)
}
$lnkPath = Join-Path $desktop 'Claude Multi Launcher.lnk'

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
if ((Test-Path -LiteralPath $lnkPath) -and $lnk.Arguments -notlike '*claude-multi-server.ps1*') {
    throw ('Refusing to replace an unrelated shortcut: ' + $lnkPath)
}
$lnk.TargetPath = $ps
$lnk.Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $server)
$lnk.WorkingDirectory = $root
$lnk.WindowStyle = 7          # minimized; the PowerShell host is hidden anyway
$lnk.IconLocation = ($iconPath + ',0')
$lnk.Description = 'Claude Multi Launcher'
$lnk.Save()

Write-Host ('Created: ' + $lnkPath)
