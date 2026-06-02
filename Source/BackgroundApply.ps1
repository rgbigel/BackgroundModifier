# =================================================================================================
#  Module:      BackgroundApply.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (logon autorun orchestrator)
# =================================================================================================

param(
    [switch]$t
)

$scriptItem = Get-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
$resolvedScriptPath = $PSCommandPath
if ($scriptItem -and $scriptItem.LinkType -eq "SymbolicLink" -and $scriptItem.Target) {
    $resolvedScriptPath = [string]$scriptItem.Target
}
$ScriptRootResolved = Split-Path -Parent ([System.IO.Path]::GetFullPath($resolvedScriptPath))
$RepoRootResolved = Split-Path -Parent $ScriptRootResolved
$ModuleRoot = Join-Path $RepoRootResolved "Modules"
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

$flags = Set-Flags -T:$t
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

Write-Host "=== BackgroundModifier BackgroundApply.ps1 (v6.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled" }

$rendererScript = Join-Path $ScriptRootResolved "BackgroundRenderer.ps1"
$setterScript = Join-Path $ScriptRootResolved "BackgroundSetter.ps1"

try {
    Write-Host "--- Stage: render ---"
    & $rendererScript -t:$t
    $rendererInvocationSucceeded = $?
    if (-not $rendererInvocationSucceeded) {
        throw "BackgroundRenderer failed"
    }

    Write-Host "--- Stage: no-blur policy ---"
    Set-NoBlur

    Write-Host "--- Stage: apply ---"
    & $setterScript -t:$t
    $setterInvocationSucceeded = $?
    if (-not $setterInvocationSucceeded) {
        throw "BackgroundSetter failed"
    }

    Write-Host "[OK] Logon orchestration completed"
}
catch {
    Write-Host "[X] Logon orchestration failed: $($_.Exception.Message)"
    exit 1
}


