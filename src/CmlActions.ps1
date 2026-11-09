# Lifecycle and maintenance actions. Self-authored; no external project code copied.
function Invoke-CmlStartProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    [void][Diagnostics.Process]::Start($StartInfo)
}

function Start-CmlProfile {
    param([Parameter(Mandatory=$true)][string]$Name, [switch]$ShowDialog, [ValidateRange(0,30)][int]$TimeoutSeconds = 15, [scriptblock]$OnProgress)
    Write-CmlProgress $OnProgress 'validate' 1 5
    $cfg = Read-CmlConfig
    $prof = Get-CmlProfileOrThrow $cfg $Name
    $viol = @(Test-CmlIsolation -Prof $prof -Others @($cfg['profiles']))
    if ($viol.Count) { throw (New-CmlIsolationError $viol) }
    Write-CmlProgress $OnProgress 'install' 2 5
    $exe = Resolve-CmlClaudeExe
    Write-CmlProgress $OnProgress 'process' 3 5
    $state = Get-CmlLiveProfileProcesses $prof $exe.Path
    if ($state.Status -eq 'unknown') { throw (Get-CmlText 'runtime.query_failed') }
    if ($state.Processes.Count) {
        $focused = $false
        foreach ($record in $state.Processes) { if (Invoke-CmlProcessAction $record 'focus') { $focused = $true; break } }
        return [ordered]@{ ok = $true; first = $false; alreadyRunning = $true; focused = $focused }
    }
    Write-CmlProgress $OnProgress 'start' 4 5
    foreach ($k in @('dataDir','configDir','workspaceDir','tempDir')) { [void](Initialize-CmlDirectory $prof[$k]) }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe.Path; $psi.UseShellExecute = $true; $psi.WorkingDirectory = $prof['workspaceDir']
    if (-not $prof['reuseDefault']) { $psi.Arguments = ('--user-data-dir="{0}"' -f $prof['dataDir']) }
    $envOld = @{}
    $envNew = @{ CLAUDE_CONFIG_DIR = $prof['configDir']; CLAUDE_CODE_TMPDIR = $prof['tempDir'] }
    foreach ($key in $envNew.Keys) { $envOld[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
    try {
        foreach ($key in $envNew.Keys) { [Environment]::SetEnvironmentVariable($key,$envNew[$key],'Process') }
        Invoke-CmlStartProcess $psi
    } catch { throw (Get-CmlText 'err.launch_failed' @($_.Exception.Message)) }
    finally { foreach ($key in $envOld.Keys) { [Environment]::SetEnvironmentVariable($key,$envOld[$key],'Process') } }
    Write-CmlProgress $OnProgress 'wait_start' 5 5
    $after = Wait-CmlProfileProcess $prof $exe.Path $true $TimeoutSeconds
    if (-not $after.Processes.Count) { throw (Get-CmlText 'runtime.start_timeout' @($TimeoutSeconds)) }
    $first = -not [bool]$prof['launched']
    if ($first) {
        $marked = [ordered]@{}; foreach ($key in $prof.Keys) { $marked[$key] = $prof[$key] }; $marked['launched'] = $true
        Set-CmlProfileRecord $cfg $marked $prof['name']; Write-CmlConfig $cfg
        if ($ShowDialog) {
            Add-Type -AssemblyName System.Windows.Forms
            [void][Windows.Forms.MessageBox]::Show(((Get-CmlText 'msg.first_launch') + "`n`n" + (Get-CmlText 'msg.first_launch_tip')),'Claude Multi Launcher')
        }
    }
    Write-Host (Get-CmlText 'runtime.detected' @($Name))
    return [ordered]@{ ok = $true; first = $first; alreadyRunning = $false; focused = $false }
}

function Get-CmlMcpConfigInfo {
    param([Parameter(Mandatory=$true)][string]$Name)
    $prof = Get-CmlProfileOrThrow (Read-CmlConfig) $Name
    $path = Join-Path (Resolve-CmlPath $prof['dataDir']) 'claude_desktop_config.json'
    if (Get-CmlReparseHit $path) { throw (Get-CmlText 'runtime.config_link') }
    return [ordered]@{ ok = $true; path = $path; exists = [bool](Test-Path -LiteralPath $path -PathType Leaf) }
}

function Open-CmlMcpConfig {
    param([Parameter(Mandatory=$true)][string]$Name)
    $info = Get-CmlMcpConfigInfo $Name
    if (-not $info.exists) { throw (Get-CmlText 'runtime.config_missing') }
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"{0}"' -f $info.path) | Out-Null
    return [ordered]@{ ok = $true }
}

function Get-CmlRepairPlan {
    $exe = Resolve-CmlClaudeExe
    $items = @()
    foreach ($prof in @((Read-CmlConfig)['profiles'])) {
        if (-not $prof['shortcut']) { continue }
        $path = Get-CmlShortcutPath $prof['name']
        $protected = (Test-Path -LiteralPath $path) -and -not (Test-CmlOurShortcut $path)
        $items += ,([ordered]@{ name = $prof['name']; path = $path; protected = [bool]$protected })
    }
    return [ordered]@{ ok = $true; exe = $exe.Path; version = $exe.Version; source = $exe.Source; items = $items }
}

function Repair-CmlShortcuts {
    param([scriptblock]$OnProgress)
    Write-CmlProgress $OnProgress 'install' 1 3
    $plan = Get-CmlRepairPlan
    # Refresh the locally extracted icon atomically; existing shortcuts retain a valid
    # old icon if extraction fails. No cache deletion, registry or app installation.
    Write-CmlProgress $OnProgress 'icon' 2 3
    $ico = Get-CmlIconPath -Refresh
    if (-not $ico) { throw (Get-CmlText 'err.icon_missing') }
    Write-CmlProgress $OnProgress 'shortcuts' 3 3
    $results = @()
    foreach ($item in $plan.items) {
        $status = 'protected'
        if (-not $item.protected) {
            try { Update-CmlShortcut -Name $item.name; $status = 'updated' } catch { $status = 'failed' }
        }
        $results += ,([ordered]@{ name = $item.name; status = $status })
    }
    return [ordered]@{ ok = $true; exe = $plan.exe; version = $plan.version; source = $plan.source; results = $results }
}
