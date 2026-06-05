# =================================================================================================
#  Module:      CleanupTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Purpose:     Centralized cleanup helpers for removing temporary files, old logs, and ensuring deterministic post--------run hygiene.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (cleanup utilities)
# =================================================================================================

function Remove-OldLogs {
    param(
        [string]$LogRoot,
        [int]$Days = 7,
        [switch]$Full
    )

    if (-not (Test-Path $LogRoot)) {
        Write-Host "[WARN] Log root not found: $LogRoot"
        return
    }

    $files = @()
    if ($Full) {
        $files = @(Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue)
    }
    else {
        $limit = (Get-Date).AddDays(-$Days)
        $files = @(Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limit })
    }

    foreach ($file in $files) {
        try {
            Remove-Item $file.FullName -Force
            if ($Full) {
                Write-Host "[OK] Removed log -> $($file.Name)"
            }
            else {
                Write-Host "[OK] Removed old log -> $($file.Name)"
            }
        }
        catch {
            Write-Host "[WARN] Could not remove log: $($file.Name)"
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

function Remove-TestLinks {
    param(
        [string]$CmdRoot,
        [string[]]$TestEntries = @(
            "BackgroundModifier-BootIdentityTest.ps1",
            "BackgroundModifier-RenderTest.ps1",
            "BackgroundModifier-ApplyTest.ps1",
            "BackgroundModifier-LogonStage.ps1"
        )
    )

    if (-not (Test-Path $CmdRoot)) {
        Write-Host "[WARN] Cmd root not found: $CmdRoot"
        return
    }

    foreach ($entry in $TestEntries) {
        $entryPath = Join-Path $CmdRoot $entry
        if (Test-Path -LiteralPath $entryPath) {
            try {
                Remove-Item -LiteralPath $entryPath -Force
                Write-Host "[OK] Removed test link -> $entry"
            }
            catch {
                Write-Host "[WARN] Could not remove test link: $entry"
            }
        }
    }
}
    Export-ModuleMember -Function *


