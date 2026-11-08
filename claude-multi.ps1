# claude-multi-launcher entry point (unofficial community tool, MIT license).
# Run:  powershell -ExecutionPolicy Bypass -File .\claude-multi.ps1 help
# The -ExecutionPolicy Bypass flag only applies to that one process; it does not change system settings.

param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1)][string]$Name,
    [Parameter(Position = 2)][string]$Arg2,
    [Parameter(Position = 3)][string]$Arg3,
    [string]$DataDir,
    [string]$ConfigDir,
    [string]$WorkspaceDir,
    [string]$TempDir,
    [string]$Root,
    [string]$Note = '',
    [switch]$NoShortcut,
    [switch]$ReuseDefault,
    [switch]$WhatIf,
    [switch]$FromShortcut
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Show-CmlFailure {
    param([string]$Message)
    if ($FromShortcut) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($Message, 'claude-multi-launcher')
        } catch { }
    }
    if ($env:NO_COLOR) { Write-Host $Message } else { Write-Host $Message -ForegroundColor Red }
}

try {
    Import-Module -Name (Join-Path $PSScriptRoot 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking

    function Require-Arg {
        param([string]$Value, [string]$Label)
        if ([string]::IsNullOrWhiteSpace($Value)) { throw (Get-CmlText 'err.arg_missing' @($Label)) }
    }

    switch ($Command.ToLowerInvariant()) {
        'list' {
            Show-CmlProfiles
        }
        'add' {
            Require-Arg $Name '<name>'
            Add-CmlProfile -Name $Name -DataDir $DataDir -ConfigDir $ConfigDir -WorkspaceDir $WorkspaceDir `
                -TempDir $TempDir -Root $Root -Note $Note -NoShortcut:$NoShortcut -ReuseDefault:$ReuseDefault -DryRun:$WhatIf
        }
        'launch' {
            Require-Arg $Name '<name>'
            Start-CmlProfile -Name $Name -ShowDialog:$FromShortcut
        }
        'open' {
            Require-Arg $Name '<name>'
            Open-CmlWorkspace -Name $Name
        }
        'paths' {
            Require-Arg $Name '<name>'
            Show-CmlPaths -Name $Name
        }
        'set-path' {
            Require-Arg $Name '<name>'
            Require-Arg $Arg2 '<type>'
            Set-CmlProfilePath -Name $Name -Type $Arg2 -Path $Arg3 -DryRun:$WhatIf
        }
        'rename' {
            Require-Arg $Name '<old>'
            Require-Arg $Arg2 '<new>'
            Rename-CmlProfile -Name $Name -NewName $Arg2
        }
        'remove' {
            Require-Arg $Name '<name>'
            Remove-CmlProfile -Name $Name -DryRun:$WhatIf
        }
        'scan' {
            $extra = @()
            if ($Name) { $extra += $Name }
            Show-CmlClones -ExtraFolders $extra
        }
        'import' {
            Require-Arg $Name '<name>'
            Require-Arg $DataDir '-DataDir'
            Import-CmlProfile -Name $Name -DataDir $DataDir -ConfigDir $ConfigDir -WorkspaceDir $WorkspaceDir `
                -TempDir $TempDir -NoShortcut:$NoShortcut
        }
        'shortcut' {
            Require-Arg $Name '<name>'
            Update-CmlShortcut -Name $Name
        }
        'lang' {
            Set-CmlLanguage -Value $Name
        }
        { $_ -in @('help', '-h', '--help', '/?') } {
            Write-CmlHelp
        }
        default {
            throw (Get-CmlText 'err.cmd_unknown' @($Command))
        }
    }
    exit 0
} catch {
    Show-CmlFailure $_.Exception.Message
    exit 1
}
