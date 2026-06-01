# =================================================================================================
#  Module:      Cleanup.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Converted to maintenance-only cleanup and aligned module root to top-level Modules.
#      5.000  --------  Initial module creation for Consolidated Architecture (cleanup utility)
# =================================================================================================

$RepoRoot    = Split-Path $PSScriptRoot -Parent
$ModuleRoot  = Join-Path $RepoRoot "Modules"

# Runtime root is explicitly outside the repo
$RuntimeRoot = "C:\BackgroundMotives"
$RenderRoot  = Join-Path $RuntimeRoot "rendered"
$LogRoot     = Join-Path $RuntimeRoot "logs"

Write-Host "=== BackgroundModifier Cleanup (Maintenance Only) ==="

if (-not (Test-Path -LiteralPath $ModuleRoot)) {
    Write-Host "[ERROR] Module root not found: $ModuleRoot"
    exit 1
}

$CleanupModule = Join-Path $ModuleRoot "CleanupTools.psm1"
if (Test-Path -LiteralPath $CleanupModule) {
    Import-Module $CleanupModule -Force

    Write-Host "`n=== Running CleanupTools against C:\BackgroundMotives (logs + rendered) ==="

    Clear-RenderFolder -RenderRoot $RenderRoot
    Remove-OldLogs     -LogRoot    $LogRoot -Days 7
}
else {
    Write-Host "[ERROR] CleanupTools.psm1 not found. Cannot run cleanup."
    exit 1
}

Write-Host "`n=== Cleanup Complete ==="
