# Self-test for claude-multi-launcher. Run on Windows:
#   powershell -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
# It works in a throw-away sandbox (APPDATA, LOCALAPPDATA, USERPROFILE and CML_HOME are redirected
# for this process only), creates no desktop shortcuts, and starts no Claude process.

param([switch]$NoPause)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Log = New-Object System.Collections.Generic.List[string]
$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param($Condition, [string]$Message)
    if ($Condition) {
        $script:Pass++
        $script:Log.Add('PASS  ' + $Message)
        Write-Host ('PASS  ' + $Message) -ForegroundColor Green
    } else {
        $script:Fail++
        $script:Log.Add('FAIL  ' + $Message)
        Write-Host ('FAIL  ' + $Message) -ForegroundColor Red
    }
}

function Assert-Throws {
    param([scriptblock]$Block, [string]$Message)
    $threw = $false
    try { & $Block } catch { $threw = $true }
    Assert-True $threw $Message
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('cml-test-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($v in @('APPDATA', 'LOCALAPPDATA', 'USERPROFILE', 'CML_HOME')) { $saved[$v] = [Environment]::GetEnvironmentVariable($v) }

try {
    $user = Join-Path $sandbox 'User'
    $env:APPDATA = Join-Path $sandbox 'Roaming'
    $env:LOCALAPPDATA = Join-Path $sandbox 'Local'
    $env:USERPROFILE = $user
    $env:CML_HOME = Join-Path $sandbox 'home'
    foreach ($d in @($env:APPDATA, $env:LOCALAPPDATA, $user)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

    Import-Module (Join-Path $PSScriptRoot '..\src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
    Set-CmlLanguage -Value 'en' | Out-Null

    # --- i18n key parity
    $zh = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '..\src\i18n\zh.psd1')
    $en = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '..\src\i18n\en.psd1')
    $diff = Compare-Object @($zh.Keys) @($en.Keys)
    Assert-True ($null -eq $diff) 'zh and en have exactly the same keys'

    # --- real .lnk files in a temporary folder; no desktop writes or script execution
    $links = Join-Path $sandbox 'Shortcut fixtures'
    New-Item -ItemType Directory -Path $links -Force | Out-Null
    $ws = New-Object -ComObject WScript.Shell
    function New-TestLink {
        param([string]$Label, [string]$Target, [string]$Arguments)
        $lnk = $ws.CreateShortcut((Join-Path $links ($Label + '.lnk')))
        $lnk.TargetPath = $Target
        $lnk.Arguments = $Arguments
        $lnk.Save()
    }
    $personal = Join-Path $env:APPDATA 'Personal space'
    $workData = Join-Path $env:APPDATA 'Work label'
    $scriptData = Join-Path $env:APPDATA 'Script label'
    $ignoredData = Join-Path $env:APPDATA 'Ignored'
    $unrelatedData = Join-Path $env:APPDATA 'Unrelated'
    $hostScript = Join-Path $links 'launch.vbs'
    [IO.File]::WriteAllText($hostScript, "' Claude launcher fixture; never executed")
    New-TestLink 'Baron' (Join-Path $env:WINDIR 'System32\wscript.exe') ('"' + $hostScript + '" "' + $personal + '" "' + (Join-Path $user '.claude-personal') + '"')
    New-TestLink 'Clinton' (Join-Path $sandbox 'Claude.exe') ('--user-data-dir="' + $workData + '"')
    $directScript = Join-Path $links 'direct.cmd'
    [IO.File]::WriteAllText($directScript, ('Claude.exe --user-data-dir="' + $scriptData + '"'))
    New-TestLink 'Doss' $directScript ''
    New-TestLink 'Own CLI' (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') ('-File claude-multi.ps1 --user-data-dir="' + $ignoredData + '"')
    New-TestLink 'Own server' (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') ('-File claude-multi-server.ps1 --user-data-dir="' + $ignoredData + '"')
    $otherScript = Join-Path $links 'other.vbs'
    [IO.File]::WriteAllText($otherScript, "' unrelated launcher")
    New-TestLink 'Unrelated' (Join-Path $env:WINDIR 'System32\wscript.exe') ('"' + $otherScript + '" "' + $unrelatedData + '"')
    New-TestLink 'Bad path' (Join-Path $sandbox 'Claude.exe') '--user-data-dir=relative\folder'
    [IO.File]::WriteAllText((Join-Path $links 'Broken.lnk'), 'not a shortcut')
    $map = Get-CmlShortcutLabelMap -Places @($links)
    Assert-True ($map -is [hashtable]) 'labels: returns a hashtable under StrictMode 2.0'
    Assert-True ($map.Count -eq 3) 'labels: only three valid external shortcuts are mapped'
    Assert-True ($map[$personal.ToLowerInvariant()] -eq 'Baron') 'labels: wscript path argument maps Personal to Baron'
    Assert-True ($map[$workData.ToLowerInvariant()] -eq 'Clinton') 'labels: direct quoted data-dir argument maps to Clinton'
    Assert-True ($map[$scriptData.ToLowerInvariant()] -eq 'Doss') 'labels: direct launcher script maps to Doss'
    Assert-True (-not $map.ContainsKey($ignoredData.ToLowerInvariant())) 'labels: own CLI and server shortcuts are excluded'
    Assert-True (-not $map.ContainsKey($unrelatedData.ToLowerInvariant())) 'labels: unrelated script path argument is ignored'
    Assert-True (-not $map.ContainsKey((Join-Path $user '.claude-personal').ToLowerInvariant())) 'labels: config path is not mistaken for data path'
    Assert-True (@($map.Keys | Where-Object { $_ -cne $_.ToLowerInvariant() }).Count -eq 0) 'labels: keys are normalized to lowercase'
    Assert-True ((Get-CmlShortcutLabelMap -Places @()).Count -eq 0) 'labels: explicit empty search returns an empty map'
    Assert-True ((Get-CmlShortcutLabelMap -Places @((Join-Path $sandbox 'Missing'))).Count -eq 0) 'labels: missing search folder is harmless'

    # --- name validation
    Assert-True (Test-CmlName 'Study') 'name: Study ok'
    Assert-True (Test-CmlName '学习') 'name: CJK ok'
    Assert-True (-not (Test-CmlName 'a b')) 'name: space rejected'
    Assert-True (-not (Test-CmlName 'con')) 'name: reserved rejected'
    Assert-True (-not (Test-CmlName '')) 'name: empty rejected'
    Assert-True (-not (Test-CmlName ('x' * 33))) 'name: 33 chars rejected'

    # --- path normalisation and relations
    $a = Resolve-CmlPath 'D:\A\B\'
    $b = Resolve-CmlPath 'd:\a\b'
    Assert-True ((Get-CmlPathRelation $a $b) -eq 'equal') 'path: case and trailing slash are equal'
    Assert-True ((Get-CmlPathRelation (Resolve-CmlPath 'D:\A\B\C') $b) -eq 'inside') 'path: nested is inside'
    Assert-True ((Get-CmlPathRelation $b (Resolve-CmlPath 'D:\A\B\C')) -eq 'contains') 'path: parent contains child'
    Assert-True ((Get-CmlPathRelation (Resolve-CmlPath 'D:\A\BB') $b) -eq 'none') 'path: prefix without separator is not nested'
    Assert-True ((Resolve-CmlPath '%USERPROFILE%\x\') -eq (Join-Path $user 'x')) 'path: environment variables expand'
    Assert-Throws { Resolve-CmlPath 'relative\path' } 'path: relative rejected'
    Assert-Throws { Resolve-CmlPath 'C:foo' } 'path: drive-relative rejected'
    Assert-Throws { Resolve-CmlPath '\\server\share\x' } 'path: UNC rejected'
    Assert-Throws { Resolve-CmlPath '%NO_SUCH_VAR_XYZ%\x' } 'path: undefined variable rejected'
    Assert-Throws { Resolve-CmlPath 'D:\' } 'path: drive root rejected'

    # --- default paths for Study
    $def = Get-CmlDefaultPaths -Name 'Study'
    Assert-True ($def['dataDir'] -eq (Join-Path $env:APPDATA 'Study')) 'default: login data under APPDATA'
    Assert-True ($def['configDir'] -eq (Join-Path $user '.claude-study')) 'default: workspace memory is .claude-study (lowercase)'
    Assert-True ($def['workspaceDir'] -eq (Join-Path (Join-Path $user 'Workspaces') 'Study')) 'default: dedicated folder under Workspaces'

    # --- dry run creates nothing
    Add-CmlProfile -Name 'Study' -NoShortcut -DryRun | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Study'))) 'dry run: no folder created'
    Assert-True (@((Read-CmlConfig)['profiles']).Count -eq 0) 'dry run: config unchanged'

    # --- existing dedicated folder is reused, its files untouched
    $keepDir = Join-Path (Join-Path $user 'Workspaces') 'Study'
    New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $keepDir 'mine.txt') -Value 'my own file'

    # --- add
    Add-CmlProfile -Name 'Study' -NoShortcut | Out-Null
    $cfg = Read-CmlConfig
    Assert-True (@($cfg['profiles']).Count -eq 1) 'add: one profile stored'
    $firstProfile = @($cfg['profiles'])[0]
    Assert-True (-not [bool]$firstProfile['launched']) 'add: new profile is marked as never launched'
    $sum = @(Get-CmlProfileSummary)
    Assert-True ($sum[0].ShortcutLabel -eq '') 'summary: unmatched profile has an empty shortcut label'
    Assert-True ($sum.Count -eq 1 -and $sum[0].Name -eq 'Study') 'summary: one row for the new profile'
    Assert-True ((-not $sum[0].Launched) -and (-not $sum[0].HasShortcut) -and ($sum[0].Violations.Count -eq 0)) 'summary: not launched, no shortcut, no isolation violations'
    Assert-True (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Study')) 'add: login data folder created'
    Assert-True (Test-Path -LiteralPath (Join-Path $user '.claude-study')) 'add: workspace memory folder created'
    Assert-True (Test-Path -LiteralPath (Join-Path $keepDir 'mine.txt')) 'add: existing dedicated folder reused, file kept'
    Assert-Throws { Add-CmlProfile -Name 'study' -NoShortcut } 'add: duplicate name (case-insensitive) rejected'
    Assert-Throws { Add-CmlProfile -Name 'bad name' -NoShortcut } 'add: invalid name rejected'

    Add-CmlProfile -Name 'Work' -NoShortcut | Out-Null
    $cfg = Read-CmlConfig
    $work = $null
    foreach ($p in @($cfg['profiles'])) { if ($p['name'] -eq 'Work') { $work = $p } }
    Assert-True (@(Test-CmlIsolation -Prof $work -Others @($cfg['profiles'])).Count -eq 0) 'isolation: two default profiles are independent'

    # --- isolation rules
    Assert-Throws { Add-CmlProfile -Name 'P1' -NoShortcut -WorkspaceDir (Join-Path $user 'Workspaces\Study') } 'rule 2: same location as another profile rejected'
    Assert-Throws { Add-CmlProfile -Name 'P2' -NoShortcut -WorkspaceDir (Join-Path $env:APPDATA 'Study\inner') } 'rule 2: nested inside another profile rejected'
    Assert-Throws { Add-CmlProfile -Name 'P3' -NoShortcut -ConfigDir (Join-Path $user '.claude') } 'rule 3: ~/.claude rejected'
    Assert-Throws { Add-CmlProfile -Name 'P4' -NoShortcut -WorkspaceDir (Join-Path $user 'Claude') } 'rule 3: ~/Claude rejected'
    Assert-Throws { Add-CmlProfile -Name 'P5' -NoShortcut -DataDir (Join-Path $env:APPDATA 'Claude') } 'rule 3: default app data rejected without -ReuseDefault'
    Assert-Throws { Add-CmlProfile -Name 'P6' -NoShortcut -DataDir (Join-Path $user 'same') -WorkspaceDir (Join-Path $user 'same') } 'rule 1: duplicate inside one profile rejected'
    Assert-Throws { Add-CmlProfile -Name 'P7' -NoShortcut -ConfigDir (Join-Path $user 'cfg') -WorkspaceDir (Join-Path $user 'cfg\ws') } 'rule 1: nesting inside one profile rejected'
    Assert-Throws { Add-CmlProfile -Name 'P8' -NoShortcut -ConfigDir $user } 'rule 3: a folder containing a shared location rejected'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA 'P1'))) 'rejected add created nothing'
    Assert-True (@((Read-CmlConfig)['profiles']).Count -eq 2) 'rejected adds left the config unchanged'

    # --- -ReuseDefault is the only exemption, and only for login data
    Add-CmlProfile -Name 'Main' -NoShortcut -ReuseDefault | Out-Null
    Assert-True (@((Read-CmlConfig)['profiles']).Count -eq 3) 'reuse default: accepted'

    # --- -Root
    $rootDir = Join-Path $sandbox 'Rooted'
    Add-CmlProfile -Name 'Lab' -NoShortcut -Root $rootDir | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $rootDir 'Lab\config')) 'root: config under root'
    Assert-True (Test-Path -LiteralPath (Join-Path $rootDir 'Lab\workspace')) 'root: workspace under root'
    Assert-True (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Lab')) 'root: login data stays under APPDATA'

    # --- set-path never moves or deletes data
    $newTemp = Join-Path $sandbox 'NewTemp'
    Set-CmlProfilePath -Name 'Study' -Type 'temp' -Path $newTemp | Out-Null
    Assert-True (Test-Path -LiteralPath $newTemp) 'set-path: new empty folder created'
    Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $env:LOCALAPPDATA 'claude-multi-launcher') 'tmp\Study')) 'set-path: old folder left in place'
    Assert-Throws { Set-CmlProfilePath -Name 'Study' -Type 'workspace' -Path (Join-Path $env:APPDATA 'Work') } 'set-path: conflicting location rejected'
    Assert-Throws { Set-CmlProfilePath -Name 'Study' -Type 'nonsense' -Path $newTemp } 'set-path: unknown type rejected'

    # --- removal plan (read-only): nothing is deleted by this test
    $plan = Get-CmlRemovalPlan -Name 'Study'
    $pd = @($plan.Items | Where-Object { $_.Kind -eq 'dataDir' })[0]
    Assert-True ($pd.Exists -and -not $pd.Reason -and -not $plan.Running) 'purge plan: own login data folder is allowed, profile not running'
    $pw = @($plan.Items | Where-Object { $_.Kind -eq 'workspaceDir' })[0]
    Assert-True ([bool]$pw.Reason) 'purge plan: dedicated folder with files is never offered for deletion'

    # --- rename keeps all paths
    Rename-CmlProfile -Name 'Study' -NewName 'Study2' | Out-Null
    $cfg = Read-CmlConfig
    $s2 = $null
    foreach ($p in @($cfg['profiles'])) { if ($p['name'] -eq 'Study2') { $s2 = $p } }
    Assert-True ($null -ne $s2) 'rename: new name stored'
    Assert-True ($s2['dataDir'] -eq (Join-Path $env:APPDATA 'Study')) 'rename: login data path unchanged'

    # --- remove keeps every data folder
    Remove-CmlProfile -Name 'Study2' -AssumeYes | Out-Null
    Assert-True (@((Read-CmlConfig)['profiles']).Count -eq 3) 'remove: record deleted'
    Assert-True (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Study')) 'remove: login data kept'
    Assert-True (Test-Path -LiteralPath (Join-Path $user '.claude-study')) 'remove: workspace memory kept'
    Assert-True (Test-Path -LiteralPath (Join-Path $keepDir 'mine.txt')) 'remove: dedicated folder and its file kept'

    # --- scan / import of an existing clone (read-only detection, record-only import)
    $dirs = @(Get-CmlDataDirsFromText 'Claude.exe --user-data-dir="C:\Data\A B" --foo --user-data-dir=C:\Data\C')
    Assert-True ($dirs.Count -eq 2 -and $dirs[0] -eq 'C:\Data\A B' -and $dirs[1] -eq 'C:\Data\C') 'scan: parses quoted and unquoted --user-data-dir'
    $tk = @(Get-CmlQuotedTokens '"C:\a b\launch.vbs" "C:\Users\x\AppData\Roaming\Personal" "C:\Users\x\.claude-personal"')
    Assert-True ($tk.Count -eq 3 -and $tk[0] -eq 'C:\a b\launch.vbs' -and $tk[2] -eq 'C:\Users\x\.claude-personal') 'scan: splits quoted shortcut arguments'
    $old = Join-Path $env:APPDATA 'OldClone'
    New-Item -ItemType Directory -Path $old -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $old 'claude_desktop_config.json') -Value '{}'
    $before = (Get-Item -LiteralPath (Join-Path $old 'claude_desktop_config.json')).LastWriteTimeUtc
    $hit = @(Find-CmlExistingClones | Where-Object { $_.DataDir -eq $old })
    Assert-True ($hit.Count -eq 1 -and -not $hit[0].Registered) 'scan: finds a folder that looks like a Claude data folder'
    Import-CmlProfile -Name 'OldClone' -DataDir $old -NoShortcut | Out-Null
    $imp = @((Read-CmlConfig)['profiles'] | Where-Object { $_['name'] -eq 'OldClone' })[0]
    Assert-True (($null -ne $imp) -and [bool]$imp['launched'] -and $imp['dataDir'] -eq $old) 'import: registered with its existing data folder, marked as launched'
    Assert-True ((Get-Item -LiteralPath (Join-Path $old 'claude_desktop_config.json')).LastWriteTimeUtc -eq $before) 'import: files in the original folder untouched'
    Assert-True (@(Find-CmlExistingClones | Where-Object { $_.DataDir -eq $old })[0].Registered) 'scan: imported folder is shown as registered'
    Assert-Throws { Import-CmlProfile -Name 'OldClone' -DataDir $old -NoShortcut } 'import: duplicate name rejected'
    Assert-Throws { Import-CmlProfile -Name 'Ghost' -DataDir (Join-Path $env:APPDATA 'NoSuchDir') -NoShortcut } 'import: missing data folder rejected'
}
catch {
    $script:Fail++
    $err = 'ERROR  ' + $_.Exception.Message
    $script:Log.Add($err)
    $script:Log.Add([string]$_.ScriptStackTrace)
    Write-Host $err -ForegroundColor Red
    Write-Host ([string]$_.ScriptStackTrace) -ForegroundColor Red
}
finally {
    foreach ($v in $saved.Keys) { [Environment]::SetEnvironmentVariable($v, $saved[$v]) }
    if ($sandbox -and (Test-Path -LiteralPath $sandbox) -and $sandbox.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
$summary = ('Passed: {0}   Failed: {1}' -f $script:Pass, $script:Fail)
Write-Host $summary
$script:Log.Add('')
$script:Log.Add($summary)
$resultFile = Join-Path $PSScriptRoot 'Test-Core.result.txt'
try {
    [IO.File]::WriteAllLines($resultFile, $script:Log.ToArray())
    Write-Host ('Result saved to: ' + $resultFile)
} catch { }
if (-not $NoPause -and $Host.Name -eq 'ConsoleHost') { [void](Read-Host 'Press Enter to close') }
if ($script:Fail -gt 0) { exit 1 }
exit 0
