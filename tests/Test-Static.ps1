param([string]$Root = (Split-Path -Parent $PSScriptRoot))
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') })
$files = @($files | Where-Object { $_.FullName -notlike ((Join-Path $Root 'build') + '\*') })
$failures = @()
$parsed = @()
foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { $failures += "Missing UTF-8 BOM: $($file.Name)" }
    try { [void]([Text.UTF8Encoding]::new($false, $true).GetString($bytes)) } catch { $failures += "Invalid UTF-8: $($file.Name)" }
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($errorItem in @($errors)) { $failures += "$($file.Name): $($errorItem.Message)" }
    $parsed += $ast
}
$zh = Import-PowerShellDataFile -LiteralPath (Join-Path $Root 'src\i18n\zh.psd1')
$en = Import-PowerShellDataFile -LiteralPath (Join-Path $Root 'src\i18n\en.psd1')
if (Compare-Object @($zh.Keys) @($en.Keys)) { $failures += 'i18n keys differ' }
foreach ($key in $zh.Keys) {
    $a = @([regex]::Matches(($zh[$key] -join "`n"), '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $b = @([regex]::Matches(($en[$key] -join "`n"), '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    if (@(Compare-Object $a $b).Count) { $failures += "i18n placeholders differ: $key" }
}
$nativeZh = Get-Content -LiteralPath (Join-Path $Root 'src\i18n\native.zh.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$nativeEn = Get-Content -LiteralPath (Join-Path $Root 'src\i18n\native.en.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (Compare-Object @($nativeZh.PSObject.Properties.Name) @($nativeEn.PSObject.Properties.Name)) { $failures += 'native i18n keys differ' }
# Conservative lexical audit: parameters, assignments and loop variables are declarations.
# Runtime branch/order behavior is covered by Test-Core; this is not a full data-flow proof.
$automatic = @('null','true','false','_','PSItem','args','input','this','Error','Host','HOME','PID','PWD','PSHOME','PSScriptRoot','PSCommandPath','PSBoundParameters','MyInvocation','ExecutionContext','LASTEXITCODE','PSVersionTable','PSCulture','PSUICulture','Matches','ErrorActionPreference','OFS')
foreach ($ast in $parsed) {
    $declarations = @{}
    foreach ($node in @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.VariableExpressionAst] }, $true))) {
        $parentNode = $node.Parent
        $isDeclaration = ($parentNode -is [Management.Automation.Language.ParameterAst]) -or
            ($parentNode -is [Management.Automation.Language.ForEachStatementAst] -and $parentNode.Variable -eq $node) -or
            ($parentNode -is [Management.Automation.Language.AssignmentStatementAst] -and $parentNode.Left -eq $node) -or
            ($parentNode -is [Management.Automation.Language.UnaryExpressionAst] -and $parentNode.TokenKind -in @('PlusPlus','MinusMinus','PostfixPlusPlus','PostfixMinusMinus'))
        if ($isDeclaration) {
            $scope = $node.Parent
            while ($scope -and $scope -isnot [Management.Automation.Language.ScriptBlockAst]) { $scope = $scope.Parent }
            $name = $node.VariablePath.UserPath -replace '^(script|local|private):', ''
            if ($node.VariablePath.UserPath -like 'script:*') { $scope = $ast }
            if ($scope) { $declarations["$($scope.Extent.StartOffset):$name"] = $true }
        }
    }
    foreach ($node in @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.VariableExpressionAst] }, $true))) {
        $name = $node.VariablePath.UserPath
        if ($name -like 'env:*' -or $name -like 'global:*') { continue }
        $name = $name -replace '^(script|local|private):', ''
        if ($name -in $automatic) { continue }
        $scope = $node.Parent; $known = $false
        while ($scope) {
            if ($scope -is [Management.Automation.Language.ScriptBlockAst] -and $declarations.ContainsKey("$($scope.Extent.StartOffset):$name")) { $known = $true; break }
            $scope = $scope.Parent
        }
        if (-not $known) { $failures += "$([IO.Path]::GetFileName($ast.Extent.File)):$($node.Extent.StartLineNumber) unresolved variable: $name" }
    }
}
if ($failures.Count) { $failures | Sort-Object -Unique | Write-Output; exit 1 }
Write-Output "PASS UTF-8 BOM and parser: $($files.Count) files"
Write-Output "PASS i18n keys and placeholders: $($zh.Count) keys per language"
Write-Output ('PASS native i18n: {0} keys per language' -f @($nativeZh.PSObject.Properties).Count)
Write-Output 'PASS lexical variable audit (conservative); run Test-Core for StrictMode runtime coverage'
