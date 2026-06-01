# =================================================================================================
#  Module:      BootIdentity.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     6.0.1
#  Changelog:
#      6.0.1  --------  Delegated ESP/BCD identity determination to BootTools atom module.
#      5.000  --------  Introduced BCD--------based bootloader--------path resolution; restored Diskpart A1/Variant-------1;
#                 added full ESP correlation rules; added BootLoaderPath to State.json.
#      4.004  --------  Refined ESP label handling; removed temp--------file Diskpart capture; pipeline only.
#      4.003  --------  Corrected partition/volume correlation; enforced GUID--------based ESP detection.
#      4.002  --------  Added deterministic logging and strict error handling.
#      4.001  --------  Initial 4.x series structure and module boundary cleanup.
# =================================================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------------------------------------
#  MODULE IMPORTS  (Root: .\Modules)
# -------------------------------------------------------------------------------------------------
$scriptItem = Get-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
$resolvedScriptPath = $PSCommandPath
if ($scriptItem -and $scriptItem.LinkType -eq "SymbolicLink" -and $scriptItem.Target) {
    $resolvedScriptPath = [string]$scriptItem.Target
}
$ScriptRootResolved = Split-Path -Parent ([System.IO.Path]::GetFullPath($resolvedScriptPath))
$RepoRootResolved = Split-Path -Parent $ScriptRootResolved
$ModuleRoot = Join-Path $RepoRootResolved "Modules"
Import-Module (Join-Path $ModuleRoot "LoggingTools.psm1")
Import-Module (Join-Path $ModuleRoot "ConfigTools.psm1")
Import-Module (Join-Path $ModuleRoot "TimeTools.psm1")
Import-Module (Join-Path $ModuleRoot "BootTools.psm1")
Import-Module (Join-Path $ModuleRoot "BackgroundStateMgr.psm1")
Import-Module (Join-Path $ModuleRoot "SystemTools.psm1")
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1")

$RuntimeRoot = "C:\BackgroundMotives"
$LogRoot = Join-Path $RuntimeRoot "logs"
$SystemRoot = Join-Path $RuntimeRoot "system"
if (-not (Test-Path -LiteralPath $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $SystemRoot)) {
    New-Item -ItemType Directory -Path $SystemRoot -Force | Out-Null
}

# -------------------------------------------------------------------------------------------------
#  START LOG
# -------------------------------------------------------------------------------------------------
$Log = Join-Path $LogRoot ("BootIdentity_{0}.log" -f (Get-RunTimestamp))

try {

    # =============================================================================================
    #  OS + SYSTEM IDENTITY
    # =============================================================================================
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    $OsInfo = [ordered]@{
        Caption        = $os.Caption
        Version        = $os.Version
        BuildNumber    = $os.BuildNumber
        InstallDate    = $os.InstallDate
        LastBootUpTime = $os.LastBootUpTime
    }

    $SystemInfo = [ordered]@{
        ComputerName = $cs.Name
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
    }

    Write-Log -Path $Log -Message "Collected OS and System identity."

    # =============================================================================================
    #  ESP/BCD IDENTITY SNAPSHOT
    # =============================================================================================

    $espSnapshot = Get-EspIdentitySnapshot
    if (-not $espSnapshot.All -or $espSnapshot.All.Count -eq 0) {
        Write-Log -Path $Log -Message "No EFI partitions detected." -Level "ERROR"
    }
    else {
        Write-Log -Path $Log -Message "Enumerated and correlated EFI partitions."
    }

    if (-not $espSnapshot.Active.DiskNumber) {
        Write-Log -Path $Log -Message "No active ESP was selected." -Level "ERROR"
    }

    if ($espSnapshot.Active.BootLoaderPath) {
        Write-Log -Path $Log -Message "Resolved bootloader path: $($espSnapshot.Active.BootLoaderPath)"
    }
    else {
        Write-Log -Path $Log -Message "Could not resolve bootloader path." -Level "ERROR"
    }

    # =============================================================================================
    #  WRITE STATE.JSON
    # =============================================================================================

    $State = [ordered]@{
        OS      = $OsInfo
        System  = $SystemInfo
        ESP     = $espSnapshot
    }

    $statePath = Join-Path $SystemRoot "State.json"
    Save-Config -Path $statePath -Config $State
    Write-Log -Path $Log -Message "State.json written: $statePath"
    Write-Log -Path $Log -Message "BootIdentity completed."

}
catch {
    Write-Log -Path $Log -Message $_.Exception.Message -Level "ERROR"
    Write-Host "[X] BootIdentity failed: $($_.Exception.Message)"
    exit 1
}
