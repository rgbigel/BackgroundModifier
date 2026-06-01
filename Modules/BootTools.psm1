# =================================================================================================
#  Module:      BootTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Changelog:
#      6.0.1  --------  Implemented EFI/ESP detection atom and BCD bootloader resolution helpers.
#      5.000  --------  Initial module creation for Consolidated Architecture (boot identity and ESP detection)
# =================================================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EspPartitions {
	$efiGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

	$efiPartitionsRaw = Get-Partition -ErrorAction Stop |
		Where-Object { $_.GptType -eq $efiGuid } |
		Sort-Object DiskNumber, PartitionNumber

	$efiPartitions = @()

	foreach ($partition in $efiPartitionsRaw) {
		$volume = $null
		try {
			$volume = $partition | Get-Volume -ErrorAction Stop
		}
		catch {
			$volume = $null
		}

		$efiPartitions += [ordered]@{
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

	return $efiPartitions
}

function Get-ActiveEspPartition {
	param(
		[Parameter(Mandatory = $true)]
		[object[]]$EfiPartitions
	)

	if (-not $EfiPartitions -or $EfiPartitions.Count -eq 0) {
		return $null
	}

	$active = $EfiPartitions | Where-Object { $_.IsSystem } | Select-Object -First 1
	if ($active) {
		return $active
	}

	return ($EfiPartitions | Select-Object -First 1)
}

function Get-BootLoaderPathFromCurrentBcd {
	param(
		[string]$BcdText
	)

	if ([string]::IsNullOrWhiteSpace($BcdText)) {
		$BcdText = bcdedit /enum "{current}" | Out-String
	}

	$deviceMatch = [regex]::Match($BcdText, "(?im)^\s*device\s+(.+)$")
	$pathMatch = [regex]::Match($BcdText, "(?im)^\s*path\s+(.+)$")

	if (-not $deviceMatch.Success -or -not $pathMatch.Success) {
		return $null
	}

	$device = $deviceMatch.Groups[1].Value.Trim()
	$path = $pathMatch.Groups[1].Value.Trim()

	if ([string]::IsNullOrWhiteSpace($device) -or [string]::IsNullOrWhiteSpace($path)) {
		return $null
	}

	return "$device$path"
}

function Get-EspIdentitySnapshot {
	param(
		[object[]]$EfiPartitions,
		[string]$BcdText
	)

	if (-not $EfiPartitions) {
		$EfiPartitions = Get-EspPartitions
	}

	$active = Get-ActiveEspPartition -EfiPartitions $EfiPartitions
	$bootLoaderPath = Get-BootLoaderPathFromCurrentBcd -BcdText $BcdText

	$activeState = [ordered]@{
		DiskNumber      = $null
		PartitionNumber = $null
		VolumeLabel     = $null
		DriveLetter     = $null
		BootLoaderPath  = $bootLoaderPath
	}

	if ($active) {
		$activeState = [ordered]@{
			DiskNumber      = $active.DiskNumber
			PartitionNumber = $active.PartitionNumber
			VolumeLabel     = $active.VolumeLabel
			DriveLetter     = $active.DriveLetter
			BootLoaderPath  = $bootLoaderPath
		}
	}

	return [ordered]@{
		All = $EfiPartitions
		Active = $activeState
	}
}

Export-ModuleMember -Function Get-EspPartitions, Get-ActiveEspPartition, Get-BootLoaderPathFromCurrentBcd, Get-EspIdentitySnapshot

