# =================================================================================================
#  Module:      check-and-report.ps1
#  Path:        .\scripts
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

$repoRoot = Split-Path -Parent $PSScriptRoot
$reportDir = Join-Path $repoRoot 'reports'
New-Item -Path $reportDir -ItemType Directory -Force | Out-Null

$codeFiles = Get-ChildItem -Path $repoRoot -Recurse -File -Include *.ps1,*.psm1 |
    Where-Object { $_.FullName -notmatch '\\.git\\' }
$docsFiles = Get-ChildItem -Path (Join-Path $repoRoot 'docs') -File -ErrorAction SilentlyContinue

$headerKeys = @('Module','Path','Author','Version')
$headerReport = [System.Collections.Generic.List[string]]::new()
$exportReport = [System.Collections.Generic.List[string]]::new()
$unrefFunctions = [System.Collections.Generic.List[string]]::new()

foreach ($file in $codeFiles) {
    $content = ''
    try { $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop } catch { $content = '' }
    $head = ($content -split "`n") | Select-Object -First 80

    $missing = @()
    foreach ($key in $headerKeys) {
        if (-not ($head -join "`n" -match "(?im)^\s*#\s*$key\s*:\s*.+$")) {
            $missing += $key
        }
    }
    if ($missing.Count -gt 0) {
        $headerReport.Add("$($file.FullName) -> MISSING: $($missing -join ', ')")
    }

    if ($file.Extension -ieq '.psm1') {
        if ($content -notmatch 'Export-ModuleMember') {
            $exportReport.Add("$($file.FullName) -> no Export-ModuleMember")
        }
    }

    $matches = [regex]::Matches($content, '(?im)^\s*function\s+([A-Za-z0-9_\-:]+)\s*(\{|\()')
    foreach ($m in $matches) {
        $fn = $m.Groups[1].Value
        $found = $false
        foreach ($doc in $docsFiles) {
            if (Select-String -Path $doc.FullName -Pattern ([regex]::Escape($fn)) -SimpleMatch -Quiet -ErrorAction SilentlyContinue) {
                $found = $true
                break
            }
        }
        if (-not $found) {
            $unrefFunctions.Add("$($file.FullName)::${fn}")
        }
    }
}

$pssaPath = Join-Path $reportDir 'pssa-results.txt'
if (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue) {
    $pssa = Invoke-ScriptAnalyzer -Path $repoRoot -Recurse
    if ($pssa) {
        $pssa | Sort-Object Severity, ScriptName, Line | Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize | Out-String | Set-Content -Path $pssaPath
    } else {
        'No PSScriptAnalyzer findings.' | Set-Content -Path $pssaPath
    }
} else {
    'PSScriptAnalyzer not installed.' | Set-Content -Path $pssaPath
}

$reportPath = Join-Path $reportDir 'code-checks.txt'
@(
    'Header check results:'
    if ($headerReport.Count -eq 0) { 'All files contain Module/Path/Author/Version headers.' } else { $headerReport }
    ''
    'Export checks (.psm1):'
    if ($exportReport.Count -eq 0) { 'All .psm1 files contain Export-ModuleMember.' } else { $exportReport }
    ''
    'Functions not referenced in docs:'
    if ($unrefFunctions.Count -eq 0) { 'No unreferenced functions found.' } else { $unrefFunctions | Sort-Object -Unique }
) | Set-Content -Path $reportPath

Write-Output "Done. Reports:"
Write-Output " - $reportPath"
Write-Output " - $pssaPath"

