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
$ModuleRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "Modules"
Import-Module (Join-Path $ModuleRoot "LoggingTools.psm1")
Import-Module (Join-Path $ModuleRoot "ConfigTools.psm1")
Import-Module (Join-Path $ModuleRoot "TimeTools.psm1")
Import-Module (Join-Path $ModuleRoot "BackgroundStateMgr.psm1")
Import-Module (Join-Path $ModuleRoot "SystemTools.psm1")
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1")

# -------------------------------------------------------------------------------------------------
#  START LOG
# -------------------------------------------------------------------------------------------------
$Log = Start-Log -Name "BootIdentity"

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

    Write-Log $Log "Collected OS and System identity."

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
    $DiskNumbers = ($DiskList -split "`r?`n" | Select-String "Disk\s+\d+").Matches.Value |
                   ForEach-Object { ($_ -replace "\D","") }

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

    Write-Log $Log "Enumerated and correlated EFI partitions."

    # --- Step 4: determine active ESP
    $ActiveEsp = $EfiPartitions | Where-Object { $_.VolumeLabel -eq "System" } | Select-Object -First 1

    if (-not $ActiveEsp) {
        Write-Log $Log "No active ESP with label 'System' found." "Error"
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
        Write-Log $Log "Resolved bootloader path: $BootLoaderPath"
    }
    else {
        Write-Log $Log "Could not resolve bootloader path." "Error"
    }

    # =============================================================================================
    #  WRITE STATE.JSON
    # =============================================================================================

    $State = [ordered]@{
        OS      = $OsInfo
        System  = $SystemInfo
        ESP     = [ordered]@{
            All    = $EfiPartitions
            Active = [ordered]@{
                DiskNumber      = $ActiveEsp.DiskNumber
                PartitionNumber = $ActiveEsp.PartitionNumber
                VolumeLabel     = $ActiveEsp.VolumeLabel
                DriveLetter     = $ActiveEsp.DriveLetter
                BootLoaderPath  = $BootLoaderPath
            }
        }
    }

    Write-StateJson -Data $State -Log $Log
    Write-Log $Log "BootIdentity completed."

}
catch {
    Write-ErrorLog $Log $_
}
finally {
    Stop-Log $Log
}
