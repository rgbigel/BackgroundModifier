# =================================================================================================
#  Module:      BootTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.2
#  Changelog:
#      6.0.2  --------  Added batched DiskPart parsing and fsutil enrichment for ESP metadata.
#      6.0.1  --------  Implemented EFI/ESP detection atom and BCD bootloader resolution helpers.
#      5.000  --------  Initial module creation for Consolidated Architecture (boot identity and ESP detection)
# =================================================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-DiskPartCommand {
	param(
		[Parameter(Mandatory = $true)]
		[string[]]$Commands
	)

	$diskpartExe = Join-Path $env:WINDIR 'System32\diskpart.exe'
	if (-not (Test-Path -LiteralPath $diskpartExe)) {
		return $null
	}

	$tempScript = Join-Path $env:TEMP ("bm_diskpart_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
	$tempOutput = Join-Path $env:TEMP ("bm_diskpart_{0}.log" -f ([guid]::NewGuid().ToString('N')))
	try {
		Set-Content -LiteralPath $tempScript -Value ($Commands -join [Environment]::NewLine) -Encoding Ascii

		$cmdLine = ('"{0}" /s "{1}" > "{2}" 2>&1' -f $diskpartExe, $tempScript, $tempOutput)
		cmd.exe /d /c $cmdLine | Out-Null
		if ($LASTEXITCODE -ne 0) {
			return $null
		}

		if (-not (Test-Path -LiteralPath $tempOutput)) {
			return $null
		}

		$output = Get-Content -LiteralPath $tempOutput -Raw -ErrorAction SilentlyContinue
		if ([string]::IsNullOrWhiteSpace($output)) {
			return $null
		}

		return $output
	}
	catch {
		return $null
	}
	finally {
		Remove-Item -LiteralPath $tempScript, $tempOutput -Force -ErrorAction SilentlyContinue
	}
}

function Parse-DiskPartPartitionMetadata {
	param(
		[Parameter(Mandatory = $true)]
		[string]$DetailText
	)

	if ([string]::IsNullOrWhiteSpace($DetailText)) {
		return $null
	}

	$meta = [ordered]@{
		VolumeLabel = $null
		DriveLetter = $null
		FileSystemType = $null
		IsBoot = $null
		IsActive = $null
	}

	$activeMatch = [regex]::Match($DetailText, '(?im)^\s*Active\s*:\s*(.+)$')
	if ($activeMatch.Success) {
		$activeText = $activeMatch.Groups[1].Value.Trim().ToLowerInvariant()
		if ($activeText -match '^(yes|true)$') { $meta.IsActive = $true }
		elseif ($activeText -match '^(no|false)$') { $meta.IsActive = $false }
	}

	$volumeRowMatch = [regex]::Match($DetailText, '(?im)^\s*\*?\s*Volume\s+\d+\s+(?<row>.+)$')
	if ($volumeRowMatch.Success) {
		$row = $volumeRowMatch.Groups['row'].Value.Trim()
		$tokens = @($row -split '\s{2,}' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
		if ($tokens.Count -gt 0) {
			$fsPattern = '^(FAT32|FAT|NTFS|EXFAT|REFS|RAW)$'
			$fsIndex = -1
			for ($i = 0; $i -lt $tokens.Count; $i++) {
				if ($tokens[$i].Trim().ToUpperInvariant() -match $fsPattern) {
					$fsIndex = $i
					break
				}
			}

			if ($fsIndex -ge 0) {
				$meta.FileSystemType = $tokens[$fsIndex].Trim().ToUpperInvariant()

				if ($fsIndex -gt 0) {
					$prefixTokens = @($tokens[0..($fsIndex - 1)])
					if ($prefixTokens.Count -gt 0 -and $prefixTokens[0].Trim() -match '^[A-Za-z]$') {
						$meta.DriveLetter = $prefixTokens[0].Trim().ToUpperInvariant()
						if ($prefixTokens.Count -gt 1) {
							$meta.VolumeLabel = (($prefixTokens[1..($prefixTokens.Count - 1)]) -join ' ').Trim()
						}
					}
					else {
						$meta.VolumeLabel = ($prefixTokens -join ' ').Trim()
					}
				}

				$infoTokens = @()
				if ($tokens.Count -gt ($fsIndex + 3)) {
					$infoTokens = @($tokens[($fsIndex + 3)..($tokens.Count - 1)])
				}
				if ($infoTokens.Count -gt 0) {
					$infoText = ($infoTokens -join ' ').ToLowerInvariant()
					if ($infoText -match '\bboot\b|\bsystem\b') {
						$meta.IsBoot = $true
					}
					elseif ($infoText -match '\bhidden\b') {
						$meta.IsBoot = $false
					}
				}
			}
		}
	}

	return $meta
}

function Get-DiskPartPartitionMetadataMap {
	param(
		[Parameter(Mandatory = $true)]
		[object[]]$Partitions
	)

	$metaMap = @{}
	if (-not $Partitions -or $Partitions.Count -eq 0) {
		return $metaMap
	}

	$commands = @()
	foreach ($partition in $Partitions) {
		$commands += ("select disk {0}" -f [int]$partition.DiskNumber)
		$commands += ("select partition {0}" -f [int]$partition.PartitionNumber)
		$commands += 'detail partition'
	}

	$allOutput = Invoke-DiskPartCommand -Commands $commands
	if ([string]::IsNullOrWhiteSpace($allOutput)) {
		return $metaMap
	}

	$selectedPartitionRegex = [regex]'(?im)selected\s+partition\s+(?<part>\d+)'
	$selectedDiskRegex = [regex]'(?im)selected\s+disk\s+(?<disk>\d+)'

	$currentDisk = $null
	$currentPart = $null
	$blockLines = @()

	$flushBlock = {
		if ($null -eq $currentDisk -or $null -eq $currentPart) {
			return
		}
		$detailText = ($blockLines -join [Environment]::NewLine)
		$parsed = Parse-DiskPartPartitionMetadata -DetailText $detailText
		if ($parsed) {
			$metaMap[("{0}:{1}" -f $currentDisk, $currentPart)] = $parsed
		}
	}

	$lines = $allOutput -split "`r?`n"
	foreach ($line in $lines) {
		$diskMatch = $selectedDiskRegex.Match($line)
		if ($diskMatch.Success) {
			$currentDisk = [int]$diskMatch.Groups['disk'].Value
		}

		$partMatch = $selectedPartitionRegex.Match($line)
		if ($partMatch.Success) {
			& $flushBlock
			$currentPart = [int]$partMatch.Groups['part'].Value
			$blockLines = @()
			continue
		}

		if ($null -ne $currentDisk -and $null -ne $currentPart) {
			$blockLines += $line
		}
	}

	& $flushBlock
	return $metaMap
}

function Get-VolumeFsInfoFromPath {
	param([string]$Path)

	$result = [ordered]@{
		VolumeLabel = $null
		FileSystemType = $null
	}

	if ([string]::IsNullOrWhiteSpace($Path)) {
		return $result
	}

	try {
		$text = fsutil fsinfo volumeinfo $Path 2>$null | Out-String
		if ($text -match '(?im)^\s*Volume Name\s*:\s*(.*)$') {
			$label = $matches[1].Trim()
			if (-not [string]::IsNullOrWhiteSpace($label)) {
				$result.VolumeLabel = $label
			}
		}

		if ($text -match '(?im)^\s*File System Name\s*:\s*(.*)$') {
			$fsName = $matches[1].Trim()
			if (-not [string]::IsNullOrWhiteSpace($fsName)) {
				$result.FileSystemType = $fsName.ToUpperInvariant()
			}
		}
	}
	catch {
		# leave values null when fsutil is not available for the path
	}

	return $result
}

function Get-EspPartitions {
	$efiGuid = "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"

	$efiPartitionsRaw = Get-Partition -ErrorAction Stop |
		Where-Object { $_.GptType -eq $efiGuid } |
		Sort-Object DiskNumber, PartitionNumber

	$efiPartitions = @()
	$diskpartMetaMap = Get-DiskPartPartitionMetadataMap -Partitions $efiPartitionsRaw

	foreach ($partition in $efiPartitionsRaw) {
		$key = ("{0}:{1}" -f [int]$partition.DiskNumber, [int]$partition.PartitionNumber)
		$diskpartMeta = $null
		if ($diskpartMetaMap.ContainsKey($key)) {
			$diskpartMeta = $diskpartMetaMap[$key]
		}

		$partitionAccessPath = $null
		if ($partition.AccessPaths) {
			$candidate = @($partition.AccessPaths | Where-Object { $_ -match '^\\\\\?\\Volume\{[^}]+\}\\$' } | Select-Object -First 1)
			if ($candidate.Count -gt 0) {
				$partitionAccessPath = [string]$candidate[0]
			}
		}
		$fsutilMeta = Get-VolumeFsInfoFromPath -Path $partitionAccessPath

		$volume = $null
		try {
			$volume = $partition | Get-Volume -ErrorAction Stop
		}
		catch {
			$volume = $null
		}

		$volumeLabel = $null
		$driveLetter = $null
		$fileSystemType = $null

		if ($volume) {
			$volumeLabel = [string]$volume.FileSystemLabel
			if ($volume.DriveLetter) {
				$driveLetter = [string]$volume.DriveLetter
			}
			$fileSystemType = [string]$volume.FileSystemType
		}

		if ($diskpartMeta) {
			if ([string]::IsNullOrWhiteSpace($volumeLabel) -and -not [string]::IsNullOrWhiteSpace([string]$diskpartMeta.VolumeLabel)) {
				$volumeLabel = [string]$diskpartMeta.VolumeLabel
			}
			if ([string]::IsNullOrWhiteSpace($driveLetter) -and -not [string]::IsNullOrWhiteSpace([string]$diskpartMeta.DriveLetter)) {
				$driveLetter = [string]$diskpartMeta.DriveLetter
			}
			if ([string]::IsNullOrWhiteSpace($fileSystemType) -and -not [string]::IsNullOrWhiteSpace([string]$diskpartMeta.FileSystemType)) {
				$fileSystemType = [string]$diskpartMeta.FileSystemType
			}
		}

		if ([string]::IsNullOrWhiteSpace($volumeLabel) -and -not [string]::IsNullOrWhiteSpace([string]$fsutilMeta.VolumeLabel)) {
			$volumeLabel = [string]$fsutilMeta.VolumeLabel
		}
		if ([string]::IsNullOrWhiteSpace($fileSystemType) -and -not [string]::IsNullOrWhiteSpace([string]$fsutilMeta.FileSystemType)) {
			$fileSystemType = [string]$fsutilMeta.FileSystemType
		}

		# ESP volumes are expected to be FAT32 and often have no mounted volume metadata.
		if ([string]::IsNullOrWhiteSpace($fileSystemType)) {
			$fileSystemType = "FAT32"
		}
		if ([string]::IsNullOrWhiteSpace($volumeLabel)) {
			$volumeLabel = ("D{0}P{1}" -f $partition.DiskNumber, $partition.PartitionNumber)
		}

		$efiPartitions += [ordered]@{
			DiskNumber        = $partition.DiskNumber
			PartitionNumber   = $partition.PartitionNumber
			PartitionTypeGuid = $partition.GptType
			PartitionType     = $partition.Type
			IsSystem          = [bool]$partition.IsSystem
			IsBoot            = if ($diskpartMeta -and $diskpartMeta.IsBoot -ne $null) { [bool]$diskpartMeta.IsBoot } else { [bool]$partition.IsBoot }
			VolumeLabel       = $volumeLabel
			DriveLetter       = $driveLetter
			FileSystemType    = $fileSystemType
			IsActiveHint      = if ($diskpartMeta) { $diskpartMeta.IsActive } else { $null }
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

	function Resolve-BcdDevicePath {
		param([string]$Text)

		$deviceMatch = [regex]::Match($Text, "(?im)^\s*device\s+(.+)$")
		$pathMatch = [regex]::Match($Text, "(?im)^\s*path\s+(.+)$")

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

	if (-not [string]::IsNullOrWhiteSpace($BcdText)) {
		$resolvedFromInput = Resolve-BcdDevicePath -Text $BcdText
		if (-not [string]::IsNullOrWhiteSpace($resolvedFromInput)) {
			return $resolvedFromInput
		}
	}

	$bcdExe = Join-Path $env:WINDIR 'System32\bcdedit.exe'
	$candidateIds = @('{current}', '{default}', '{bootmgr}')
	foreach ($id in $candidateIds) {
		try {
			$candidateText = & $bcdExe '/enum' $id 2>&1 | Out-String
			if ($LASTEXITCODE -ne 0) {
				continue
			}
			$resolved = Resolve-BcdDevicePath -Text $candidateText
			if (-not [string]::IsNullOrWhiteSpace($resolved)) {
				return $resolved
			}
		}
		catch {
			continue
		}
	}

	try {
		$allText = & $bcdExe '/enum' 'all' 2>&1 | Out-String
		if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($allText)) {
			$bootmgrBlock = [regex]::Match($allText, '(?ims)identifier\s+\{bootmgr\}.*?(?=\r?\n\r?\n|$)')
			if ($bootmgrBlock.Success) {
				$resolvedBootmgr = Resolve-BcdDevicePath -Text $bootmgrBlock.Value
				if (-not [string]::IsNullOrWhiteSpace($resolvedBootmgr)) {
					return $resolvedBootmgr
				}
			}
		}
	}
	catch {
		# fall through to null if parsing fails
	}

	return $null
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
	$activeByHint = $EfiPartitions | Where-Object { $_.IsActiveHint -eq $true } | Select-Object -First 1
	if ($activeByHint) {
		$active = $activeByHint
	}
	$bootLoaderPath = Get-BootLoaderPathFromCurrentBcd -BcdText $BcdText
	$defaultBootLoaderPath = '\\EFI\\Microsoft\\Boot\\bootmgfw.efi'
	if ([string]::IsNullOrWhiteSpace($bootLoaderPath)) {
		if ($active -and -not [string]::IsNullOrWhiteSpace([string]$active.DriveLetter)) {
			$bootLoaderPath = ('{0}:{1}' -f [string]$active.DriveLetter, $defaultBootLoaderPath)
		}
		else {
			$bootLoaderPath = $defaultBootLoaderPath
		}
	}

	$normalizedAll = @()
	foreach ($partition in $EfiPartitions) {
		$isActive = $false
		if ($active -and $partition.DiskNumber -eq $active.DiskNumber -and $partition.PartitionNumber -eq $active.PartitionNumber) {
			$isActive = $true
		}

		$normalizedAll += [ordered]@{
			DiskNumber        = $partition.DiskNumber
			PartitionNumber   = $partition.PartitionNumber
			PartitionTypeGuid = $partition.PartitionTypeGuid
			PartitionType     = $partition.PartitionType
			IsSystem          = [bool]$partition.IsSystem
			IsBoot            = [bool]$partition.IsBoot
			IsActive          = $isActive
			VolumeLabel       = $partition.VolumeLabel
			DriveLetter       = $partition.DriveLetter
			FileSystemType    = $partition.FileSystemType
		}
	}

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
		All = $normalizedAll
		Active = $activeState
	}
}

Export-ModuleMember -Function Get-EspPartitions, Get-ActiveEspPartition, Get-BootLoaderPathFromCurrentBcd, Get-EspIdentitySnapshot


