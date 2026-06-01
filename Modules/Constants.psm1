# =================================================================================================
#  Module:      Constants.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Centralized constant paths and directory definitions for all components.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (path constants)
# =================================================================================================

$Global:RepoRoot    = Split-Path -Parent $PSScriptRoot
$Global:RootPath    = "C:\BackgroundMotives"
$Global:LogRoot     = Join-Path $Global:RootPath "logs"
$Global:AssetsRoot  = Join-Path $Global:RootPath "assets"
$Global:RenderRoot  = Join-Path $Global:RootPath "rendered"
$Global:SystemRoot  = Join-Path $Global:RootPath "system"
Export-ModuleMember -Function *

