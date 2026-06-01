# =================================================================================================
#  Module:      LoggingTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Deterministic, append--------only logging helpers used across all modules.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (advanced logging)
# =================================================================================================

function Write-Log {
    param(
        [string]$Path,
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $line = "$timestamp [$Level] $Message"

    try {
        Add-Content -Path $Path -Value $line -Encoding UTF8
    }
    catch {
        Write-Host "[ERROR] Failed to write log: $($_.Exception.Message)"
    }
}

function Write-LogDebug {
    param(
        [string]$Path,
        [string]$Message,
        [bool]$Enabled
    )

    if ($Enabled) {
        Write-Log -Path $Path -Message $Message -Level "DEBUG"
    }
}

function Write-LogTrace {
    param(
        [string]$Path,
        [string]$Message,
        [bool]$Enabled
    )

    if ($Enabled) {
        Write-Log -Path $Path -Message $Message -Level "TRACE"
    }
}
    Export-ModuleMember -Function *

