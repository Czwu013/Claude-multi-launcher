param([string]$PackagePath = '', [string]$OutputDir = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = '1.0.4314.35'
$expectedHash = '90778deb1b77e36292828b4b5833c9255c27533f40e0ddd55891ae718944edc4'
$cache = Join-Path $root ('build\webview2-' + $version)
New-Item -ItemType Directory -Path $cache -Force | Out-Null
if (-not $PackagePath) {
    $PackagePath = Join-Path $cache 'sdk.nupkg'
    if (-not (Test-Path -LiteralPath $PackagePath)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $uri = 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/{0}/microsoft.web.webview2.{0}.nupkg' -f $version
        Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $PackagePath -TimeoutSec 90
    }
}
if ((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash -ine $expectedHash) { throw 'WebView2 SDK checksum differs. Refusing to build; remove build/webview2-* and retry.' }
$sdk = Join-Path $cache 'sdk'
if (-not (Test-Path -LiteralPath $sdk)) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $PackagePath).Path, $sdk)
}
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'A 64-bit Windows installation with .NET Framework 4.8 is required.' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$core = Join-Path $sdk 'lib\net462\Microsoft.Web.WebView2.Core.dll'
$forms = Join-Path $sdk 'lib\net462\Microsoft.Web.WebView2.WinForms.dll'
$executable = Join-Path $OutputDir 'claude-multi-launcher.exe'
$icon = Join-Path $root 'assets\launcher.ico'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ "/out:$executable" "/win32icon:$icon" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/reference:$core" "/reference:$forms" (Join-Path $root 'tools\Launcher.cs') (Join-Path $root 'tools\WindowChrome.cs')
if ($LASTEXITCODE -ne 0) { throw 'Native launcher compilation failed.' }
Copy-Item -LiteralPath $core,$forms -Destination $OutputDir -Force
Copy-Item -LiteralPath (Join-Path $sdk 'runtimes\win-x64\native\WebView2Loader.dll') -Destination $OutputDir -Force
Copy-Item -LiteralPath (Join-Path $sdk 'LICENSE.txt') -Destination (Join-Path $OutputDir 'WebView2-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $sdk 'NOTICE.txt') -Destination (Join-Path $OutputDir 'WebView2-NOTICE.txt') -Force
Write-Output ('Built: ' + $executable)
