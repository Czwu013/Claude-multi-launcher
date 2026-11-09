param([string]$Root = (Split-Path -Parent $PSScriptRoot), [string]$DesktopPath = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Puts a "Claude Multi Launcher" icon on the desktop. The shortcut opens our native EXE.
# Run once; nothing is
# installed. Delete the icon any time to undo.
$root = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$server = Join-Path $root 'claude-multi-launcher.exe'
if (-not (Test-Path -LiteralPath $server)) {
    throw 'Build the native launcher first with build-exe.cmd, or extract the complete portable package.'
}

Import-Module (Join-Path $root 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
$iconPath = Join-Path $root 'assets\launcher.ico'
if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { throw ('Launcher icon not found: ' + $iconPath) }
$desktop = $DesktopPath
if (-not $desktop) { $desktop = [Environment]::GetFolderPath('Desktop', 'DoNotVerify') }
if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
if (-not (Test-Path -LiteralPath $desktop -PathType Container)) {
    throw ('Desktop folder not found: ' + $desktop)
}
$lnkPath = Join-Path $desktop 'Claude Multi Launcher.lnk'

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$ownedNative = $lnk.Description -eq 'Claude Multi Launcher' -and (Split-Path -Leaf $lnk.TargetPath) -eq 'claude-multi-launcher.exe'
if ((Test-Path -LiteralPath $lnkPath) -and $lnk.Arguments -notlike '*claude-multi-server.ps1*' -and $lnk.TargetPath -ne $server -and -not $ownedNative) {
    throw ('Refusing to replace an unrelated shortcut: ' + $lnkPath)
}
$lnk.TargetPath = $server
$lnk.Arguments = ''
$lnk.WorkingDirectory = $root
$lnk.WindowStyle = 1
$lnk.IconLocation = ($iconPath + ',0')
$lnk.Description = 'Claude Multi Launcher'
$lnk.Save()

Write-Host ('Created: ' + $lnkPath)
