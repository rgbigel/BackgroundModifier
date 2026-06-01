# =================================================================================================
#  Module:      BackgroundSetterStart.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (logon autorun orchestrator)
# =================================================================================================

param(
    [switch]$t,
    [switch]$d
)

$ModuleRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "Modules"
$prev = $WarningPreference
$WarningPreference = "SilentlyContinue"

Import-Module (Join-Path $ModuleRoot "Constants.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force
Import-Module (Join-Path $ModuleRoot "TranscriptTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "PathTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force
Import-Module (Join-Path $ModuleRoot "BackgroundNoBlurReg.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t -D:$d
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

Write-Host "=== BackgroundModifier Logon Autorun Orchestrator (v5.000) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled" }

$rendererScript = Join-Path $PSScriptRoot "BackgroundRenderer.ps1"
$setterScript = Join-Path $PSScriptRoot "BackgroundSetter.ps1"

try {
    Write-Host "--- Stage: render ---"
    & $rendererScript -t:$t -d:$d
    if ($LASTEXITCODE -ne 0) {
        throw "BackgroundRenderer failed with exit code $LASTEXITCODE"
    }

    Write-Host "--- Stage: no-blur policy ---"
    Set-NoBlur

    Write-Host "--- Stage: apply ---"
    & $setterScript -t:$t -d:$d
    if ($LASTEXITCODE -ne 0) {
        throw "BackgroundSetter failed with exit code $LASTEXITCODE"
    }

    Write-Host "[OK] Logon orchestration completed"
}
catch {
    Write-Host "[X] Logon orchestration failed: $($_.Exception.Message)"
    exit 1
}
