# =================================================================================================
#  Module:      Logging.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Minimal logging helpers for consistent, deterministic output.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (logging utilities)
# =================================================================================================

function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-LogWarn {
    param([string]$Message)
    Write-Host "[WARN] $Message"
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[ERROR] $Message"
}
Export-ModuleMember -Function *

