# =================================================================================================
#  Module:      ValidationTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Purpose:     Deterministic validation helpers for parameters, paths, configs, and workflow-critical preconditions.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (validation utilities)
# =================================================================================================

function Test-PathRequired {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Host "[ERROR] Path parameter is empty."
        return $false
    }

    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Required path not found: $Path"
        return $false
    }

    return $true
}

function Test-StringRequired {
    param(
        [string]$Value,
        [string]$Name = "Value"
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Host "[ERROR] Missing required string: $Name"
        return $false
    }

    return $true
}

function Test-NumberRange {
    param(
        [int]$Value,
        [int]$Min,
        [int]$Max,
        [string]$Name = "Value"
    )

    if ($Value -lt $Min -or $Value -gt $Max) {
        Write-Host "[ERROR] $Name out of range ($Min - $Max): $Value"
        return $false
    }

    return $true
}
    Export-ModuleMember -Function *


