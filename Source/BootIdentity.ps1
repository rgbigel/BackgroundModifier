# =================================================================================================
#  Module:      BootIdentity.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
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
    #  EFI PARTITION ENUMERATION  (BootEntryManager tactic)
    # =============================================================================================

    $efiGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"
    $efiPartitionsRaw = Get-Partition -ErrorAction Stop |
        Where-Object { $_.GptType -eq $efiGuid } |
        Sort-Object DiskNumber, PartitionNumber

    $EfiPartitions = @()

    foreach ($partition in $efiPartitionsRaw) {
        $volume = $null
        try {
            $volume = $partition | Get-Volume -ErrorAction Stop
        }
        catch {
            $volume = $null
        }

        $EfiPartitions += [ordered]@{
            DiskNumber        = $partition.DiskNumber
            PartitionNumber   = $partition.PartitionNumber
            PartitionTypeGuid = $partition.GptType
            PartitionType     = $partition.Type
            IsSystem          = [bool]$partition.IsSystem
            IsBoot            = [bool]$partition.IsBoot
            VolumeLabel       = if ($volume) { [string]$volume.FileSystemLabel } else { $null }
            DriveLetter       = if ($volume -and $volume.DriveLetter) { [string]$volume.DriveLetter } else { $null }
            FileSystemType    = if ($volume) { [string]$volume.FileSystemType } else { $null }
        }
    }

    Write-Log -Path $Log -Message "Enumerated and correlated EFI partitions."

    # --- Determine active ESP from partition metadata.
    $ActiveEsp = $EfiPartitions | Where-Object { $_.IsSystem } | Select-Object -First 1
    if (-not $ActiveEsp) {
        $ActiveEsp = $EfiPartitions | Select-Object -First 1
    }

    if (-not $ActiveEsp) {
        Write-Log -Path $Log -Message "No active ESP with label 'System' found." -Level "ERROR"
    }

    # =============================================================================================
    #  BCD BOOTLOADER PATH RESOLUTION
    # =============================================================================================

    $Bcd = bcdedit /enum "{current}" | Out-String

    $Device = ($Bcd -split "`r?`n" | Select-String "^\s*device\s+").ToString().Split()[-1]
    $Path   = ($Bcd -split "`r?`n" | Select-String "^\s*path\s+").ToString().Split()[-1]

    $BootLoaderPath = $null

    if ($Device -and $Path) {
        $BootLoaderPath = "$Device$Path"
        Write-Log -Path $Log -Message "Resolved bootloader path: $BootLoaderPath"
    }
    else {
        Write-Log -Path $Log -Message "Could not resolve bootloader path." -Level "ERROR"
    }

    # =============================================================================================
    #  WRITE STATE.JSON
    # =============================================================================================

    $ActiveEspState = [ordered]@{
        DiskNumber      = $null
        PartitionNumber = $null
        VolumeLabel     = $null
        DriveLetter     = $null
        BootLoaderPath  = $BootLoaderPath
    }

    if ($ActiveEsp) {
        $ActiveEspState = [ordered]@{
            DiskNumber      = $ActiveEsp.DiskNumber
            PartitionNumber = $ActiveEsp.PartitionNumber
            VolumeLabel     = $ActiveEsp.VolumeLabel
            DriveLetter     = $ActiveEsp.DriveLetter
            BootLoaderPath  = $BootLoaderPath
        }
    }

    $State = [ordered]@{
        OS      = $OsInfo
        System  = $SystemInfo
        ESP     = [ordered]@{
            All    = $EfiPartitions
            Active = $ActiveEspState
        }
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
