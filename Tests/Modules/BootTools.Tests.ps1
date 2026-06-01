$modulePath = Join-Path $PSScriptRoot "..\..\Modules\BootTools.psm1"
Import-Module $modulePath -Force

Describe "BootTools" {
    It "exports expected functions" {
        Get-Command Get-EspPartitions -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Get-ActiveEspPartition -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Get-BootLoaderPathFromCurrentBcd -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Get-EspIdentitySnapshot -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "selects active ESP by IsSystem" {
        $all = @(
            [pscustomobject]@{ DiskNumber = 4; PartitionNumber = 2; IsSystem = $false; VolumeLabel = "EFID4P0-WDB"; DriveLetter = $null },
            [pscustomobject]@{ DiskNumber = 0; PartitionNumber = 1; IsSystem = $true; VolumeLabel = "D0-ESP"; DriveLetter = $null }
        )

        $active = Get-ActiveEspPartition -EfiPartitions $all

        $active.DiskNumber | Should Be 0
        $active.PartitionNumber | Should Be 1
    }

    It "falls back to first ESP when none marked IsSystem" {
        $all = @(
            [pscustomobject]@{ DiskNumber = 9; PartitionNumber = 1; IsSystem = $false; VolumeLabel = "ESP-A"; DriveLetter = $null },
            [pscustomobject]@{ DiskNumber = 10; PartitionNumber = 1; IsSystem = $false; VolumeLabel = "ESP-B"; DriveLetter = $null }
        )

        $active = Get-ActiveEspPartition -EfiPartitions $all

        $active.DiskNumber | Should Be 9
        $active.PartitionNumber | Should Be 1
    }

    It "parses boot loader path from BCD text" {
        $bcdText = @"
Windows Boot Loader
-------------------
identifier              {current}
device                  partition=C:
path                    \WINDOWS\system32\winload.efi
"@

        $path = Get-BootLoaderPathFromCurrentBcd -BcdText $bcdText
        $path | Should Be "partition=C:\WINDOWS\system32\winload.efi"
    }

    It "returns null boot loader path when BCD fields are missing" {
        $bcdText = @"
Windows Boot Loader
-------------------
identifier              {current}
"@

        $path = Get-BootLoaderPathFromCurrentBcd -BcdText $bcdText
        $path | Should Be $null
    }

    It "composes ESP identity snapshot from provided data" {
        $all = @(
            [pscustomobject]@{ DiskNumber = 0; PartitionNumber = 1; IsSystem = $true; VolumeLabel = "D0-ESP"; DriveLetter = $null },
            [pscustomobject]@{ DiskNumber = 4; PartitionNumber = 2; IsSystem = $false; VolumeLabel = "EFID4P0-WDB"; DriveLetter = $null }
        )

        $bcdText = @"
Windows Boot Loader
-------------------
identifier              {current}
device                  partition=C:
path                    \WINDOWS\system32\winload.efi
"@

        $snapshot = Get-EspIdentitySnapshot -EfiPartitions $all -BcdText $bcdText

        $snapshot.All.Count | Should Be 2
        $snapshot.Active.DiskNumber | Should Be 0
        $snapshot.Active.PartitionNumber | Should Be 1
        $snapshot.Active.BootLoaderPath | Should Be "partition=C:\WINDOWS\system32\winload.efi"
    }
}
