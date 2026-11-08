param([switch]$NoPause)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
function Assert-Feature {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ('FAIL ' + $Message) }
    $script:Passed++
    Write-Output ('PASS ' + $Message)
}
function Assert-Rejected {
    param([scriptblock]$Block,[string]$Message)
    $rejected = $false
    try { & $Block | Out-Null } catch { $rejected = $true }
    Assert-Feature $rejected $Message
}
$repo = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('cml-features-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($key in @('APPDATA','LOCALAPPDATA','USERPROFILE','CML_HOME')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key) }
try {
    $env:APPDATA = Join-Path $sandbox 'Roaming'; $env:LOCALAPPDATA = Join-Path $sandbox 'Local'
    $env:USERPROFILE = Join-Path $sandbox 'User'; $env:CML_HOME = Join-Path $sandbox 'Home'
    foreach ($dir in @($env:APPDATA,$env:LOCALAPPDATA,$env:USERPROFILE)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Import-Module (Join-Path $repo 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
    Set-CmlLanguage 'en' | Out-Null
    Set-CmlProfileOrder -Names @()
    Assert-Feature (@((Read-CmlConfig)['profiles']).Count -eq 0) 'empty list can be saved'
    foreach ($name in @('Alpha','Beta','Gamma')) { Add-CmlProfile -Name $name -NoShortcut | Out-Null }
    $before = Read-CmlConfig
    $records = @{}
    foreach ($profile in @($before['profiles'])) { $records[$profile['name']] = ConvertTo-Json -InputObject $profile -Depth 6 -Compress }
    Set-CmlProfileOrder -Names @('Gamma','alpha','Beta')
    $after = Read-CmlConfig
    Assert-Feature ((@($after['profiles'] | ForEach-Object { $_['name'] }) -join ',') -ceq 'Gamma,Alpha,Beta') 'order persists after re-read, preserving original name case'
    Assert-Feature ($after['language'] -eq $before['language'] -and $after['claudeExe'] -eq $before['claudeExe']) 'reorder preserves global settings'
    $unchanged = $true
    foreach ($profile in @($after['profiles'])) { if ((ConvertTo-Json -InputObject $profile -Depth 6 -Compress) -cne $records[$profile['name']]) { $unchanged = $false } }
    Assert-Feature $unchanged 'reorder changes no profile fields or paths'
    $configFile = Join-Path $env:CML_HOME 'profiles.json'
    $configText = [IO.File]::ReadAllText($configFile)
    Assert-Rejected { Set-CmlProfileOrder -Names @('Alpha','alpha','Gamma') } 'duplicate names are rejected case-insensitively'
    Assert-Rejected { Set-CmlProfileOrder -Names @('Gamma','Alpha') } 'stale list with missing profile is rejected'
    Assert-Rejected { Set-CmlProfileOrder -Names @('Gamma','Alpha','Unknown') } 'unknown replacement profile is rejected'
    Assert-Rejected { Set-CmlProfileOrder -Names @() } 'empty reorder cannot erase a populated list'
    Assert-Feature ([IO.File]::ReadAllText($configFile) -ceq $configText) 'rejected reorder leaves config byte-for-byte unchanged'
    # Exercise the real server dispatcher without starting HttpListener, a browser or Claude.
    $tokens = $null; $errors = $null
    $serverAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'claude-multi-server.ps1'),[ref]$tokens,[ref]$errors)
    foreach ($functionName in @('Get-Field','Invoke-Api')) {
        $definition = $serverAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$true)
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $response = Invoke-Api 'reorder' ([pscustomobject]@{names=@('Beta','Gamma','Alpha')})
    Assert-Feature ([bool]$response['ok']) 'real server dispatcher accepts reorder payload'
    Assert-Feature ((@((Read-CmlConfig)['profiles'] | ForEach-Object { $_['name'] }) -join ',') -eq 'Beta,Gamma,Alpha') 'server order is the saved config order'
    Assert-Rejected { Invoke-Api 'reorder' ([pscustomobject]@{names=@('Beta','Beta','Alpha')}) } 'server dispatcher rejects invalid reorder'

    # Read installed app icon only, never account files. Write .ico and .lnk only in sandbox.
    $iconPath = Get-CmlIconPath
    Assert-Feature ([bool]$iconPath -and (Test-Path -LiteralPath $iconPath)) 'installed Claude Desktop icon can be extracted locally'
    Add-Type -AssemblyName System.Drawing
    $installed = Resolve-CmlClaudeExe
    $expectedIcon = [Drawing.Icon]::ExtractAssociatedIcon($installed.Path)
    $memory = New-Object IO.MemoryStream
    try { $expectedIcon.Save($memory); $expectedBytes = [Convert]::ToBase64String($memory.ToArray()) } finally { $memory.Dispose(); $expectedIcon.Dispose() }
    Assert-Feature ([Convert]::ToBase64String([IO.File]::ReadAllBytes($iconPath)) -ceq $expectedBytes) 'icon bytes match the locally installed Claude executable'
    $desktop = Join-Path $sandbox 'Desktop fixtures'
    New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    & (Join-Path $repo 'tools\New-DesktopShortcut.ps1') -Root $repo -DesktopPath $desktop | Out-Null
    $ws = New-Object -ComObject WScript.Shell
    $linkPath = Join-Path $desktop 'Claude Multi Launcher.lnk'
    $link = $ws.CreateShortcut($linkPath)
    Assert-Feature ($link.IconLocation -eq ($iconPath + ',0')) 'launcher shortcut uses Claude Desktop icon, not PowerShell icon'
    Assert-Feature ($link.Arguments -like '*claude-multi-server.ps1*' -and $link.Arguments -like '*-WindowStyle Hidden*') 'launcher shortcut still opens the hidden launcher host'
    $link.IconLocation = ($link.TargetPath + ',0'); $link.Save()
    & (Join-Path $repo 'tools\New-DesktopShortcut.ps1') -Root $repo -DesktopPath $desktop | Out-Null
    Assert-Feature ($ws.CreateShortcut($linkPath).IconLocation -eq ($iconPath + ',0')) 'rebuilding an existing launcher shortcut replaces its old generic icon'
    $link = $ws.CreateShortcut($linkPath); $link.Arguments = '-NoProfile'; $link.Save()
    Assert-Rejected { & (Join-Path $repo 'tools\New-DesktopShortcut.ps1') -Root $repo -DesktopPath $desktop } 'unrelated same-name shortcut is protected'
    Assert-Feature ($ws.CreateShortcut($linkPath).Arguments -eq '-NoProfile') 'protected unrelated shortcut remains unchanged'
    Write-Output ('Passed: {0}   Failed: 0' -f $script:Passed)
} catch { Write-Output $_; Write-Output $_.ScriptStackTrace; exit 1 }
finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key]) }
    $sandboxFull = [IO.Path]::GetFullPath($sandbox)
    $tempFull = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($sandboxFull.StartsWith($tempFull,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $sandboxFull)) { Remove-Item -LiteralPath $sandboxFull -Recurse -Force }
}
