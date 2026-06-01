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
    #  DISKPART ESP ENUMERATION  (A1 + Variant 1)
    # =============================================================================================

    function Invoke-Diskpart {
        param([string[]]$Lines)

        $script = $Lines -join "`r`n"
        $bytes  = [System.Text.Encoding]::ASCII.GetBytes($script)
        $ms     = New-Object System.IO.MemoryStream
        $ms.Write($bytes,0,$bytes.Length)
        $ms.Position = 0

        return (diskpart /s - $ms | Out-String)
    }

    # --- Step 1: list disk
    $DiskList = Invoke-Diskpart @("list disk")
    $DiskNumbers = @(
        [regex]::Matches($DiskList, "Disk\s+(\d+)") |
        ForEach-Object { $_.Groups[1].Value }
    ) | Select-Object -Unique

    $Partitions = @()

    foreach ($d in $DiskNumbers) {

        $out = Invoke-Diskpart @(
            "list disk"
            "select disk $d"
            "list partition"
        )

        foreach ($line in ($out -split "`r?`n")) {
            if ($line -match "^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.+)$") {
                $Partitions += [ordered]@{
                    DiskNumber        = [int]$d
                    PartitionNumber   = [int]$Matches[1]
                    PartitionTypeGuid = $Matches[5].Trim()
                }
            }
        }
    }

    # --- Step 2: list volume
    $VolOut = Invoke-Diskpart @("list volume")
    $Volumes = @()

    foreach ($line in ($VolOut -split "`r?`n")) {
        if ($line -match "^\s*(\d+)\s+([A-Z]?)\s+(\S*)\s+(.+?)\s+(\d+)\s+(\d+)\s*$") {
            $Volumes += [ordered]@{
                VolumeNumber    = [int]$Matches[1]
                DriveLetter     = $Matches[2]
                Label           = $Matches[3]
                DiskNumber      = [int]$Matches[5]
                PartitionNumber = [int]$Matches[6]
            }
        }
    }

    # --- Step 3: correlate EFI partitions
    $EfiPartitions = @()

    foreach ($p in $Partitions) {
        if ($p.PartitionTypeGuid -match "EFI") {

            $v = $Volumes | Where-Object {
                $_.DiskNumber -eq $p.DiskNumber -and
                $_.PartitionNumber -eq $p.PartitionNumber
            }

            $EfiPartitions += [ordered]@{
                DiskNumber        = $p.DiskNumber
                PartitionNumber   = $p.PartitionNumber
                PartitionTypeGuid = $p.PartitionTypeGuid
                VolumeLabel       = $v.Label
                DriveLetter       = $v.DriveLetter
            }
        }
    }

    Write-Log -Path $Log -Message "Enumerated and correlated EFI partitions."

    # --- Step 4: determine active ESP
    $ActiveEsp = $EfiPartitions | Where-Object { $_.VolumeLabel -eq "System" } | Select-Object -First 1

    if (-not $ActiveEsp) {
        Write-Log -Path $Log -Message "No active ESP with label 'System' found." -Level "ERROR"
    }

    # =============================================================================================
    #  BCD BOOTLOADER PATH RESOLUTION
    # =============================================================================================

    $Bcd = bcdedit /enum "{current}" | Out-String

    $Device = ($Bcd -split "`r?`n" | Select-String "device").ToString().Split()[-1]
    $Path   = ($Bcd -split "`r?`n" | Select-String "path").ToString().Split()[-1]

    $BootLoaderPath = $null

    if ($ActiveEsp -and $Path) {

        $root = if ($ActiveEsp.DriveLetter) {
            "$($ActiveEsp.DriveLetter):\"
        } else {
            "\"
        }

        $BootLoaderPath = Join-Path $root $Path.TrimStart("\")
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
