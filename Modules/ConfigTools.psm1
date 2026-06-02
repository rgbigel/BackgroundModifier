# =================================================================================================
#  Module:      ConfigTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Purpose:     Deterministic loading and saving of module--------wide configuration files; isolates config I/O.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (JSON/config I/O)
# =================================================================================================

function Load-Config {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[WARN] Config file not found: $Path"
        return $null
    }

    try {
        $json = Get-Content -Path $Path -Raw
        return ($json | ConvertFrom-Json)
    }
    catch {
        Write-Host "[ERROR] Failed to load config: $($_.Exception.Message)"
        return $null
    }
}

function Save-Config {
    param(
        [string]$Path,
        [object]$Config
    )

    try {
        $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $Path -Encoding UTF8
        Write-Host "[OK] Config saved -> $Path"
    }
    catch {
        Write-Host "[ERROR] Failed to save config: $($_.Exception.Message)"
    }
}
    Export-ModuleMember -Function *


