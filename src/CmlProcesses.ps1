# Process metadata only. Never reads authentication files or inspects login state.
function Write-CmlProgress {
    param([scriptblock]$OnProgress, [string]$Step, [int]$Index, [int]$Total)
    if ($OnProgress) { & $OnProgress ([ordered]@{ type = 'progress'; step = $Step; text = (Get-CmlText ('step.' + $Step)); index = $Index; total = $Total }) | Out-Null }
}

function Get-CmlProcessInventory {
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    return @(Get-CimInstance -ClassName Win32_Process -Filter ("Name = 'Claude.exe' AND SessionId = {0}" -f $session) -OperationTimeoutSec 3 -ErrorAction Stop)
}

function ConvertTo-CmlProcessRecord {
    param($Row)
    foreach ($key in @('ProcessId','ExecutablePath','CommandLine','CreationDate')) {
        if (-not $Row.PSObject.Properties[$key] -or $null -eq $Row.$key) { return $null }
    }
    if (-not $Row.ExecutablePath -or -not $Row.CommandLine -or -not $Row.CreationDate) { return $null }
    $created = ([datetime]$Row.CreationDate).ToUniversalTime()
    return [pscustomobject]@{ ProcessId = [int]$Row.ProcessId; Path = [string]$Row.ExecutablePath; CommandLine = [string]$Row.CommandLine; Created = $created; Id = ('{0}:{1}' -f $Row.ProcessId,$created.Ticks) }
}

function Get-CmlProcessDataArguments {
    param([string]$CommandLine)
    $pattern = '(?i)(?:^|\s)(?:"--user-data-dir=([^"]+)"|--user-data-dir(?:=|\s+)(?:"([^"]+)"|([^\s"]+)))'
    foreach ($match in [regex]::Matches($CommandLine,$pattern)) {
        foreach ($i in 1..3) { if ($match.Groups[$i].Success) { $match.Groups[$i].Value; break } }
    }
}

function Get-CmlProfileProcesses {
    param([System.Collections.IDictionary]$Prof, [object[]]$Inventory, [string]$ExePath)
    $matchedProcesses = @(); $unknown = $false
    foreach ($row in $Inventory) {
        $record = ConvertTo-CmlProcessRecord $row
        if (-not $record) { $unknown = $true; continue }
        if ($record.CommandLine -match '(?i)(?:^|\s)"?--type(?:=|\s)') { continue }
        $dirs = @(Get-CmlProcessDataArguments $record.CommandLine)
        if ($dirs.Count -eq 0 -and $record.CommandLine -match '(?i)--user-data-dir') { $unknown = $true; continue }
        $belongs = $false
        if ([bool]$Prof['reuseDefault'] -and $dirs.Count -eq 0) { $belongs = $true }
        foreach ($dir in $dirs) {
            try { if ((Get-CmlPathRelation (Resolve-CmlPath $dir) $Prof['dataDir']) -eq 'equal') { $belongs = $true } } catch { $unknown = $true }
        }
        if (-not $belongs) { continue }
        if ($dirs.Count -gt 1 -or $record.Path -ine $ExePath) { $unknown = $true; continue }
        $matchedProcesses += $record
    }
    $status = 'stopped'
    if ($unknown) { $status = 'unknown' } elseif ($matchedProcesses.Count) { $status = 'running' }
    return [pscustomobject]@{ Status = $status; Processes = @($matchedProcesses) }
}

function Get-CmlRuntimeSnapshot {
    param([System.Collections.IDictionary]$Config = (Read-CmlConfig))
    $states = @{}
    try {
        $exe = Resolve-CmlClaudeExe
        $inventory = @(Get-CmlProcessInventory)
        foreach ($prof in @($Config['profiles'])) { $states[$prof['name']] = Get-CmlProfileProcesses -Prof $prof -Inventory $inventory -ExePath $exe.Path }
    } catch {
        foreach ($prof in @($Config['profiles'])) { $states[$prof['name']] = [pscustomobject]@{ Status = 'unknown'; Processes = @() } }
    }
    return $states
}

function Get-CmlLiveProfileProcesses {
    param([System.Collections.IDictionary]$Prof, [string]$ExePath)
    try { return (Get-CmlProfileProcesses -Prof $Prof -Inventory @(Get-CmlProcessInventory) -ExePath $ExePath) }
    catch { throw (Get-CmlText 'runtime.query_failed') }
}

function Get-CmlValidatedProcess {
    param($Record)
    # Recheck the PID, creation time, image and command line before acting. Bind its handle
    # before returning, so a later PID reuse cannot redirect a force termination.
    $rows = @(Get-CmlProcessInventory | Where-Object { [int]$_.ProcessId -eq $Record.ProcessId })
    if ($rows.Count -ne 1) { throw (Get-CmlText 'runtime.changed') }
    $fresh = ConvertTo-CmlProcessRecord $rows[0]
    if (-not $fresh -or $fresh.Id -cne $Record.Id -or $fresh.Path -ine $Record.Path -or $fresh.CommandLine -cne $Record.CommandLine) { throw (Get-CmlText 'runtime.changed') }
    $process = Get-Process -Id $Record.ProcessId -ErrorAction Stop
    [void]$process.Handle
    # Win32_Process dates have microsecond precision; native StartTime has 100ns precision.
    if ([math]::Abs($process.StartTime.ToUniversalTime().Ticks - $Record.Created.Ticks) -ge 10) { $process.Dispose(); throw (Get-CmlText 'runtime.changed') }
    return $process
}

function Invoke-CmlProcessAction {
    param($Record, [ValidateSet('focus','close','force')][string]$Action)
    $process = Get-CmlValidatedProcess $Record
    try {
        if ($Action -eq 'force') { $process.Kill(); return $true }
        if ($Action -eq 'close') { return $process.CloseMainWindow() }
        $process.Refresh()
        $handle = $process.MainWindowHandle
        if ($handle -eq [IntPtr]::Zero) { return $false }
        if (-not ('CmlWindowNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CmlWindowNative {
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
        }
        if ([CmlWindowNative]::IsIconic($handle)) { [void][CmlWindowNative]::ShowWindowAsync($handle,9) }
        return [CmlWindowNative]::SetForegroundWindow($handle)
    } finally { $process.Dispose() }
}

function Wait-CmlProfileProcess {
    param([System.Collections.IDictionary]$Prof, [string]$ExePath, [bool]$WantRunning, [ValidateRange(0,30)][int]$TimeoutSeconds)
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $state = Get-CmlLiveProfileProcesses -Prof $Prof -ExePath $ExePath
        if ($state.Status -eq 'unknown') { throw (Get-CmlText 'runtime.query_failed') }
        if (($state.Processes.Count -gt 0) -eq $WantRunning) { return $state }
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { return $state }
        Start-Sleep -Milliseconds 250
    } while ($true)
}

function Stop-CmlProfile {
    param([Parameter(Mandatory=$true)][string]$Name, [switch]$Force, [string[]]$ExpectedIds = @(), [ValidateRange(0,15)][int]$TimeoutSeconds = 5, [scriptblock]$OnProgress)
    Write-CmlProgress $OnProgress 'process' 1 3
    $prof = Get-CmlProfileOrThrow (Read-CmlConfig) $Name
    $exe = Resolve-CmlClaudeExe
    $state = Get-CmlLiveProfileProcesses $prof $exe.Path
    if ($state.Status -eq 'unknown') { throw (Get-CmlText 'runtime.query_failed') }
    if ($Force) {
        $actual = @($state.Processes | ForEach-Object { $_.Id })
        if (-not $ExpectedIds.Count -or $actual.Count -ne $ExpectedIds.Count -or @(Compare-Object $actual $ExpectedIds).Count) { throw (Get-CmlText 'runtime.changed') }
    }
    Write-CmlProgress $OnProgress 'close' 2 3
    foreach ($record in $state.Processes) {
        $action = 'close'; if ($Force) { $action = 'force' }
        [void](Invoke-CmlProcessAction $record $action)
    }
    Write-CmlProgress $OnProgress 'wait_close' 3 3
    $after = Wait-CmlProfileProcess $prof $exe.Path $false $TimeoutSeconds
    return [ordered]@{ ok = $true; stopped = ($after.Processes.Count -eq 0); remaining = @($after.Processes | ForEach-Object { $_.Id }) }
}
