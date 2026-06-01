# =================================================================================================
#  Module:      CleanupTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Centralized cleanup helpers for removing temporary files, old logs, and ensuring deterministic post--------run hygiene.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (cleanup utilities)
# =================================================================================================

function Remove-OldLogs {
    param(
        [string]$LogRoot,
        [int]$Days = 7
    )

    if (-not (Test-Path $LogRoot)) {
        Write-Host "[WARN] Log root not found: $LogRoot"
        return
    }

    $limit = (Get-Date).AddDays(-$Days)

    Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            try {
                Remove-Item $_.FullName -Force
                Write-Host "[OK] Removed old log -> $($_.Name)"
            }
            catch {
                Write-Host "[WARN] Could not remove log: $($_.Name)"
            }
        }
}

function Clear-RenderFolder {
    param([string]$RenderRoot)

    if (-not (Test-Path $RenderRoot)) {
        Write-Host "[WARN] Render folder not found: $RenderRoot"
        return
    }

    try {
        Get-ChildItem -Path $RenderRoot -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
        Write-Host "[OK] Cleared render folder -> $RenderRoot"
    }
    catch {
        Write-Host "[ERROR] Failed to clear render folder: $($_.Exception.Message)"
    }
}
    Export-ModuleMember -Function *

