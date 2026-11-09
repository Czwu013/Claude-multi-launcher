# Claude Multi Launcher: local window. Serves ui\index.html on 127.0.0.1 (random port, random token)
# and opens it in an Edge/Chrome "app" window (no tabs, no address bar). The page calls the same
# functions as the command line. Nothing is reachable from other computers or other web pages.
#   powershell -STA -ExecutionPolicy Bypass -File .\claude-multi-server.ps1

param([switch]$NoBrowser, [int]$ParentProcessId = 0)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

trap {
    $msg = ($_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + [string]$_.ScriptStackTrace)
    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'claude-multi-launcher'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        [IO.File]::WriteAllText((Join-Path $logDir 'gui-error.log'), $msg, [Text.Encoding]::UTF8)
    } catch { }
    [void][System.Windows.MessageBox]::Show($msg, 'Claude Multi Launcher', 'OK', 'Error')
    exit 1
}

Import-Module -Name (Join-Path $PSScriptRoot 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking

$indexPath = Join-Path $PSScriptRoot 'ui\index.html'
if (-not (Test-Path -LiteralPath $indexPath)) { throw ('ui\index.html not found next to this script: ' + $PSScriptRoot) }
$token = [guid]::NewGuid().ToString('N')

# ---- listener on loopback only --------------------------------------------------------------
$listener = $null
$port = 0
for ($i = 0; $i -lt 40 -and $null -eq $listener; $i++) {
    $port = Get-Random -Minimum 49200 -Maximum 65000
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add(('http://127.0.0.1:{0}/' -f $port))
    try { $l.Start(); $listener = $l } catch { $l.Close() }
}
if ($null -eq $listener) { throw 'Could not open a local port.' }

# ---- helpers --------------------------------------------------------------------------------
function Get-Field {
    param($Obj, [string]$Name, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Send-Bytes {
    param($Ctx, [byte[]]$Bytes, [string]$Type, [int]$Code = 200)
    $r = $Ctx.Response
    $r.StatusCode = $Code
    $r.ContentType = $Type
    $r.Headers.Add('Cache-Control', 'no-store')
    $r.Headers.Add('X-Content-Type-Options', 'nosniff')
    $r.ContentLength64 = $Bytes.Length
    $r.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $r.OutputStream.Close()
}

function Send-Json {
    param($Ctx, $Obj, [int]$Code = 200)
    $json = ConvertTo-Json -InputObject $Obj -Depth 8 -Compress
    Send-Bytes $Ctx ([Text.Encoding]::UTF8.GetBytes($json)) 'application/json; charset=utf-8' $Code
}

function Get-StringTable {
    $lang = Get-CmlLang
    $file = Join-Path $PSScriptRoot ('src\i18n\{0}.psd1' -f $lang)
    $raw = Import-PowerShellDataFile -LiteralPath $file
    $out = [ordered]@{}
    foreach ($k in $raw.Keys) { if ($k -ne 'help.lines') { $out[$k] = [string]$raw[$k] } }
    return $out
}

function Get-StateObject {
    $profiles = @()
    foreach ($s in @(Get-CmlProfileSummary)) {
        $profiles += , ([ordered]@{
                name = $s.Name; dataDir = $s.DataDir; configDir = $s.ConfigDir; workspaceDir = $s.WorkspaceDir
                tempDir = $s.TempDir; hasShortcut = $s.HasShortcut; launched = $s.Launched
                violations = @($s.Violations); note = $s.Note; shortcutLabel = $s.ShortcutLabel; processStatus = $s.ProcessStatus; processIds = @($s.ProcessIds)
            })
    }
    return [ordered]@{ ok = $true; lang = (Get-CmlLang); strings = (Get-StringTable); profiles = $profiles }
}

function Invoke-Browse {
    param([string]$Description)
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.ShowInTaskbar = $false
    $owner.StartPosition = 'CenterScreen'
    $owner.Opacity = 0
    $owner.Show()
    try {
        $fb = New-Object System.Windows.Forms.FolderBrowserDialog
        $fb.Description = $Description
        if ($fb.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { return $fb.SelectedPath }
        return ''
    } finally {
        $owner.Close()
    }
}

function Invoke-Api {
    param([string]$Name, $Body, [scriptblock]$OnProgress)
    switch ($Name) {
        'ping' { return [ordered]@{ ok = $true } }
        'state' { return (Get-StateObject) }
        'create' {
            $p = @{ Name = [string](Get-Field $Body 'name' '') }
            $root = [string](Get-Field $Body 'root' '')
            if ($root) { $p['Root'] = $root }
            if (-not [bool](Get-Field $Body 'shortcut' $true)) { $p['NoShortcut'] = $true }
            Add-CmlProfile @p -OnProgress $OnProgress | Out-Null
            return [ordered]@{ ok = $true }
        }
        'launch' { return (Start-CmlProfile -Name ([string](Get-Field $Body 'name' '')) -OnProgress $OnProgress) }
        'stop' {
            $force = [bool](Get-Field $Body 'force' $false)
            $ids = @(); foreach ($itemId in @(Get-Field $Body 'expectedIds' @())) { $ids += [string]$itemId }
            return (Stop-CmlProfile -Name ([string](Get-Field $Body 'name' '')) -Force:$force -ExpectedIds $ids -OnProgress $OnProgress)
        }
        'mcp-info' { return (Get-CmlMcpConfigInfo -Name ([string](Get-Field $Body 'name' ''))) }
        'mcp-open' { return (Open-CmlMcpConfig -Name ([string](Get-Field $Body 'name' ''))) }
        'repair-plan' { return (Get-CmlRepairPlan) }
        'repair' { return (Repair-CmlShortcuts -OnProgress $OnProgress) }
        'open' { Open-CmlWorkspace -Name ([string](Get-Field $Body 'name' '')) | Out-Null; return [ordered]@{ ok = $true } }
        'shortcut' { Update-CmlShortcut -Name ([string](Get-Field $Body 'name' '')) | Out-Null; return [ordered]@{ ok = $true } }
        'reorder' {
            $names = @()
            foreach ($nameItem in @(Get-Field $Body 'names' @())) { $names += [string]$nameItem }
            Set-CmlProfileOrder -Names $names
            return [ordered]@{ ok = $true }
        }
        'remove' {
            # The page asked the user to confirm first. Removes only the record and our own shortcut.
            Remove-CmlProfile -Name ([string](Get-Field $Body 'name' '')) -AssumeYes | Out-Null
            return [ordered]@{ ok = $true }
        }
        'plan' {
            $pl = Get-CmlRemovalPlan -Name ([string](Get-Field $Body 'name' ''))
            $its = @()
            foreach ($it in $pl.Items) {
                $its += , ([ordered]@{ kind = $it.Kind; label = $it.Label; path = $it.Path; exists = $it.Exists; sizeMB = $it.SizeMB; reason = $it.Reason })
            }
            return [ordered]@{ ok = $true; running = $pl.Running; hasShortcut = $pl.HasShortcut; items = $its }
        }
        'purge' {
            # The page showed the preview and the user confirmed. Folders go to the Recycle Bin.
            $kinds = @()
            foreach ($k in @(Get-Field $Body 'kinds' @())) { $kinds += [string]$k }
            Remove-CmlProfileData -Name ([string](Get-Field $Body 'name' '')) -Kinds $kinds | Out-Null
            return [ordered]@{ ok = $true }
        }
        'lang' {
            $v = [string](Get-Field $Body 'value' 'auto')
            Set-CmlLanguage $v | Out-Null
            return [ordered]@{ ok = $true }
        }
        'browse' {
            $path = Invoke-Browse ([string](Get-Field $Body 'description' ''))
            return [ordered]@{ ok = $true; path = $path }
        }
        'scan' {
            $list = @()
            foreach ($c in @(Find-CmlExistingClones)) {
                $list += , ([ordered]@{
                        name = $c.Name; dataDir = $c.DataDir; configDir = $c.ConfigDir; sources = @($c.Sources)
                        running = $c.Running; registered = $c.Registered
                    })
            }
            return [ordered]@{ ok = $true; clones = $list }
        }
        'import' {
            $results = @()
            foreach ($it in @(Get-Field $Body 'items' @())) {
                try {
                    $a = @{ Name = [string](Get-Field $it 'name' ''); DataDir = [string](Get-Field $it 'dataDir' ''); NoShortcut = $true }
                    $cd = [string](Get-Field $it 'configDir' '')
                    if ($cd) { $a['ConfigDir'] = $cd }
                    Import-CmlProfile @a | Out-Null
                    $results += , ([ordered]@{ ok = $true })
                } catch {
                    $results += , ([ordered]@{ ok = $false; error = $_.Exception.Message })
                }
            }
            return [ordered]@{ ok = $true; results = $results }
        }
        default { throw ('Unknown action: ' + $Name) }
    }
}

function Test-Request {
    param($Req)
    if ($Req.Url.Host -ne '127.0.0.1') { return $false }
    if ($Req.Url.Port -ne $port) { return $false }
    return $true
}

function Invoke-Request {
    param($Ctx)
    $req = $Ctx.Request
    if (-not (Test-Request $req)) { Send-Bytes $Ctx ([byte[]]@()) 'text/plain' 403; return }
    $path = $req.Url.AbsolutePath
    if ($req.HttpMethod -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
        if ($req.QueryString['t'] -ne $token) { Send-Bytes $Ctx ([byte[]]@()) 'text/plain' 403; return }
        Send-Bytes $Ctx ([IO.File]::ReadAllBytes($indexPath)) 'text/html; charset=utf-8'
        return
    }
    if ($req.HttpMethod -eq 'POST' -and $path.StartsWith('/api/')) {
        if ($req.Headers['X-Token'] -ne $token) { Send-Bytes $Ctx ([byte[]]@()) 'text/plain' 403; return }
        $name = $path.Substring(5)
        $body = $null
        $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
        try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
        if ($text) { $body = $text | ConvertFrom-Json }
        $script:lastPing = Get-Date
        if ($req.Headers['X-Progress'] -eq '1' -and $name -in @('create','launch','stop','repair')) {
            $Ctx.Response.ContentType = 'application/x-ndjson; charset=utf-8'
            $Ctx.Response.SendChunked = $true
            $Ctx.Response.Headers.Add('Cache-Control','no-store')
            $Ctx.Response.Headers.Add('X-Content-Type-Options','nosniff')
            $writer = New-Object IO.StreamWriter($Ctx.Response.OutputStream,([Text.UTF8Encoding]::new($false)))
            $writer.AutoFlush = $true
            $report = { param($event) $writer.WriteLine((ConvertTo-Json -InputObject $event -Depth 8 -Compress)) }.GetNewClosure()
            try {
                $res = Invoke-Api $name $body -OnProgress $report
                $writer.WriteLine((ConvertTo-Json -InputObject @{type='result';result=$res} -Depth 8 -Compress))
            } catch {
                $writer.WriteLine((ConvertTo-Json -InputObject @{type='error';error=$_.Exception.Message} -Compress))
            } finally { $writer.Dispose(); $Ctx.Response.Close() }
            return
        }
        try {
            $res = Invoke-Api $name $body
            Send-Json $Ctx $res
        } catch {
            Send-Json $Ctx ([ordered]@{ ok = $false; error = $_.Exception.Message })
        }
        return
    }
    Send-Bytes $Ctx ([byte[]]@()) 'text/plain' 404
}

# ---- open the window ------------------------------------------------------------------------
function Find-Browser {
    $cands = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
    )
    foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return $null
}

$url = ('http://127.0.0.1:{0}/?t={1}' -f $port, $token)
$script:lastPing = Get-Date
$parentHost = $null
if ($ParentProcessId -gt 0) {
    $parentHost = [Diagnostics.Process]::GetProcessById($ParentProcessId)
    [void]$parentHost.Handle # Bind this process identity, not a future reused PID.
}
if ($NoBrowser) { Write-Output $url }
$proc = $null
if (-not $NoBrowser) {
    $exe = Find-Browser
    if ($exe) {
        $uiProfile = Join-Path $env:LOCALAPPDATA 'claude-multi-launcher\ui-profile'
        if (-not (Test-Path -LiteralPath $uiProfile)) { New-Item -ItemType Directory -Path $uiProfile -Force | Out-Null }
        $argList = @(('--app={0}' -f $url), ('--user-data-dir="{0}"' -f $uiProfile), '--window-size=1180,800',
            '--no-first-run', '--no-default-browser-check', '--disable-extensions')
        $proc = Start-Process -FilePath $exe -ArgumentList $argList -PassThru
    } else {
        Start-Process $url | Out-Null   # default browser; the page pings, and the server ends when it stops
    }
}

# ---- serve until the window is closed -------------------------------------------------------
$done = $false
while (-not $done) {
    if ($parentHost -and $parentHost.HasExited) { break }
    $ar = $listener.BeginGetContext($null, $null)
    while (-not $ar.AsyncWaitHandle.WaitOne(400)) {
        if ($parentHost -and $parentHost.HasExited) { $done = $true; break }
        if ($proc -and $proc.HasExited) { $done = $true; break }
        if (-not $proc -and -not $NoBrowser -and ((Get-Date) - $script:lastPing).TotalSeconds -gt 30) { $done = $true; break }
    }
    if ($done) { break }
    $ctx = $listener.EndGetContext($ar)
    try { Invoke-Request $ctx } catch { try { $ctx.Response.Abort() } catch { } }
}
$listener.Stop()
$listener.Close()
if ($parentHost) { $parentHost.Dispose() }
