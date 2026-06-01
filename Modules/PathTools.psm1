# =================================================================================================
#  Module:      PathTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Small helpers for safe path creation and validation.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (path utilities)
# =================================================================================================

function Ensure-Path {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return $Path
}

function Join-Safe {
    param(
        [string]$Base,
        [string]$Child
    )
    return (Join-Path $Base $Child)
}
    Export-ModuleMember -Function *

