<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
    Module:     SystemInfoTools.psm1
    Version:    1.0.0
    Author:     Rolf Bercht

    Purpose:
        Provides system information query functions for Windows 11, BCD, EFI, and volume inventory.
        Atomic functions used for display rendering and system metadata collection.
        Shared utility module with independent versioning from main solution (v9.0.0).

    Caller Contract (Module-Caller State Update Responsibility):
        This module processes system data and returns results. Caller is responsible for:
        - get-*: Safe to call; read-only, no state modification needed
        - Compute-SystemInfoHash: Called during Phase 1 collection; caller must:
            * Capture returned $hash value
            * Write $hash to state.json (.systemInfo.hash) with collectionSourceVersion (caller $Version)
            * Write collectionSource and collectedAtUtc timestamp to state.json
            * Failure to update state.json makes Phase 2 change detection unreliable
        - This module does NOT directly modify state.json; caller owns state consistency
============================================================================================ #>

$Version = "1.0.0"

function Test-IsWindows11 {
    <#
    .SYNOPSIS
        Detects if system is running Windows 11 or later.
    .DESCRIPTION
        Checks CurrentBuildNumber registry value and returns true if build >= 22000.
    .OUTPUTS
        [bool] True if Windows 11+, false otherwise.
    #>
    try {
        $build = [int](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber")
        return ($build -ge 22000)
    }
    catch {
        return $false
    }
}

function Get-DefaultBcdIdentifier {
    <#
    .SYNOPSIS
        Extracts the default boot entry description from BCD.
    .DESCRIPTION
        Queries bcdedit /enum all /v and returns the default boot entry description.
        Falls back to GUID if description unavailable.
    .OUTPUTS
        [string] Description of default boot entry, GUID as fallback, or error status.
    #>
    try {
        $bcdEdit = Join-Path $env:WINDIR "System32\bcdedit.exe"
        if (-not (Test-Path $bcdEdit)) {
            return "(bcdedit missing)"
        }

        # Single call to get all BCD entries
        $allOutput = & $bcdEdit /enum all /v 2>$null | Out-String
        
        if (-not $allOutput) {
            return "(unavailable)"
        }

        # Extract default GUID from Boot Manager entry (GUID: {9dea862c-5cdd-4e70-acc1-f32b344370f5})
        $defaultGuid = $null
        $blocks = [regex]::Split($allOutput, "(?:`r?`n){2,}")
        
        foreach ($block in $blocks) {
            # Match Boot Manager entry by its GUID (with -v flag, shortcut names like {bootmgr} don't appear)
            if ($block -match "(?im)^\s*identifier\s+\{9dea862c-5cdd-4e70-acc1-f32b344370f5\}") {
                # Found Boot Manager block, extract default GUID
                if ($block -match "(?im)^\s*default\s+(\{[^}]+\})") {
                    $defaultGuid = $matches[1]
                }
                break
            }
        }

        if (-not $defaultGuid) {
            return "(not set)"
        }

        # Find the block containing this GUID and extract its description
        foreach ($block in $blocks) {
            if ($block -match "(?im)^\s*identifier\s+(\{[^}]+\})") {
                $blockGuid = $matches[1]
                if ($blockGuid -eq $defaultGuid) {
                    # Found the block for default GUID, now get description
                    if ($block -match "(?im)^\s*description\s+(.+)$") {
                        return $matches[1].Trim()
                    }
                    # No description found, return GUID
                    return $defaultGuid
                }
            }
        }

        # Description not found, return GUID
        return $defaultGuid
    }
    catch {
        return "(error)"
    }
}

function Get-EfiVolumeLabel {
    <#
    .SYNOPSIS
        Retrieves the EFI System Partition (ESP) label.
    .DESCRIPTION
        Queries EFI partition by GUID and returns volume label.
        Returns disk/partition reference if label unavailable.
    .OUTPUTS
        [string] EFI volume label, partition reference, error status.
    #>
    try {
        $efiGuid = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
        $efiPartition = Get-Partition -ErrorAction SilentlyContinue |
            Where-Object { $_.GptType -eq $efiGuid } |
            Select-Object -First 1

        if (-not $efiPartition) {
            return "(not found)"
        }

        $efiVolume = Get-Volume -Partition $efiPartition -ErrorAction SilentlyContinue
        if (-not $efiVolume) {
            $displayPartition = [Math]::Max(0, ([int]$efiPartition.PartitionNumber - 1))
            return "Disk $($efiPartition.DiskNumber) Part $displayPartition"
        }

        $label = if ([string]::IsNullOrWhiteSpace($efiVolume.FileSystemLabel)) {
            "(no label)"
        }
        else {
            $efiVolume.FileSystemLabel
        }

        $displayPartition = [Math]::Max(0, ([int]$efiPartition.PartitionNumber - 1))
        return "$label (D$($efiPartition.DiskNumber)P$displayPartition)"
    }
    catch {
        return "(error)"
    }
}

function Get-VolumeInventorySummary {
    <#
    .SYNOPSIS
        Counts volumes and BCD-referenced volumes.
    .DESCRIPTION
        Returns formatted summary of total volume count and BCD entry references.
    .OUTPUTS
        [string] Formatted summary "Volumes=N; BCDRefs=M" or error status.
    #>
    try {
        $volumes = @(Get-Volume -ErrorAction SilentlyContinue)
        $volumeCount = $volumes.Count

        $bcdRefCount = 0
        try {
            $bcdEdit = Join-Path $env:WINDIR "System32\bcdedit.exe"
            if (Test-Path $bcdEdit) {
                $bcdText = (& $bcdEdit /enum all /v 2>$null | Out-String)
                if ($bcdText) {
                    $bcdRefCount = ([regex]::Matches($bcdText, '\\\\Device\\\\HarddiskVolume\d+') |
                        ForEach-Object { $_.Value.ToLowerInvariant() } |
                        Select-Object -Unique).Count
                }
            }
        }
        catch {
            $bcdRefCount = 0
        }

        return "Volumes=$volumeCount; BCDRefs=$bcdRefCount"
    }
    catch {
        return "(error)"
    }
}

function Compute-SystemInfoHash {
    <#
    .SYNOPSIS
        Computes SHA256 hash of system information.
    .DESCRIPTION
        Creates deterministic hash from system info fields to detect changes.
        Hash covers: hostname, username, osVersion, buildNumber, ipAddresses, efiLabel, bcdDefault, volumeInventory.
        Excludes timestamps to enable change detection independent of render time.
    .PARAMETER SystemInfo
        [PSCustomObject] with properties: hostname, username, osVersion, buildNumber, ipAddresses, efiLabel, bcdDefault, volumeInventory.
    .OUTPUTS
        [string] SHA256 hash in hexadecimal format (lowercase).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$SystemInfo
    )

    try {
        # Concatenate fields in deterministic order
        $concatenated = @(
            $SystemInfo.hostname,
            $SystemInfo.username,
            $SystemInfo.osVersion,
            $SystemInfo.buildNumber,
            $SystemInfo.ipAddresses,
            $SystemInfo.efiLabel,
            $SystemInfo.bcdDefault,
            $SystemInfo.volumeInventory
        ) -join "|" 

        # Compute SHA256
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($concatenated)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha256.ComputeHash($bytes)
        $hexHash = [BitConverter]::ToString($hash) -replace '-', ''
        return $hexHash.ToLower()
    }
    catch {
        return "(error:$($_.Exception.Message))"
    }
}

Export-ModuleMember -Function @(
    'Test-IsWindows11',
    'Get-DefaultBcdIdentifier',
    'Get-EfiVolumeLabel',
    'Get-VolumeInventorySummary',
    'Compute-SystemInfoHash'
)
