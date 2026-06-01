# =================================================================================================
#  Module:      ModeTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Helpers for interpreting and exposing debug and trace mode states.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (debug/trace modes)
# =================================================================================================

function Show-DebugState {
    param([bool]$Enabled)
    if ($Enabled) { Write-Host "[DEBUG] Debug mode active" }
}

function Show-TraceState {
    param([bool]$Enabled)
    if ($Enabled) { Write-Host "[TRACE] Trace mode active" }
}
Export-ModuleMember -Function *

