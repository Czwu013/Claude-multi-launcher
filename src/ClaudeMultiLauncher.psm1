# claude-multi-launcher core module (unofficial community tool, MIT license)
# Windows PowerShell 5.1 compatible. No registry writes, no network access, no admin rights.
# Record removal keeps data; explicit purge uses guarded preview and the Windows recycle bin.

Set-StrictMode -Version 2.0

$script:ModuleRoot = $PSScriptRoot
$script:RepoRoot   = Split-Path -Parent $PSScriptRoot
$script:Strings    = $null
$script:LangCode   = $null
$script:ItemKinds  = @('dataDir', 'configDir', 'workspaceDir', 'tempDir', 'outputsDir')

# ---------------------------------------------------------------- home / config location

function Get-CmlHome {
    if ($env:CML_HOME) { return $env:CML_HOME }
    return (Join-Path $env:APPDATA 'claude-multi-launcher')
}

function Get-CmlConfigPath {
    return (Join-Path (Get-CmlHome) 'profiles.json')
}

# ---------------------------------------------------------------- i18n

function Get-CmlLang {
    if ($script:LangCode) { return $script:LangCode }
    $setting = 'auto'
    try {
        $cfgPath = Get-CmlConfigPath
        if (Test-Path -LiteralPath $cfgPath) {
            $o = [IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($o.PSObject.Properties['language']) { $setting = [string]$o.language }
        }
    } catch {
        $setting = 'auto'
    }
    if ($setting -ne 'zh' -and $setting -ne 'en') {
        $name = ''
        try { $name = (Get-UICulture).Name } catch { $name = '' }
        if ($name -like 'zh*') { $setting = 'zh' } else { $setting = 'en' }
    }
    $script:LangCode = $setting
    return $setting
}

function Reset-CmlLanguageCache {
    $script:LangCode = $null
    $script:Strings = $null
}

function Initialize-CmlStrings {
    $lang = Get-CmlLang
    $file = Join-Path (Join-Path $script:ModuleRoot 'i18n') ($lang + '.psd1')
    $script:Strings = Import-PowerShellDataFile -LiteralPath $file
}

function Get-CmlText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$FormatArgs
    )
    if (-not $script:Strings) { Initialize-CmlStrings }
    if (-not $script:Strings.ContainsKey($Key)) { return ('[' + $Key + ']') }
    $fmt = [string]$script:Strings[$Key]
    if ($null -ne $FormatArgs -and $FormatArgs.Count -gt 0) {
        return [string]::Format($fmt, $FormatArgs)
    }
    return $fmt
}

function Get-CmlLines {
    param([Parameter(Mandatory = $true)][string]$Key)
    if (-not $script:Strings) { Initialize-CmlStrings }
    return @($script:Strings[$Key])
}

function Write-CmlLine {
    param(
        [string]$Text,
        [string]$Color
    )
    if ($Color -and -not $env:NO_COLOR) {
        Write-Host $Text -ForegroundColor $Color
    } else {
        Write-Host $Text
    }
}

function Get-CmlItemLabel {
    param([string]$Kind)
    switch ($Kind) {
        'dataDir'      { return (Get-CmlText 'item.data') }
        'configDir'    { return (Get-CmlText 'item.config') }
        'workspaceDir' { return (Get-CmlText 'item.workspace') }
        'tempDir'      { return (Get-CmlText 'item.temp') }
        'outputsDir'   { return (Get-CmlText 'item.outputs') }
        default        { return $Kind }
    }
}

function Write-CmlHelp {
    foreach ($line in (Get-CmlLines 'help.lines')) { Write-Host $line }
}

# ---------------------------------------------------------------- path helpers

function Resolve-CmlPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    $p = $Path.Trim().Trim('"')
    if ($p -eq '~' -or $p.StartsWith('~\') -or $p.StartsWith('~/')) {
        $p = $env:USERPROFILE + $p.Substring(1)
    }
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if ($p.IndexOf('%') -ge 0) { throw (Get-CmlText 'err.path_unresolved' @($Path)) }
    if ($p.StartsWith('\\')) { throw (Get-CmlText 'err.path_unc' @($Path)) }
    if (-not [IO.Path]::IsPathRooted($p) -or $p.Length -lt 3 -or $p[1] -ne ':' -or ($p[2] -ne '\' -and $p[2] -ne '/')) {
        throw (Get-CmlText 'err.path_not_absolute' @($Path))
    }
    try {
        $full = [IO.Path]::GetFullPath($p)
    } catch {
        throw (Get-CmlText 'err.path_invalid' @($Path))
    }
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd('\', '/')
    }
    if ($full.Length -le $root.Length) { throw (Get-CmlText 'err.path_root' @($Path)) }
    return $full
}

function Get-CmlPathRelation {
    # Returns: equal | inside (A is inside B) | contains (A contains B) | none
    param([string]$A, [string]$B)
    $ka = $A.ToLowerInvariant()
    $kb = $B.ToLowerInvariant()
    if ($ka -eq $kb) { return 'equal' }
    if ($ka.StartsWith($kb + '\')) { return 'inside' }
    if ($kb.StartsWith($ka + '\')) { return 'contains' }
    return 'none'
}

function Test-CmlName {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return $false }
    if ($Name -notmatch '^[\p{L}\p{N}_-]{1,32}$') { return $false }
    if ($Name -match '^(con|prn|aux|nul|com[1-9]|lpt[1-9])$') { return $false }
    return $true
}

function Get-CmlDefaultAppDataDir {
    # The default (non-profile) Claude app data folder. Prefer the one that exists.
    $roaming = Join-Path $env:APPDATA 'Claude'
    $local = Join-Path $env:LOCALAPPDATA 'Claude'
    if (Test-Path -LiteralPath $roaming) { return $roaming }
    if (Test-Path -LiteralPath $local) { return $local }
    return $roaming
}

function Get-CmlDefaultPaths {
    param([string]$Name, [string]$Root)
    $d = [ordered]@{}
    $d['dataDir'] = Join-Path $env:APPDATA $Name
    if ($Root) {
        $base = Join-Path (Resolve-CmlPath $Root) $Name
        $d['configDir'] = Join-Path $base 'config'
        $d['workspaceDir'] = Join-Path $base 'workspace'
        $d['tempDir'] = Join-Path $base 'tmp'
    } else {
        $d['configDir'] = Join-Path $env:USERPROFILE ('.claude-' + $Name.ToLowerInvariant())
        $d['workspaceDir'] = Join-Path (Join-Path $env:USERPROFILE 'Workspaces') $Name
        $d['tempDir'] = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'claude-multi-launcher') 'tmp') $Name
    }
    $d['outputsDir'] = ''
    return $d
}

function Get-CmlSharedLocations {
    # Places that several profiles (or the default app) would silently share.
    $up = $env:USERPROFILE
    $documents = [Environment]::GetFolderPath('MyDocuments','DoNotVerify')
    if (-not $documents) { $documents = Join-Path $up 'Documents' }
    $list = @(
        (Join-Path $up '.claude'),
        (Join-Path $up 'Claude'),
        (Join-Path (Join-Path $up 'Documents') 'Claude'),
        (Join-Path $documents 'Claude'),
        (Join-Path $env:APPDATA 'Claude'),
        (Join-Path $env:LOCALAPPDATA 'Claude'),
        (Join-Path $env:APPDATA 'Claude-3p'),
        (Join-Path $env:LOCALAPPDATA 'Claude-3p'),
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude'),
        (Get-CmlHome)
    )
    $out = @()
    foreach ($s in $list) {
        try {
            $r = Resolve-CmlPath $s
            if ($r -and ($out -notcontains $r)) { $out += $r }
        } catch { }
    }
    return $out
}

function Get-CmlReparseHit {
    # Returns the first path (the location itself or an ancestor below the user profile)
    # that is a symbolic link or junction; otherwise $null.
    param([string]$Path)
    $stop = ''
    try { $stop = (Resolve-CmlPath $env:USERPROFILE).ToLowerInvariant() } catch { $stop = '' }
    $cur = $Path
    while ($cur) {
        if ($stop -and $cur.ToLowerInvariant() -eq $stop) { break }
        $root = [IO.Path]::GetPathRoot($cur)
        if ($cur.Length -le $root.Length) { break }
        if (Test-Path -LiteralPath $cur) {
            $item = Get-Item -LiteralPath $cur -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $cur }
        }
        $cur = [IO.Path]::GetDirectoryName($cur)
    }
    return $null
}

# ---------------------------------------------------------------- config read / write

function New-CmlConfig {
    return [ordered]@{ version = 1; language = 'auto'; claudeExe = ''; profiles = @() }
}

function Complete-CmlProfile {
    param([System.Collections.IDictionary]$Raw)
    $p = [ordered]@{}
    foreach ($k in @('name', 'dataDir', 'configDir', 'workspaceDir', 'tempDir', 'outputsDir', 'note')) {
        if ($Raw.Contains($k) -and $null -ne $Raw[$k]) { $p[$k] = [string]$Raw[$k] } else { $p[$k] = '' }
    }
    if ($Raw.Contains('shortcut') -and $null -ne $Raw['shortcut']) { $p['shortcut'] = [bool]$Raw['shortcut'] } else { $p['shortcut'] = $true }
    if ($Raw.Contains('reuseDefault') -and $null -ne $Raw['reuseDefault']) { $p['reuseDefault'] = [bool]$Raw['reuseDefault'] } else { $p['reuseDefault'] = $false }
    # only records whether this tool has started the profile; it never knows whether you are signed in
    if ($Raw.Contains('launched') -and $null -ne $Raw['launched']) { $p['launched'] = [bool]$Raw['launched'] } else { $p['launched'] = $false }
    return $p
}

function Read-CmlConfig {
    $path = Get-CmlConfigPath
    $cfg = New-CmlConfig
    if (-not (Test-Path -LiteralPath $path)) { return $cfg }
    try {
        $obj = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } catch {
        throw (Get-CmlText 'err.config_corrupt' @($path))
    }
    if ($null -eq $obj) { throw (Get-CmlText 'err.config_corrupt' @($path)) }
    if ($obj.PSObject.Properties['language'] -and $obj.language) { $cfg['language'] = [string]$obj.language }
    if ($obj.PSObject.Properties['claudeExe'] -and $obj.claudeExe) { $cfg['claudeExe'] = [string]$obj.claudeExe }
    $list = @()
    if ($obj.PSObject.Properties['profiles'] -and $null -ne $obj.profiles) {
        foreach ($po in @($obj.profiles)) {
            $h = [ordered]@{}
            foreach ($prop in $po.PSObject.Properties) { $h[$prop.Name] = $prop.Value }
            $list += , (Complete-CmlProfile $h)
        }
    }
    $cfg['profiles'] = $list
    return $cfg
}

function Write-CmlConfig {
    param([System.Collections.IDictionary]$Cfg)
    $path = Get-CmlConfigPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $out = [ordered]@{
        version   = 1
        language  = [string]$Cfg['language']
        claudeExe = [string]$Cfg['claudeExe']
        profiles  = @($Cfg['profiles'])
    }
    $json = ConvertTo-Json -InputObject $out -Depth 6
    $tmp = $path + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $path -Force
}

function Set-CmlProfileOrder {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Names)
    $cfg = Read-CmlConfig
    $profiles = @($cfg['profiles'])
    if ($Names.Count -ne $profiles.Count) { throw (Get-CmlText 'err.order_changed') }
    $byName = @{}
    foreach ($profile in $profiles) { $byName[[string]$profile['name']] = $profile }
    $seen = @{}
    $orderedProfiles = @()
    foreach ($name in $Names) {
        if (-not $name -or $seen.ContainsKey($name) -or -not $byName.ContainsKey($name)) {
            throw (Get-CmlText 'err.order_changed')
        }
        $seen[$name] = $true
        $orderedProfiles += , $byName[$name]
    }
    # Save only the sequence; preserve names, directories and all other profile fields.
    $cfg['profiles'] = $orderedProfiles
    Write-CmlConfig $cfg
}

function Find-CmlProfile {
    param([System.Collections.IDictionary]$Cfg, [string]$Name)
    foreach ($p in @($Cfg['profiles'])) {
        if ($p['name'] -ieq $Name) { return $p }
    }
    return $null
}

function Get-CmlProfileOrThrow {
    param([System.Collections.IDictionary]$Cfg, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { throw (Get-CmlText 'err.arg_missing' @('<name>')) }
    $p = Find-CmlProfile $Cfg $Name
    if ($null -eq $p) { throw (Get-CmlText 'err.not_found' @($Name)) }
    return $p
}

function Set-CmlProfileRecord {
    param([System.Collections.IDictionary]$Cfg, [System.Collections.IDictionary]$Prof, [string]$OldName)
    $list = @()
    foreach ($p in @($Cfg['profiles'])) {
        if ($p['name'] -ieq $OldName) { $list += , $Prof } else { $list += , $p }
    }
    $Cfg['profiles'] = $list
}

# ---------------------------------------------------------------- isolation check

function Test-CmlIsolation {
    # Returns zero or more violation objects (Code, Message). Empty result = isolated.
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Prof,
        [object[]]$Others
    )
    $violations = New-Object System.Collections.Generic.List[object]

    function Add-Violation {
        param([string]$Code, [string]$Message)
        $violations.Add([pscustomobject]@{ Code = $Code; Message = $Message })
    }

    $own = @()
    foreach ($k in $script:ItemKinds) {
        if ($Prof[$k]) {
            $own += [pscustomobject]@{ Kind = $k; Path = (Resolve-CmlPath ([string]$Prof[$k])) }
        }
    }

    # Rule 1: within the same profile, no duplicates and no nesting
    for ($i = 0; $i -lt $own.Count; $i++) {
        for ($j = $i + 1; $j -lt $own.Count; $j++) {
            $rel = Get-CmlPathRelation $own[$i].Path $own[$j].Path
            $l1 = Get-CmlItemLabel $own[$i].Kind
            $l2 = Get-CmlItemLabel $own[$j].Kind
            if ($rel -eq 'equal') {
                Add-Violation 'iso.dup_within' (Get-CmlText 'iso.dup_within' @($l1, $l2, $own[$i].Path))
            } elseif ($rel -ne 'none') {
                Add-Violation 'iso.nested_within' (Get-CmlText 'iso.nested_within' @($l1, $l2, $own[$i].Path, $own[$j].Path))
            }
        }
    }

    # Rule 2 (and 5): across profiles, no duplicates and no nesting
    foreach ($other in @($Others)) {
        if ($null -eq $other) { continue }
        if ($other['name'] -ieq $Prof['name']) { continue }
        foreach ($k2 in $script:ItemKinds) {
            if (-not $other[$k2]) { continue }
            $op = ''
            try { $op = Resolve-CmlPath ([string]$other[$k2]) } catch { continue }
            foreach ($mine in $own) {
                $rel = Get-CmlPathRelation $mine.Path $op
                if ($rel -ne 'none') {
                    Add-Violation 'iso.cross' (Get-CmlText 'iso.cross' @($other['name'], (Get-CmlItemLabel $k2), $mine.Path, $op))
                }
            }
        }
    }

    # Rule 3: not equal to / inside / containing a shared location
    $reuse = $false
    if ($Prof.Contains('reuseDefault')) { $reuse = [bool]$Prof['reuseDefault'] }
    $defaultApp = ''
    try { $defaultApp = (Resolve-CmlPath (Get-CmlDefaultAppDataDir)).ToLowerInvariant() } catch { $defaultApp = '' }
    foreach ($shared in (Get-CmlSharedLocations)) {
        foreach ($mine in $own) {
            $rel = Get-CmlPathRelation $mine.Path $shared
            if ($rel -eq 'none') { continue }
            if ($reuse -and $mine.Kind -eq 'dataDir' -and $rel -eq 'equal' -and $mine.Path.ToLowerInvariant() -eq $defaultApp) { continue }
            Add-Violation 'iso.shared' (Get-CmlText 'iso.shared' @((Get-CmlItemLabel $mine.Kind), $mine.Path, $shared))
        }
    }

    # Rule 4: no symbolic links or junctions
    foreach ($mine in $own) {
        $hit = Get-CmlReparseHit $mine.Path
        if ($hit) {
            Add-Violation 'iso.reparse' (Get-CmlText 'iso.reparse' @((Get-CmlItemLabel $mine.Kind), $hit))
        }
    }

    return $violations.ToArray()
}

function New-CmlIsolationError {
    param([object[]]$Violations)
    $lines = @((Get-CmlText 'err.iso_failed'))
    foreach ($v in $Violations) { $lines += ('  - ' + $v.Message) }
    return ($lines -join [Environment]::NewLine)
}

function Test-CmlDataDirLocation {
    param([string]$DataDir)
    $a = Get-CmlPathRelation $DataDir (Resolve-CmlPath $env:APPDATA)
    $b = Get-CmlPathRelation $DataDir (Resolve-CmlPath $env:LOCALAPPDATA)
    return ($a -eq 'inside' -or $b -eq 'inside')
}

# ---------------------------------------------------------------- shortcut

function Get-CmlShortcutPath {
    param([string]$Name)
    $desktop = [Environment]::GetFolderPath('Desktop', 'DoNotVerify')
    if (-not $desktop) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
    return (Join-Path $desktop ('Claude (' + $Name + ').lnk'))
}

function Test-CmlOurShortcut {
    param([string]$LnkPath)
    if (-not (Test-Path -LiteralPath $LnkPath)) { return $false }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($LnkPath)
        return ($sc.Arguments -like '*claude-multi.ps1*')
    } catch {
        return $false
    }
}

function Get-CmlIconPath {
    param([switch]$Refresh)
    # Reads the icon from the locally installed app; it is never shipped with this tool.
    $iconDir = Join-Path (Get-CmlHome) 'icons'
    $ico = Join-Path $iconDir 'claude.ico'
    if (-not $Refresh -and (Test-Path -LiteralPath $ico)) { return $ico }
    try {
        $exe = Resolve-CmlClaudeExe
        Add-Type -AssemblyName System.Drawing
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($exe.Path)
        if (-not (Test-Path -LiteralPath $iconDir)) { New-Item -ItemType Directory -Path $iconDir -Force | Out-Null }
        $tempIcon = $ico + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
        $fs = [IO.File]::Create($tempIcon)
        try { $icon.Save($fs) } finally { $fs.Dispose(); $icon.Dispose() }
        try {
            if (Test-Path -LiteralPath $ico) { [IO.File]::Replace($tempIcon,$ico,[NullString]::Value) }
            else { [IO.File]::Move($tempIcon,$ico) }
        } finally { if (Test-Path -LiteralPath $tempIcon) { Remove-Item -LiteralPath $tempIcon -Force } }
        return $ico
    } catch {
        Write-CmlLine (Get-CmlText 'warn.icon_failed') 'Yellow'
        return $null
    }
}

function New-CmlShortcut {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Prof)
    $lnk = Get-CmlShortcutPath $Prof['name']
    if ((Test-Path -LiteralPath $lnk) -and -not (Test-CmlOurShortcut $lnk)) {
        Write-CmlLine (Get-CmlText 'warn.shortcut_exists' @($lnk)) 'Yellow'
        return $false
    }
    try {
        $entry = Join-Path $script:RepoRoot 'claude-multi.ps1'
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath = $psExe
        $sc.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" launch "{1}" -FromShortcut' -f $entry, $Prof['name'])
        $sc.WorkingDirectory = $script:RepoRoot
        $sc.Description = ('Claude ({0}) - claude-multi-launcher (unofficial)' -f $Prof['name'])
        $ico = Get-CmlIconPath -Refresh
        if ($ico) { $sc.IconLocation = ($ico + ',0') } else { $sc.IconLocation = ($psExe + ',0') }
        $sc.Save()
        Write-CmlLine (Get-CmlText 'msg.shortcut_done' @($lnk)) 'Green'
        return $true
    } catch {
        Write-CmlLine (Get-CmlText 'warn.shortcut_failed' @($_.Exception.Message)) 'Yellow'
        return $false
    }
}

function Remove-CmlOurShortcut {
    # Deletes only a shortcut this tool created. Never touches data folders.
    param([string]$Name)
    $lnk = Get-CmlShortcutPath $Name
    if (Test-CmlOurShortcut $lnk) {
        Remove-Item -LiteralPath $lnk -Force
        return $true
    }
    return $false
}

function Update-CmlShortcut {
    param([string]$Name)
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    if (-not (New-CmlShortcut $prof)) { throw (Get-CmlText 'runtime.shortcut_failed') }
}

# ---------------------------------------------------------------- profile operations

function Initialize-CmlDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { return 'existed' }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    return 'created'
}

function Write-CmlProfileItems {
    param([System.Collections.IDictionary]$Prof, [hashtable]$States)
    foreach ($k in $script:ItemKinds) {
        $label = Get-CmlItemLabel $k
        if ($Prof[$k]) {
            $st = ''
            if ($States -and $States.ContainsKey($k)) { $st = '  [' + $States[$k] + ']' }
            Write-Host ('  {0}: {1}{2}' -f $label, $Prof[$k], $st)
        } elseif ($k -eq 'outputsDir') {
            Write-Host ('  {0}: {1}' -f $label, (Get-CmlText 'state.unmanaged'))
        }
    }
}

function Add-CmlProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$DataDir,
        [string]$ConfigDir,
        [string]$WorkspaceDir,
        [string]$TempDir,
        [string]$Root,
        [string]$Note = '',
        [switch]$NoShortcut,
        [switch]$ReuseDefault,
        [switch]$DryRun,
        [scriptblock]$OnProgress
    )
    Write-CmlProgress $OnProgress 'validate' 1 4
    if (-not (Test-CmlName $Name)) { throw (Get-CmlText 'err.name_invalid' @($Name)) }
    if ($ReuseDefault -and $DataDir) { throw (Get-CmlText 'err.reuse_conflict') }
    $cfg = Read-CmlConfig
    if ($null -ne (Find-CmlProfile $cfg $Name)) { throw (Get-CmlText 'err.name_exists' @($Name)) }

    $def = Get-CmlDefaultPaths -Name $Name -Root $Root
    $prof = [ordered]@{
        name         = $Name
        dataDir      = (Resolve-CmlPath $def['dataDir'])
        configDir    = (Resolve-CmlPath $def['configDir'])
        workspaceDir = (Resolve-CmlPath $def['workspaceDir'])
        tempDir      = (Resolve-CmlPath $def['tempDir'])
        outputsDir   = ''
        shortcut     = (-not $NoShortcut)
        note         = $Note
        reuseDefault = [bool]$ReuseDefault
        launched     = $false
    }
    if ($ReuseDefault) { $prof['dataDir'] = (Resolve-CmlPath (Get-CmlDefaultAppDataDir)) }
    if ($DataDir) { $prof['dataDir'] = (Resolve-CmlPath $DataDir) }
    if ($ConfigDir) { $prof['configDir'] = (Resolve-CmlPath $ConfigDir) }
    if ($WorkspaceDir) { $prof['workspaceDir'] = (Resolve-CmlPath $WorkspaceDir) }
    if ($TempDir) { $prof['tempDir'] = (Resolve-CmlPath $TempDir) }

    $viol = @(Test-CmlIsolation -Prof $prof -Others @($cfg['profiles']))
    if ($viol.Count -gt 0) { throw (New-CmlIsolationError $viol) }

    Write-CmlProgress $OnProgress 'directories' 2 4
    $states = @{}
    if ($DryRun) {
        Write-CmlLine (Get-CmlText 'msg.dryrun_banner') 'Yellow'
        foreach ($k in @('dataDir', 'configDir', 'workspaceDir', 'tempDir')) {
            if (Test-Path -LiteralPath $prof[$k]) {
                if ($k -eq 'workspaceDir') { $states[$k] = (Get-CmlText 'state.reused') } else { $states[$k] = (Get-CmlText 'state.exists') }
            } else {
                $states[$k] = (Get-CmlText 'state.will_create')
            }
        }
    } else {
        foreach ($k in @('dataDir', 'configDir', 'workspaceDir', 'tempDir')) {
            $r = Initialize-CmlDirectory $prof[$k]
            if ($r -eq 'created') {
                $states[$k] = (Get-CmlText 'state.created')
            } elseif ($k -eq 'workspaceDir') {
                $states[$k] = (Get-CmlText 'state.reused')
            } else {
                $states[$k] = (Get-CmlText 'state.exists')
            }
        }
        Write-CmlProgress $OnProgress 'save' 3 4
        $list = @($cfg['profiles'])
        $list += , $prof
        $cfg['profiles'] = $list
        Write-CmlConfig $cfg
    }

    Write-CmlLine (Get-CmlText 'msg.add_done' @($Name)) 'Green'
    Write-CmlProfileItems $prof $states
    Write-CmlProgress $OnProgress 'shortcuts' 4 4
    if ($prof['shortcut']) {
        if ($DryRun) {
            Write-Host ('  {0}: {1}' -f (Get-CmlText 'item.shortcut'), (Get-CmlShortcutPath $Name))
        } else {
            if (-not (New-CmlShortcut $prof)) { throw (Get-CmlText 'runtime.create_partial') }
        }
    }
    if ($ReuseDefault) { Write-CmlLine (Get-CmlText 'msg.reuse_note') 'Cyan' }
    if (-not (Test-CmlDataDirLocation $prof['dataDir'])) {
        Write-CmlLine (Get-CmlText 'warn.datadir_location') 'Yellow'
    }
    if (-not $DryRun) {
        Write-Host ''
        Write-Host (Get-CmlText 'msg.add_next' @($Name))
        Write-Host (Get-CmlText 'msg.login_note')
        Write-Host (Get-CmlText 'msg.shared_note')
    }
}

function Show-CmlProfiles {
    $cfg = Read-CmlConfig
    $profiles = @($cfg['profiles'])
    if ($profiles.Count -eq 0) {
        Write-Host (Get-CmlText 'msg.list_empty')
        return
    }
    foreach ($p in $profiles) {
        Write-CmlLine ('● ' + $p['name']) 'Cyan'
        Write-Host ('    {0}: {1}' -f (Get-CmlItemLabel 'dataDir'), $p['dataDir'])
        Write-Host ('    {0}: {1}' -f (Get-CmlItemLabel 'configDir'), $p['configDir'])
        Write-Host ('    {0}: {1}' -f (Get-CmlItemLabel 'workspaceDir'), $p['workspaceDir'])
        $has = Test-CmlOurShortcut (Get-CmlShortcutPath $p['name'])
        if ($has) { $s = (Get-CmlText 'msg.shortcut_yes') } else { $s = (Get-CmlText 'msg.shortcut_no') }
        Write-Host ('    {0}: {1}' -f (Get-CmlText 'item.shortcut'), $s)
        if ($p['note']) { Write-Host (Get-CmlText 'msg.list_note' @($p['note'])) }
    }
}

function Show-CmlPaths {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    Write-CmlLine (Get-CmlText 'msg.paths_header' @($prof['name'])) 'Cyan'
    foreach ($k in $script:ItemKinds) {
        $label = Get-CmlItemLabel $k
        if ($prof[$k]) {
            if (Test-Path -LiteralPath $prof[$k]) { $st = (Get-CmlText 'state.exists') } else { $st = (Get-CmlText 'state.missing') }
            Write-Host ('  {0}: {1}  [{2}]' -f $label, $prof[$k], $st)
        } elseif ($k -eq 'outputsDir') {
            Write-Host ('  {0}: {1}' -f $label, (Get-CmlText 'state.unmanaged'))
        }
    }
    $has = Test-CmlOurShortcut (Get-CmlShortcutPath $prof['name'])
    if ($has) { $s = (Get-CmlText 'msg.shortcut_yes') } else { $s = (Get-CmlText 'msg.shortcut_no') }
    Write-Host ('  {0}: {1}' -f (Get-CmlText 'item.shortcut'), $s)
    $viol = @(Test-CmlIsolation -Prof $prof -Others @($cfg['profiles']))
    if ($viol.Count -eq 0) {
        Write-CmlLine (Get-CmlText 'iso.ok') 'Green'
    } else {
        Write-CmlLine (Get-CmlText 'iso.bad') 'Red'
        foreach ($v in $viol) { Write-Host ('  - ' + $v.Message) }
    }
    Write-Host (Get-CmlText 'msg.shared_note')
}

function Get-CmlShortcutLabelMap {
    param([string[]]$Places)
    # Maps a data folder (lowercased) to the display name of a desktop / Start-menu shortcut
    # that launches it, for shortcuts NOT made by this tool. Read-only: it reads the shortcut
    # target and, for launcher scripts, the script text and its path arguments; never the data.
    $map = @{}
    if (-not $PSBoundParameters.ContainsKey('Places')) {
        $Places = @(
            [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
            [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms')
        )
    }
    $Places = @($Places | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    $ws = $null
    try { $ws = New-Object -ComObject WScript.Shell } catch { return $map }
    foreach ($place in $places) {
        $files = @(Get-ChildItem -LiteralPath $place -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq '.lnk' })
        foreach ($f in $files) {
            try {
                $sc = $ws.CreateShortcut($f.FullName)
                if ($sc.Arguments -like '*claude-multi.ps1*') { continue }         # made by this tool
                if ($sc.Arguments -like '*claude-multi-server.ps1*') { continue }   # made by this tool
                $dirs = @()
                $dirs += @(Get-CmlDataDirsFromText ([string]$sc.Arguments))
                $tp = [string]$sc.TargetPath
                if ((Split-Path -Leaf $tp).ToLowerInvariant() -in @('wscript.exe', 'cscript.exe', 'cmd.exe', 'powershell.exe', 'pwsh.exe')) {
                    $tok = @(Get-CmlQuotedTokens ([string]$sc.Arguments))
                    $si = -1
                    for ($i = 0; $i -lt $tok.Count; $i++) {
                        if ($tok[$i] -match '\.(vbs|bat|cmd|ps1)$' -and (Test-Path -LiteralPath $tok[$i])) { $si = $i; break }
                    }
                    if ($si -ge 0) {
                        $stext = ''
                        try { if ((Get-Item -LiteralPath $tok[$si]).Length -lt 204800) { $stext = [IO.File]::ReadAllText($tok[$si]) } } catch { }
                        if ($stext -match '(?i)claude') {
                            $dirs += @(Get-CmlDataDirsFromText $stext)
                            if ($tok.Count -gt ($si + 1)) { $dirs += $tok[$si + 1] }
                        }
                    }
                }
                if ($tp -match '\.(bat|cmd|ps1|vbs)$' -and (Test-Path -LiteralPath $tp)) {
                    try { if ((Get-Item -LiteralPath $tp).Length -lt 204800) { $dirs += @(Get-CmlDataDirsFromText ([IO.File]::ReadAllText($tp))) } } catch { }
                }
                foreach ($d in $dirs) {
                    if (-not $d) { continue }
                    $rp = ''
                    try { $rp = Resolve-CmlPath $d } catch { continue }
                    if (-not $rp) { continue }
                    $key = $rp.ToLowerInvariant()
                    if (-not $map.ContainsKey($key)) { $map[$key] = [string]$f.BaseName }
                }
            } catch { continue }
        }
    }
    return $map
}

function Get-CmlProfileSummary {
    # Plain data about every profile, for the graphical window (no console output).
    $cfg = Read-CmlConfig
    $runtime = Get-CmlRuntimeSnapshot -Config $cfg
    $labelMap = @{}
    try { $labelMap = Get-CmlShortcutLabelMap } catch { $labelMap = @{} }
    $out = @()
    foreach ($p in @($cfg['profiles'])) {
        $viol = @(Test-CmlIsolation -Prof $p -Others @($cfg['profiles']))
        $msgs = @()
        foreach ($v in $viol) { $msgs += [string]$v.Message }
        $label = ''
        $dd = [string]$p['dataDir']
        if ($dd) {
            $k = $dd.ToLowerInvariant()
            if ($labelMap.ContainsKey($k)) { $label = [string]$labelMap[$k] }
        }
        $out += , ([pscustomobject]@{
                Name          = [string]$p['name']
                DataDir       = [string]$p['dataDir']
                ConfigDir     = [string]$p['configDir']
                WorkspaceDir  = [string]$p['workspaceDir']
                TempDir       = [string]$p['tempDir']
                HasShortcut   = [bool](Test-CmlOurShortcut (Get-CmlShortcutPath $p['name']))
                Launched      = [bool]$p['launched']
                Note          = [string]$p['note']
                Violations    = $msgs
                ShortcutLabel = $label
                ProcessStatus = $runtime[$p['name']].Status
                ProcessIds    = @($runtime[$p['name']].Processes | ForEach-Object { $_.ProcessId })
            })
    }
    return $out
}

function Rename-CmlProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$NewName
    )
    if (-not (Test-CmlName $NewName)) { throw (Get-CmlText 'err.name_invalid' @($NewName)) }
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    $clash = Find-CmlProfile $cfg $NewName
    if ($null -ne $clash -and $clash['name'] -ine $prof['name']) { throw (Get-CmlText 'err.name_exists' @($NewName)) }
    $oldName = $prof['name']
    $new = [ordered]@{}
    foreach ($k in $prof.Keys) { $new[$k] = $prof[$k] }
    $new['name'] = $NewName
    Set-CmlProfileRecord $cfg $new $oldName
    Write-CmlConfig $cfg
    if ($new['shortcut']) {
        [void](Remove-CmlOurShortcut $oldName)
        [void](New-CmlShortcut $new)
    }
    Write-CmlLine (Get-CmlText 'msg.rename_done' @($oldName, $NewName)) 'Green'
}

function Remove-CmlProfile {
    # Removes only the config record and this tool's own desktop shortcut. Data folders are always kept.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$DryRun,
        [switch]$AssumeYes   # tests and the graphical window (which asks in its own dialog); the command line never passes it
    )
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    $lnk = Get-CmlShortcutPath $prof['name']
    $hasLnk = Test-CmlOurShortcut $lnk

    if ($DryRun) { Write-CmlLine (Get-CmlText 'msg.dryrun_banner') 'Yellow' }
    Write-Host (Get-CmlText 'msg.remove_preview')
    Write-Host (Get-CmlText 'msg.remove_record' @($prof['name']))
    if ($hasLnk) { Write-Host (Get-CmlText 'msg.remove_shortcut' @($lnk)) }
    Write-Host (Get-CmlText 'msg.remove_keep')
    foreach ($k in $script:ItemKinds) {
        if ($prof[$k]) { Write-Host ('  {0}: {1}' -f (Get-CmlItemLabel $k), $prof[$k]) }
    }
    if ($DryRun) { return }

    $ok = $AssumeYes.IsPresent
    if (-not $ok) {
        try {
            $answer = Read-Host (Get-CmlText 'msg.remove_confirm')
            $ok = ($answer.Trim() -ieq 'y')
        } catch {
            $ok = $false
        }
    }
    if (-not $ok) {
        Write-Host (Get-CmlText 'msg.remove_cancel')
        return
    }
    $list = @()
    foreach ($p in @($cfg['profiles'])) {
        if ($p['name'] -ine $prof['name']) { $list += , $p }
    }
    $cfg['profiles'] = $list
    Write-CmlConfig $cfg
    if ($hasLnk) { [void](Remove-CmlOurShortcut $prof['name']) }
    Write-CmlLine (Get-CmlText 'msg.remove_done' @($prof['name'])) 'Green'
}

function ConvertTo-CmlKind {
    param([string]$Type)
    $map = @{
        data = 'dataDir'; datadir = 'dataDir'
        config = 'configDir'; configdir = 'configDir'
        workspace = 'workspaceDir'; workspacedir = 'workspaceDir'
        temp = 'tempDir'; tempdir = 'tempDir'
        outputs = 'outputsDir'; outputsdir = 'outputsDir'
    }
    if ($Type -and $map.ContainsKey($Type)) { return $map[$Type] }
    throw (Get-CmlText 'err.type_invalid' @($Type))
}

function Set-CmlProfilePath {
    # Updates the config and creates an empty folder. Never moves, copies or deletes existing data.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Type,
        [string]$Path,
        [switch]$DryRun
    )
    $kind = ConvertTo-CmlKind $Type
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    $new = [ordered]@{}
    foreach ($k in $prof.Keys) { $new[$k] = $prof[$k] }
    $old = [string]$prof[$kind]
    if ([string]::IsNullOrWhiteSpace($Path)) {
        if ($kind -ne 'outputsDir') { throw (Get-CmlText 'err.arg_missing' @('<path>')) }
        $new[$kind] = ''
    } else {
        $new[$kind] = (Resolve-CmlPath $Path)
    }
    if ($kind -eq 'dataDir') { $new['reuseDefault'] = $false }

    $viol = @(Test-CmlIsolation -Prof $new -Others @($cfg['profiles']))
    if ($viol.Count -gt 0) { throw (New-CmlIsolationError $viol) }

    if ($DryRun) {
        Write-CmlLine (Get-CmlText 'msg.dryrun_banner') 'Yellow'
    } else {
        if ($new[$kind]) { [void](Initialize-CmlDirectory $new[$kind]) }
        Set-CmlProfileRecord $cfg $new $prof['name']
        Write-CmlConfig $cfg
    }
    Write-CmlLine (Get-CmlText 'msg.setpath_done' @($prof['name'], (Get-CmlItemLabel $kind), $new[$kind])) 'Green'
    if ($old -and $old -ine $new[$kind]) { Write-Host (Get-CmlText 'msg.setpath_nodata' @($old)) }
    if ($kind -eq 'outputsDir') { Write-CmlLine (Get-CmlText 'msg.setpath_outputs_exp') 'Yellow' }
    if ($kind -eq 'dataDir' -and $new[$kind] -and -not (Test-CmlDataDirLocation $new[$kind])) {
        Write-CmlLine (Get-CmlText 'warn.datadir_location') 'Yellow'
    }
}

function Open-CmlWorkspace {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    $dir = $prof['workspaceDir']
    if (-not (Test-Path -LiteralPath $dir)) {
        Write-CmlLine (Get-CmlText 'msg.open_missing' @($dir)) 'Yellow'
        return
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $dir)
}

function Set-CmlLanguage {
    param([string]$Value)
    $cfg = Read-CmlConfig
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Host (Get-CmlText 'lang.current' @((Get-CmlLang), $cfg['language']))
        return
    }
    if ($Value -notin @('auto', 'zh', 'en')) { throw (Get-CmlText 'err.lang_invalid') }
    $cfg['language'] = $Value.ToLowerInvariant()
    Write-CmlConfig $cfg
    Reset-CmlLanguageCache
    Write-Host (Get-CmlText 'lang.set' @($cfg['language']))
}

# ---------------------------------------------------------------- locate and launch Claude

function Resolve-CmlClaudeExe {
    # Order: explicit claudeExe in config > MSIX package named exactly "Claude" (publisher checked)
    # > classic per-user install (Authenticode signature checked). Never guesses.
    $cfg = Read-CmlConfig
    if ($cfg['claudeExe']) {
        $p = Resolve-CmlPath $cfg['claudeExe']
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw (Get-CmlText 'err.exe_config_missing' @($p)) }
        return @{ Path = $p; Source = 'config'; Version = '' }
    }

    $pkgs = @()
    try { $pkgs = @(Get-AppxPackage -Name 'Claude' -ErrorAction Stop) } catch { $pkgs = @() }
    if ($pkgs.Count -gt 0) {
        $sorted = @($pkgs | Sort-Object -Property @{ Expression = { [version]$_.Version } } -Descending)
        foreach ($pkg in $sorted) {
            if ([string]$pkg.Publisher -notmatch 'Anthropic') { continue }
            $exe = Join-Path $pkg.InstallLocation 'app\Claude.exe'
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw (Get-CmlText 'err.exe_not_in_pkg' @($exe)) }
            return @{ Path = $exe; Source = 'msix'; Version = [string]$pkg.Version }
        }
        throw (Get-CmlText 'err.publisher_mismatch' @([string]$sorted[0].Publisher))
    }

    $base = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    if (Test-Path -LiteralPath $base) {
        $dirs = @(Get-ChildItem -LiteralPath $base -Directory -Filter 'app-*' -ErrorAction SilentlyContinue)
        $versioned = @()
        foreach ($d in $dirs) {
            $v = $null
            if ([version]::TryParse($d.Name.Substring(4), [ref]$v)) {
                $versioned += [pscustomobject]@{ Dir = $d.FullName; Version = $v }
            }
        }
        foreach ($c in @($versioned | Sort-Object -Property Version -Descending)) {
            $exe = Join-Path $c.Dir 'claude.exe'
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
            $sig = Get-AuthenticodeSignature -LiteralPath $exe
            if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'Anthropic') {
                throw (Get-CmlText 'err.signature_bad' @($exe))
            }
            return @{ Path = $exe; Source = 'classic'; Version = [string]$c.Version }
        }
    }
    throw (Get-CmlText 'err.exe_not_found')
}

function Get-CmlRunningClaudeCount {
    # Counts running processes whose executable is exactly the installed Claude app.
    param([string]$ExePath)
    $n = 0
    try {
        foreach ($proc in @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue)) {
            $path = ''
            try { $path = [string]$proc.Path } catch { $path = '' }
            if ($path -and $path -ieq $ExePath) { $n++ }
        }
    } catch { }
    return $n
}

# ---------------------------------------------------------------- find and adopt existing clones
# Read-only detection: it looks at shortcut targets, command lines of running Claude processes,
# small launcher scripts on the desktop, and folder/file NAMES. It never opens login data,
# cookies or tokens, and never changes anything it finds.

function Get-CmlDataDirsFromText {
    # Extracts every --user-data-dir value from a command line or a small script.
    param([string]$Text)
    $out = @()
    if ([string]::IsNullOrEmpty($Text)) { return $out }
    $t = [regex]::Replace($Text, '\$env:(\w+)', { param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value) })
    foreach ($m in [regex]::Matches($t, '--user-data-dir(?:=|\s+)(?:"([^"]+)"|(\S+))')) {
        if ($m.Groups[1].Success) { $out += $m.Groups[1].Value } else { $out += $m.Groups[2].Value.Trim("'", '"') }
    }
    return $out
}

function Get-CmlQuotedTokens {
    # Splits a shortcut's argument string into tokens, honouring double quotes.
    param([string]$Text)
    $out = @()
    if ([string]::IsNullOrEmpty($Text)) { return $out }
    foreach ($m in [regex]::Matches($Text, '"([^"]*)"|(\S+)')) {
        if ($m.Groups[1].Success) { $out += $m.Groups[1].Value } else { $out += $m.Groups[2].Value }
    }
    return $out
}

function Find-CmlExistingClones {
    param([string[]]$ExtraFolders = @())
    $found = @{}
    $shared = @(Get-CmlSharedLocations)

    function Add-Found {
        param([string]$RawPath, [string]$Source, [bool]$Running = $false, [string]$ConfigHint = '')
        $p = ''
        try { $p = Resolve-CmlPath $RawPath } catch { return }
        if (-not $p) { return }
        foreach ($s in $shared) { if ((Get-CmlPathRelation $p $s) -eq 'equal') { return } }
        $key = $p.ToLowerInvariant()
        if (-not $found.ContainsKey($key)) {
            $found[$key] = @{ DataDir = $p; Sources = (New-Object System.Collections.Generic.List[string]); Running = $false; ConfigHint = '' }
        }
        if ($ConfigHint -and -not $found[$key].ConfigHint) { $found[$key].ConfigHint = $ConfigHint }
        if (-not $found[$key].Sources.Contains($Source)) { $found[$key].Sources.Add($Source) }
        if ($Running) { $found[$key].Running = $true }
    }

    # 1) running Claude processes (main process only)
    try {
        foreach ($pr in @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'Claude.exe'" -ErrorAction Stop)) {
            $cl = [string]$pr.CommandLine
            if ($cl -match '--type=') { continue }
            foreach ($d in (Get-CmlDataDirsFromText $cl)) { Add-Found $d (Get-CmlText 'src.process') $true }
        }
    } catch { }

    # 2) shortcuts and small launcher scripts on the desktop and in the Start menu
    $places = @(
        [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $ws = $null
    try { $ws = New-Object -ComObject WScript.Shell } catch { $ws = $null }
    foreach ($place in $places) {
        $files = @(Get-ChildItem -LiteralPath $place -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.lnk', '.bat', '.cmd', '.ps1', '.vbs') })
        foreach ($f in $files) {
            $texts = @()
            $label = (Get-CmlText 'src.script')
            if ($f.Extension -eq '.lnk') {
                if ($null -eq $ws) { continue }
                try {
                    $sc = $ws.CreateShortcut($f.FullName)
                    if ($sc.Arguments -like '*claude-multi.ps1*') { continue }   # made by this tool
                    $label = (Get-CmlText 'src.shortcut') + ': ' + $f.BaseName
                    $texts += [string]$sc.Arguments
                    $tp = [string]$sc.TargetPath
                    # Shortcut that runs a launcher script (wscript/cmd/powershell + script + paths):
                    # when the script mentions Claude, the paths after it are the data folder and config folder.
                    if ((Split-Path -Leaf $tp).ToLowerInvariant() -in @('wscript.exe', 'cscript.exe', 'cmd.exe', 'powershell.exe', 'pwsh.exe')) {
                        $tok = @(Get-CmlQuotedTokens ([string]$sc.Arguments))
                        $si = -1
                        for ($i = 0; $i -lt $tok.Count; $i++) {
                            if ($tok[$i] -match '\.(vbs|bat|cmd|ps1)$' -and (Test-Path -LiteralPath $tok[$i])) { $si = $i; break }
                        }
                        if ($si -ge 0 -and $tok.Count -gt ($si + 1)) {
                            $stext = ''
                            try {
                                if ((Get-Item -LiteralPath $tok[$si]).Length -lt 204800) { $stext = [IO.File]::ReadAllText($tok[$si]) }
                            } catch { $stext = '' }
                            if ($stext -match '(?i)claude') {
                                $paths = @()
                                for ($j = $si + 1; $j -lt $tok.Count; $j++) {
                                    try { $paths += (Resolve-CmlPath $tok[$j]) } catch { }
                                }
                                if ($paths.Count -ge 1) {
                                    $hint = ''
                                    if ($paths.Count -ge 2) { $hint = $paths[1] }
                                    Add-Found $paths[0] ((Get-CmlText 'src.script') + ': ' + $f.BaseName) $false $hint
                                }
                            }
                        }
                    }
                    if ($tp -match '\.(bat|cmd|ps1|vbs)$' -and (Test-Path -LiteralPath $tp)) {
                        $ti = Get-Item -LiteralPath $tp
                        if ($ti.Length -lt 204800) { $texts += [IO.File]::ReadAllText($tp) }
                        $label = (Get-CmlText 'src.script')
                    }
                } catch { continue }
            } elseif ($f.Length -lt 204800) {
                try { $texts += [IO.File]::ReadAllText($f.FullName) } catch { continue }
            }
            foreach ($t in $texts) {
                foreach ($d in (Get-CmlDataDirsFromText $t)) { Add-Found $d $label }
            }
        }
    }

    # 3) folders that look like a Claude data folder (by the names of what is inside, never the contents)
    $markers = @('claude_desktop_config.json', 'local-agent-mode-sessions', 'claude-code-sessions', 'vm_bundles')
    $roots = @($env:APPDATA, $env:LOCALAPPDATA, $env:USERPROFILE) + @($ExtraFolders)
    $cands = @()
    foreach ($r in $roots) {
        if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
        $cands += @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    foreach ($x in @($ExtraFolders)) { if ($x -and (Test-Path -LiteralPath $x)) { $cands += $x } }
    foreach ($c in $cands) {
        foreach ($m in $markers) {
            if (Test-Path -LiteralPath (Join-Path $c $m)) { Add-Found $c (Get-CmlText 'src.folder'); break }
        }
    }

    $cfg = Read-CmlConfig
    $result = @()
    foreach ($k in ($found.Keys | Sort-Object)) {
        $e = $found[$k]
        $leaf = Split-Path -Leaf $e.DataDir
        $cfgGuess = Join-Path $env:USERPROFILE ('.claude-' + $leaf.ToLowerInvariant())
        if ($e.ConfigHint -and (Test-Path -LiteralPath $e.ConfigHint)) { $cfgGuess = $e.ConfigHint }
        if (-not (Test-Path -LiteralPath $cfgGuess)) { $cfgGuess = '' }
        $reg = $false
        foreach ($p in @($cfg['profiles'])) {
            if ($p['dataDir'] -and (Get-CmlPathRelation $p['dataDir'] $e.DataDir) -eq 'equal') { $reg = $true }
        }
        $result += , ([pscustomobject]@{
                Name       = $leaf
                DataDir    = $e.DataDir
                ConfigDir  = $cfgGuess
                Sources    = @($e.Sources)
                Running    = [bool]$e.Running
                Registered = $reg
                NameOk     = (Test-CmlName $leaf)
            })
    }
    return $result
}

function Show-CmlClones {
    param([string[]]$ExtraFolders = @())
    $list = @(Find-CmlExistingClones -ExtraFolders $ExtraFolders)
    if ($list.Count -eq 0) { Write-Host (Get-CmlText 'msg.scan_none'); return }
    Write-CmlLine (Get-CmlText 'msg.scan_header' @($list.Count)) 'Cyan'
    foreach ($c in $list) {
        $flags = @()
        if ($c.Running) { $flags += (Get-CmlText 'msg.scan_running') }
        if ($c.Registered) { $flags += (Get-CmlText 'msg.scan_registered') }
        Write-Host ('* {0}  [{1}]  {2}' -f $c.Name, ($c.Sources -join ', '), ($flags -join ' '))
        Write-Host ('    {0}: {1}' -f (Get-CmlText 'item.data'), $c.DataDir)
        if ($c.ConfigDir) { Write-Host ('    {0}: {1}' -f (Get-CmlText 'item.config'), $c.ConfigDir) }
    }
    Write-Host (Get-CmlText 'msg.scan_next')
}

function Import-CmlProfile {
    # Registers an existing data folder as a profile. Nothing is copied, moved or changed in it.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DataDir,
        [string]$ConfigDir,
        [string]$WorkspaceDir,
        [string]$TempDir,
        [switch]$NoShortcut
    )
    if (-not (Test-CmlName $Name)) { throw (Get-CmlText 'err.name_invalid' @($Name)) }
    $cfg = Read-CmlConfig
    if ($null -ne (Find-CmlProfile $cfg $Name)) { throw (Get-CmlText 'err.name_exists' @($Name)) }
    $data = Resolve-CmlPath $DataDir
    if (-not (Test-Path -LiteralPath $data -PathType Container)) { throw (Get-CmlText 'err.import_missing' @($data)) }

    $def = Get-CmlDefaultPaths -Name $Name
    $guess = Join-Path $env:USERPROFILE ('.claude-' + $Name.ToLowerInvariant())
    $prof = [ordered]@{
        name         = $Name
        dataDir      = $data
        configDir    = (Resolve-CmlPath $def['configDir'])
        workspaceDir = (Resolve-CmlPath $def['workspaceDir'])
        tempDir      = (Resolve-CmlPath $def['tempDir'])
        outputsDir   = ''
        shortcut     = (-not $NoShortcut)
        note         = (Get-CmlText 'msg.import_note')
        reuseDefault = $false
        launched     = $true
    }
    if ($ConfigDir) { $prof['configDir'] = (Resolve-CmlPath $ConfigDir) }
    elseif (Test-Path -LiteralPath $guess) { $prof['configDir'] = (Resolve-CmlPath $guess) }
    if ($WorkspaceDir) { $prof['workspaceDir'] = (Resolve-CmlPath $WorkspaceDir) }
    if ($TempDir) { $prof['tempDir'] = (Resolve-CmlPath $TempDir) }

    $viol = @(Test-CmlIsolation -Prof $prof -Others @($cfg['profiles']))
    if ($viol.Count -gt 0) { throw (New-CmlIsolationError $viol) }

    foreach ($k in @('configDir', 'workspaceDir', 'tempDir')) { [void](Initialize-CmlDirectory $prof[$k]) }
    $list = @($cfg['profiles'])
    $list += , $prof
    $cfg['profiles'] = $list
    Write-CmlConfig $cfg
    Write-CmlLine (Get-CmlText 'msg.import_done' @($Name)) 'Green'
    Write-CmlProfileItems $prof @{}
    if ($prof['shortcut']) { [void](New-CmlShortcut $prof) }
}

# ---------------------------------------------------------------- delete a profile together with its data
# Moves the profile's own folders to the Recycle Bin (never a permanent delete from this tool),
# only after a preview and an explicit confirmation by the caller. Refuses anything that is shared,
# overlaps another profile, passes through a link, or is too close to the top of the user's profile.

function Get-CmlDirSizeMB {
    param([string]$Path)
    $sum = 0
    try {
        foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $sum += $f.Length }
    } catch { }
    return [math]::Round($sum / 1MB, 1)
}

function Get-CmlRunningDataDirs {
    $out = @()
    try {
        foreach ($pr in @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'Claude.exe'" -ErrorAction Stop)) {
            $cl = [string]$pr.CommandLine
            if ($cl -match '--type=') { continue }
            foreach ($d in (Get-CmlDataDirsFromText $cl)) { try { $out += (Resolve-CmlPath $d) } catch { } }
        }
    } catch { throw (Get-CmlText 'runtime.query_failed') }
    return $out
}

function Get-CmlDeleteRefusal {
    # Returns '' when the folder may be moved to the Recycle Bin, otherwise a reason (already translated).
    param([string]$Path, [string]$Name, $Cfg)
    $p = Resolve-CmlPath $Path
    if (@($p.Split('\') | Where-Object { $_ }).Count -lt 3) { return (Get-CmlText 'purge.shallow') }
    foreach ($s in (Get-CmlSharedLocations)) {
        if ((Get-CmlPathRelation $p $s) -ne 'none') { return (Get-CmlText 'purge.shared') }
    }
    $tops = @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'))
    foreach ($u in $tops) {
        if (-not $u) { continue }
        $rel = Get-CmlPathRelation $p (Resolve-CmlPath $u)
        if ($rel -eq 'equal' -or $rel -eq 'contains') { return (Get-CmlText 'purge.shallow') }
    }
    foreach ($o in @($Cfg['profiles'])) {
        if ($o['name'] -ieq $Name) { continue }
        foreach ($k in $script:ItemKinds) {
            if (-not $o[$k]) { continue }
            $op = ''
            try { $op = Resolve-CmlPath ([string]$o[$k]) } catch { continue }
            if ((Get-CmlPathRelation $p $op) -ne 'none') { return (Get-CmlText 'purge.other') }
        }
    }
    if (Get-CmlReparseHit $p) { return (Get-CmlText 'purge.link') }
    return ''
}

function Get-CmlRemovalPlan {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    $running = $false
    $dataKey = ''
    try { $dataKey = (Resolve-CmlPath $prof['dataDir']).ToLowerInvariant() } catch { $dataKey = '' }
    foreach ($d in (Get-CmlRunningDataDirs)) { if ($d.ToLowerInvariant() -eq $dataKey) { $running = $true } }
    $items = @()
    foreach ($k in @('dataDir', 'configDir', 'tempDir', 'workspaceDir')) {
        if (-not $prof[$k]) { continue }
        $path = [string]$prof[$k]
        $exists = (Test-Path -LiteralPath $path -PathType Container)
        $reason = ''
        $size = 0
        try { $reason = Get-CmlDeleteRefusal $path $prof['name'] $cfg } catch { $reason = $_.Exception.Message }
        if ($exists) {
            $size = Get-CmlDirSizeMB $path
            if ($k -eq 'workspaceDir' -and -not $reason) {
                $any = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($any.Count -gt 0) { $reason = (Get-CmlText 'purge.has_files') }
            }
        }
        $items += , ([pscustomobject]@{
                Kind = $k; Label = (Get-CmlItemLabel $k); Path = $path; Exists = $exists; SizeMB = $size; Reason = $reason
            })
    }
    return [pscustomobject]@{
        Name        = [string]$prof['name']
        Running     = $running
        HasShortcut = [bool](Test-CmlOurShortcut (Get-CmlShortcutPath $prof['name']))
        Items       = $items
    }
}

function Remove-CmlProfileData {
    # The caller must have shown Get-CmlRemovalPlan and obtained the user's confirmation.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Kinds
    )
    $plan = Get-CmlRemovalPlan -Name $Name
    if ($plan.Running) { throw (Get-CmlText 'purge.running') }
    Add-Type -AssemblyName Microsoft.VisualBasic
    $moved = 0
    $failed = @()
    foreach ($it in $plan.Items) {
        if ($Kinds -notcontains $it.Kind) { continue }
        if (-not $it.Exists) { continue }
        if ($it.Reason) { $failed += ('{0}: {1}' -f $it.Label, $it.Reason); continue }
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, [Microsoft.VisualBasic.FileIO.UIOption]::AllDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $moved++
        } catch {
            $failed += ('{0}: {1}' -f $it.Label, $_.Exception.Message)
        }
    }
    if ($failed.Count -gt 0) { throw (Get-CmlText 'purge.failed' @(($failed -join '; '))) }
    Remove-CmlProfile -Name $Name -AssumeYes | Out-Null
    Write-CmlLine (Get-CmlText 'purge.done' @($moved, $plan.Name)) 'Green'
}

. (Join-Path $PSScriptRoot 'CmlProcesses.ps1')
. (Join-Path $PSScriptRoot 'CmlActions.ps1')

Export-ModuleMember -Function @(
    'Get-CmlText', 'Get-CmlLang', 'Reset-CmlLanguageCache', 'Write-CmlHelp', 'Write-CmlLine',
    'Resolve-CmlPath', 'Get-CmlPathRelation', 'Test-CmlName', 'Get-CmlDefaultPaths',
    'Read-CmlConfig', 'Write-CmlConfig', 'Test-CmlIsolation',
    'Add-CmlProfile', 'Show-CmlProfiles', 'Show-CmlPaths', 'Rename-CmlProfile', 'Remove-CmlProfile',
    'Set-CmlProfilePath', 'Open-CmlWorkspace', 'Set-CmlLanguage', 'Update-CmlShortcut',
    'Resolve-CmlClaudeExe', 'Start-CmlProfile', 'Get-CmlProfileSummary', 'Get-CmlItemLabel',
    'Get-CmlDataDirsFromText', 'Get-CmlQuotedTokens', 'Find-CmlExistingClones', 'Show-CmlClones', 'Import-CmlProfile',
    'Get-CmlRemovalPlan', 'Remove-CmlProfileData', 'Get-CmlShortcutLabelMap',
    'Set-CmlProfileOrder', 'Get-CmlIconPath', 'Get-CmlRuntimeSnapshot', 'Stop-CmlProfile',
    'Get-CmlMcpConfigInfo', 'Open-CmlMcpConfig', 'Get-CmlRepairPlan', 'Repair-CmlShortcuts'
)
