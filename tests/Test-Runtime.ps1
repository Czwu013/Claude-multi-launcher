param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
function Assert-Runtime {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ('FAIL ' + $Message) }
    $script:Passed++; Write-Output ('PASS ' + $Message)
}
function Assert-Rejected {
    param([scriptblock]$Block,[string]$Message)
    $rejected = $false; try { & $Block | Out-Null } catch { $rejected = $true }
    Assert-Runtime $rejected $Message
}
$repo = Split-Path -Parent $PSScriptRoot
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('cml-runtime-' + [guid]::NewGuid().ToString('N'))
$saved = @{}; $helpers = @(); $server = $null
foreach ($key in @('APPDATA','LOCALAPPDATA','USERPROFILE','CML_HOME','CLAUDE_CONFIG_DIR','CLAUDE_CODE_TMPDIR')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
try {
    $env:APPDATA=Join-Path $sandbox 'Roaming'; $env:LOCALAPPDATA=Join-Path $sandbox 'Local'; $env:USERPROFILE=Join-Path $sandbox 'User'; $env:CML_HOME=Join-Path $sandbox 'Home'
    foreach ($dir in @($env:APPDATA,$env:LOCALAPPDATA,$env:USERPROFILE)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Import-Module (Join-Path $repo 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
    Set-CmlLanguage 'en' | Out-Null
    foreach ($name in @('Alpha','Beta')) { Add-CmlProfile -Name $name -Root (Join-Path $sandbox 'Profiles') -NoShortcut | Out-Null }
    $cfg=Read-CmlConfig; $alpha=$cfg['profiles'][0]; $beta=$cfg['profiles'][1]
    $m=Get-Module ClaudeMultiLauncher
    $exe=Join-Path $sandbox 'Claude.exe'
    $date=[datetime]::UtcNow
    $row=[pscustomobject]@{ProcessId=101;ExecutablePath=$exe;CommandLine=('"{0}" --user-data-dir="{1}"' -f $exe,$alpha['dataDir']);CreationDate=$date}
    & $m { param($Path) $script:TestExe=$Path; $script:TestRows=@(); $script:Started=0; $script:Acts=@(); $script:Mode='none'; $script:LaunchEnv=@{}; $script:TestFocus=$true
        function script:Resolve-CmlClaudeExe { return @{Path=$script:TestExe;Source='test';Version='1.0'} }
        function script:Get-CmlProcessInventory { if ($script:Mode -eq 'deny') { throw 'test query denied' }; return $script:TestRows }
        function script:Invoke-CmlProcessAction { param($Record,$Action) $script:Acts+=('{0}:{1}' -f $Action,$Record.ProcessId); if ($Action -eq 'force' -or ($Action -eq 'close' -and $script:Mode -eq 'close')) { $script:TestRows=@($script:TestRows | Where-Object { $_.ProcessId -ne $Record.ProcessId }) }; return $script:TestFocus }
        function script:Invoke-CmlStartProcess { param($StartInfo) $script:Started++; $script:LaunchEnv=@{config=$env:CLAUDE_CONFIG_DIR;temp=$env:CLAUDE_CODE_TMPDIR;work=$StartInfo.WorkingDirectory}; if ($script:Mode -eq 'throw') { throw 'test start failure' }; if ($script:Mode -eq 'start') { $script:TestRows=@($script:NextRow) } }
    } $exe
    $setRows = { param($Rows) & $m {param($Rows) $script:TestRows=@($Rows)} $Rows }
    & $setRows @($row)
    $states=Get-CmlRuntimeSnapshot
    Assert-Runtime ($states.Alpha.Status -eq 'running' -and $states.Beta.Status -eq 'stopped') 'exact profile matching does not match a different path'
    $quoted=[pscustomobject]@{ProcessId=102;ExecutablePath=$exe;CommandLine=('"{0}" "--user-data-dir={1}"' -f $exe,$alpha['dataDir']);CreationDate=$date}
    & $setRows @($quoted)
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Alpha.Status -eq 'running') 'whole-argument quoting and spaces are parsed'
    $prefixed=[pscustomobject]@{ProcessId=103;ExecutablePath=$exe;CommandLine=('--user-data-dir="{0}2"' -f $alpha['dataDir']);CreationDate=$date}
    & $setRows @($prefixed)
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Alpha.Status -eq 'stopped') 'profile directory prefix is not an exact match'
    $helper=[pscustomobject]@{ProcessId=104;ExecutablePath=$exe;CommandLine=($row.CommandLine+' --type=renderer');CreationDate=$date}
    & $setRows @($helper)
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Alpha.Status -eq 'stopped') 'Electron helper processes are excluded'
    $other=[pscustomobject]@{ProcessId=105;ExecutablePath=(Join-Path $sandbox 'other\Claude.exe');CommandLine=$row.CommandLine;CreationDate=$date}
    & $setRows @($other)
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Alpha.Status -eq 'unknown') 'same profile with unexpected executable is unknown and cannot be controlled'
    & $setRows @([pscustomobject]@{ProcessId=106})
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Alpha.Status -eq 'unknown') 'unreadable process metadata is unknown, never stopped'
    $malformed=[pscustomobject]@{ProcessId=107;ExecutablePath=$exe;CommandLine='Claude.exe --user-data-dir=';CreationDate=$date}
    & $setRows @($malformed)
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Alpha.Status -eq 'unknown') 'unparseable data-dir arguments are unknown rather than stopped'
    & $m { $script:Mode='deny' }
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Beta.Status -eq 'unknown') 'CIM failure yields unknown status'
    Assert-Rejected { Start-CmlProfile Alpha -TimeoutSeconds 0 } 'unknown process state blocks launch'
    Assert-Rejected { Stop-CmlProfile Alpha -TimeoutSeconds 0 } 'unknown process state blocks close'
    & $m { $script:Mode='none' }; & $setRows @($row)
    $focus=Start-CmlProfile Alpha -TimeoutSeconds 0
    Assert-Runtime ($focus.alreadyRunning -and $focus.focused -and (& $m {$script:Started}) -eq 0) 'existing instance is focused without a new launch'
    & $m {$script:TestFocus=$false}
    $focus=Start-CmlProfile Alpha -TimeoutSeconds 0
    Assert-Runtime ($focus.alreadyRunning -and -not $focus.focused -and (& $m {$script:Started}) -eq 0) 'missing window is reported without duplicate launch'
    & $m {$script:TestFocus=$true}; & $setRows @()
    $events=New-Object Collections.ArrayList
    $report={param($Event) [void]$events.Add($Event)}.GetNewClosure()
    Assert-Rejected { Start-CmlProfile Alpha -TimeoutSeconds 0 -OnProgress $report } 'launch request without a matching process times out'
    Assert-Runtime (-not [bool]((Read-CmlConfig)['profiles'][0]['launched'])) 'timeout does not mark a profile as launched'
    Assert-Runtime (($events | ForEach-Object {$_.step}) -join ',' -eq 'validate,install,process,start,wait_start') 'launch reports actual ordered steps including wait'
    $env:CLAUDE_CONFIG_DIR='before-config';$env:CLAUDE_CODE_TMPDIR='before-temp'
    & $m {param($Next) $script:NextRow=$Next;$script:Mode='start'} $row
    $started=Start-CmlProfile Alpha -TimeoutSeconds 0
    $launchEnv=& $m {$script:LaunchEnv}
    Assert-Runtime ($started.first -and -not $started.alreadyRunning -and [bool]((Read-CmlConfig)['profiles'][0]['launched'])) 'detected process marks first successful launch'
    Assert-Runtime ($launchEnv.config -eq $alpha['configDir'] -and $launchEnv.temp -eq $alpha['tempDir'] -and $launchEnv.work -eq $alpha['workspaceDir']) 'child launch receives independent config/temp/workspace paths'
    Assert-Runtime ($env:CLAUDE_CONFIG_DIR -eq 'before-config' -and $env:CLAUDE_CODE_TMPDIR -eq 'before-temp') 'environment is restored after launch'
    & $setRows @(); & $m {$script:Mode='throw'}
    Assert-Rejected { Start-CmlProfile Beta -TimeoutSeconds 0 } 'start error is propagated'
    Assert-Runtime ($env:CLAUDE_CONFIG_DIR -eq 'before-config' -and $env:CLAUDE_CODE_TMPDIR -eq 'before-temp') 'environment is restored after launch exception'
    & $m {$script:Mode='none';$script:Acts=@()}; & $setRows @($row)
    $closed=Stop-CmlProfile Alpha -TimeoutSeconds 0
    Assert-Runtime (-not $closed.stopped -and $closed.remaining.Count -eq 1 -and ((& $m {$script:Acts}) -join ',') -eq 'close:101') 'normal close timeout never forces termination'
    Assert-Rejected { Stop-CmlProfile Alpha -Force -TimeoutSeconds 0 } 'force requires explicit process identity confirmation'
    Assert-Rejected { Stop-CmlProfile Alpha -Force -ExpectedIds @('101:old') -TimeoutSeconds 0 } 'stale process identities cannot be force terminated'
    $forced=Stop-CmlProfile Alpha -Force -ExpectedIds $closed.remaining -TimeoutSeconds 0
    Assert-Runtime ($forced.stopped -and ((& $m {$script:Acts}) -join ',') -eq 'close:101,force:101') 'confirmed force targets only the selected profile'
    & $m {$script:Mode='close'}; & $setRows @($row)
    Assert-Runtime ((Stop-CmlProfile Alpha -TimeoutSeconds 0).stopped) 'normal exit is observed'
    $info=Get-CmlMcpConfigInfo Alpha
    Assert-Runtime (-not $info.exists -and -not (Test-Path -LiteralPath $info.path)) 'missing MCP config is reported without creating or reading it'
    Assert-Rejected { Open-CmlMcpConfig Alpha } 'missing MCP config cannot open or create Notepad document'
    [IO.File]::WriteAllText($info.path,'{"sample":"not credentials"}')
    $before=[IO.File]::ReadAllBytes($info.path)
    Assert-Runtime ((Get-CmlMcpConfigInfo Alpha).exists) 'existing MCP file is detected by metadata'
    & $m { $script:Opened=@(); function script:Start-Process {param($FilePath,$ArgumentList) $script:Opened=@($FilePath,$ArgumentList)} }
    Open-CmlMcpConfig Alpha | Out-Null
    Assert-Runtime ((& $m {$script:Opened[0]}) -like '*\System32\notepad.exe' -and (& $m {$script:Opened[1]}) -eq ('"{0}"' -f $info.path)) 'MCP opens the exact quoted path in Notepad'
    Assert-Runtime ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($info.path))) 'MCP action leaves configuration bytes untouched'
    $cfg=Read-CmlConfig;$cfg['profiles'][0]['shortcut']=$true;$cfg['profiles'][1]['shortcut']=$true;Write-CmlConfig $cfg
    & $m {param($Root) $script:TestRoot=$Root;$script:Repaired=@()
        function script:Get-CmlShortcutPath {param($Name) return (Join-Path $script:TestRoot ($Name+'.lnk'))}
        function script:Test-CmlOurShortcut {param($LnkPath) return ($LnkPath -like '*Alpha.lnk')}
        function script:Get-CmlIconPath {param([switch]$Refresh) if (-not $Refresh) {throw 'refresh required'};return 'test.ico'}
        function script:Update-CmlShortcut {param($Name) $script:Repaired+=$Name}
    } $sandbox
    [IO.File]::WriteAllText((Join-Path $sandbox 'Beta.lnk'),'external fixture')
    $plan=Get-CmlRepairPlan
    Assert-Runtime ($plan.items.Count -eq 2 -and $plan.items[1].protected) 'repair plan identifies protected external shortcut'
    $repaired=Repair-CmlShortcuts
    Assert-Runtime ($repaired.results[0].status -eq 'updated' -and $repaired.results[1].status -eq 'protected' -and ((& $m {$script:Repaired}) -join ',') -eq 'Alpha') 'repair refreshes icon and rebuilds only eligible tool shortcuts'
    & $m { function script:Update-CmlShortcut {param($Name) throw 'simulated write failure'} }
    Assert-Runtime ((Repair-CmlShortcuts).results[0].status -eq 'failed') 'repair records a per-shortcut failure rather than claiming success'
    & $m { function script:Get-CimInstance {param($ClassName,$Filter,$ErrorAction) throw 'simulated CIM denial'} }
    Assert-Rejected { Get-CmlRemovalPlan Alpha } 'process-query failure also blocks the destructive data-removal preview'

    # Real OS checks use our own inert, unsigned sleep helper named Claude.exe.
    # This is NOT Claude Desktop; it reads no files and has no network or login code.
    $source=Join-Path $sandbox 'helper.cs'
    [IO.File]::WriteAllText($source,'using System.Threading; class Helper { static void Main() { Thread.Sleep(60000); } }')
    $compiler=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:winexe (('/out:{0}' -f $exe)) $source
    if ($LASTEXITCODE -ne 0) {throw 'helper compilation failed'}
    Import-Module (Join-Path $repo 'src\ClaudeMultiLauncher.psm1') -Force -DisableNameChecking
    $cfg=Read-CmlConfig;$cfg['claudeExe']=$exe;Write-CmlConfig $cfg
    $live=Start-CmlProfile Alpha -TimeoutSeconds 5
    $otherLive=Start-CmlProfile Beta -TimeoutSeconds 5
    $snapshot=Get-CmlRuntimeSnapshot
    $helpers=@($snapshot.Alpha.Processes.ProcessId)+@($snapshot.Beta.Processes.ProcessId)
    Assert-Runtime (-not $live.alreadyRunning -and -not $otherLive.alreadyRunning -and $snapshot.Alpha.Status -eq 'running' -and $snapshot.Beta.Status -eq 'running') 'real ShellExecute/CIM distinguishes two sandbox helper profiles'
    $record=$snapshot.Alpha.Processes[0]
    $staleRecord=[pscustomobject]@{ProcessId=$record.ProcessId;Path=$record.Path;CommandLine=$record.CommandLine;Created=$record.Created;Id='reused-pid-fixture'}
    $m=Get-Module ClaudeMultiLauncher
    Assert-Rejected { & $m {param($Record) $process=Get-CmlValidatedProcess $Record; $process.Dispose()} $staleRecord } 'live validation rejects changed identity before binding or acting'
    $normal=Stop-CmlProfile Alpha -TimeoutSeconds 0
    Assert-Runtime (-not $normal.stopped -and $normal.remaining.Count -eq 1) 'hidden helper stays alive after normal close without automatic kill'
    $forceResult=Stop-CmlProfile Alpha -Force -ExpectedIds $normal.remaining -TimeoutSeconds 5
    Assert-Runtime ($forceResult.stopped -and (Get-CmlRuntimeSnapshot).Alpha.Status -eq 'stopped') 'real validated handle termination removes only the confirmed helper'
    Assert-Runtime ((Get-CmlRuntimeSnapshot).Beta.Status -eq 'running') 'closing Alpha leaves the other real helper profile running'
    $betaIds=@((Get-CmlRuntimeSnapshot).Beta.Processes | ForEach-Object {$_.Id})
    Stop-CmlProfile Beta -Force -ExpectedIds $betaIds -TimeoutSeconds 5 | Out-Null
    $helpers=@()

    # Real loopback HTTP streaming, still using only the inert helper and sandbox config.
    $stdout=Join-Path $sandbox 'server.out';$stderr=Join-Path $sandbox 'server.err'
    $hostExe=(Get-Process -Id $PID).Path
    $server=Start-Process -FilePath $hostExe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"{0}"' -f (Join-Path $repo 'claude-multi-server.ps1')),'-NoBrowser') -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $url='';$clock=[Diagnostics.Stopwatch]::StartNew()
    while (-not $url -and $clock.Elapsed.TotalSeconds -lt 15) {
        if(Test-Path -LiteralPath $stdout) { $logStream=[IO.File]::Open($stdout,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); $logReader=New-Object IO.StreamReader($logStream); try { $logText=$logReader.ReadToEnd() } finally { $logReader.Dispose() }; $match=[regex]::Match($logText,'http://127\.0\.0\.1:\d+/\?t=[a-f0-9]+');if($match.Success){$url=$match.Value} }
        if(-not $url){Start-Sleep -Milliseconds 200}
    }
    if(-not $url){throw 'test server did not start'}
    $uri=[uri]$url;$nonce=$uri.Query.Substring(3);$origin=$uri.GetLeftPart([UriPartial]::Authority)
    Add-Type -AssemblyName System.Net.Http
    $client=New-Object Net.Http.HttpClient
    try {
        $request=New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post,($origin+'/api/launch'))
        $request.Headers.Add('X-Token',$nonce);$request.Headers.Add('X-Progress','1')
        $request.Content=New-Object Net.Http.StringContent('{"name":"Alpha"}',[Text.Encoding]::UTF8,'application/json')
        $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $reader=New-Object IO.StreamReader($response.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
        try {
            $firstEvent=$reader.ReadLine() | ConvertFrom-Json
            Assert-Runtime ($response.Content.Headers.ContentType.MediaType -eq 'application/x-ndjson' -and $firstEvent.type -eq 'progress' -and $firstEvent.step -eq 'validate') 'real HttpListener flushes a progress event before the final result'
            $events=@($firstEvent)
            while($null -ne ($line=$reader.ReadLine())) {if($line){$events+=($line | ConvertFrom-Json)}}
            if ($events[-1].type -eq 'error') { throw ('Loopback operation error: ' + $events[-1].error) }
            Assert-Runtime ($events[-1].type -eq 'result' -and $events[-1].result.ok -and @($events | Where-Object {$_.type -eq 'progress'}).Count -eq 5) 'real loopback launch emits five steps and one successful result'
            $helpers=@((Get-CmlRuntimeSnapshot).Alpha.Processes.ProcessId)
        } finally { $reader.Dispose();$response.Dispose();$request.Dispose() }
        $bad=New-Object Net.Http.HttpRequestMessage([Net.Http.HttpMethod]::Post,($origin+'/api/state'));$bad.Content=New-Object Net.Http.StringContent('{}')
        $denied=$client.SendAsync($bad).GetAwaiter().GetResult()
        Assert-Runtime ([int]$denied.StatusCode -eq 403) 'real loopback API still rejects a missing nonce'
        $denied.Dispose();$bad.Dispose()
    } finally {$client.Dispose()}
    Write-Output ('Passed: {0}   Failed: 0' -f $script:Passed)
} finally {
    if($server){Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue;$server.Dispose()}
    foreach($helperId in $helpers){Stop-Process -Id $helperId -Force -ErrorAction SilentlyContinue}
    # Also find a helper if a test failed between startup and tracking. Image path must
    # equal the verified sandbox executable; real Claude processes are never targeted.
    foreach($pr in @(Get-Process -Name Claude -ErrorAction SilentlyContinue)) {try {if($pr.Path -eq (Join-Path $sandbox 'Claude.exe')){$pr.Kill()}}catch{}finally{$pr.Dispose()}}
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    if(Test-Path -LiteralPath $sandbox){Remove-Item -LiteralPath $sandbox -Recurse -Force}
}
