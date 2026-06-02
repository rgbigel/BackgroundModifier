# =================================================================================================
#  Module:      ProfileTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Purpose:     Centralized helpers for reading, writing, and validating operator profiles.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (profile utilities)
# =================================================================================================

function Load-Profile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[WARN] Profile not found: $Path"
        return $null
    }

    try {
        $json = Get-Content -Path $Path -Raw
        return ($json | ConvertFrom-Json)
    }
    catch {
        Write-Host "[ERROR] Failed to load profile: $($_.Exception.Message)"
        return $null
    }
}

function Save-Profile {
    param(
        [string]$Path,
        [object]$Profile
    )

    try {
        $Profile | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        Write-Host "[OK] Profile saved -> $Path"
    }
    catch {
        Write-Host "[ERROR] Failed to save profile: $($_.Exception.Message)"
    }
}

function Test-ProfileValid {
    param([object]$Profile)

    if ($null -eq $Profile) { return $false }
    if (-not $Profile.PSObject.Properties.Name -contains "Name") { return $false }

    return $true
}
Export-ModuleMember -Function *


