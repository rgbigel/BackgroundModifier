<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
    Module:     ImageStateTools.psm1
    Version:    8.0.1
    Author:     Rolf Bercht

    Purpose:
        Provides image state and base image restoration functions used by both 
        BackgroundRenderer and BackgroundSetter for desktop/logon image management.
        Atomic functions for image comparison and restoration.

  Caller Contract (Module-Caller State Update Responsibility):
    This module manages image artifacts and state but does NOT modify state.json. Caller must:
    - Get-ImageState: Safe to call; read-only queries image file state
    - Restore-ImageBase: Modifies image files; caller must THEN:
      * Update state.json render section with new image paths
      * Update state.json with restoration timestamp and source (appliedAtUtc, appliedByPhase)
    - On successful restoration: Caller must track desktopImageHash and logonImageHash in state
    - This module manages artifacts (files); StateTools manages metadata (state.json)
============================================================================================ #>

function Get-ImageState {
    [CmdletBinding()]
    param(
        [string]$DesktopImage,
        [string]$DesktopBase,
        [string]$DesktopRendered,
        [string]$LogonImage,
        [string]$LogonBase,
        [string]$LogonRendered
    )

    <#
    .SYNOPSIS
        Analyzes current state of desktop and logon images.
    .DESCRIPTION
        Compares user images against rendered and base versions.
        Returns detailed PSCustomObject with existence and match status.
    .PARAMETER DesktopImage
        Path to current desktop image.
    .PARAMETER DesktopBase
        Path to desktop base image.
    .PARAMETER DesktopRendered
        Path to desktop rendered image.
    .PARAMETER LogonImage
        Path to current logon image.
    .PARAMETER LogonBase
        Path to logon base image.
    .PARAMETER LogonRendered
        Path to logon rendered image.
    .OUTPUTS
        [PSCustomObject] with properties: DesktopImageExists, DesktopBaseExists, etc., 
        and computed flags: UserChangedDesktop, UserChangedLogon
    #>

    $desktopMatchesRendered = Test-FileContentEqual -PathA $DesktopImage -PathB $DesktopRendered
    $desktopMatchesBase = Test-FileContentEqual -PathA $DesktopImage -PathB $DesktopBase
    $logonMatchesRendered = Test-FileContentEqual -PathA $LogonImage -PathB $LogonRendered
    $logonMatchesBase = Test-FileContentEqual -PathA $LogonImage -PathB $LogonBase

    return [pscustomobject]@{
        DesktopImageExists = (Test-Path $DesktopImage)
        DesktopBaseExists = (Test-Path $DesktopBase)
        DesktopRenderedExists = (Test-Path $DesktopRendered)
        LogonImageExists = (Test-Path $LogonImage)
        LogonBaseExists = (Test-Path $LogonBase)
        LogonRenderedExists = (Test-Path $LogonRendered)
        DesktopMatchesRendered = $desktopMatchesRendered
        DesktopMatchesBase = $desktopMatchesBase
        LogonMatchesRendered = $logonMatchesRendered
        LogonMatchesBase = $logonMatchesBase
        UserChangedDesktop = ((Test-Path $DesktopImage) -and (Test-Path $DesktopRendered) -and -not $desktopMatchesRendered)
        UserChangedLogon = ((Test-Path $LogonImage) -and (Test-Path $LogonRendered) -and -not $logonMatchesRendered)
    }
}

function Restore-BaseFromCurrentImage {
    [CmdletBinding()]
    param(
        [string]$BasePath,
        [string]$CurrentImagePath,
        [string]$Label
    )

    <#
    .SYNOPSIS
        Restores a base image from current image if base is missing.
    .DESCRIPTION
        Copies current image to base path if base doesn't exist.
        Used during initialization to establish base images.
    .PARAMETER BasePath
        Destination path for base image.
    .PARAMETER CurrentImagePath
        Source path for current image.
    .PARAMETER Label
        Human-readable label (Desktop/Logon) for logging.
    .OUTPUTS
        [bool] True if restored or already exists, false if current image missing.
    #>

    if (Test-Path $BasePath) {
        return $true
    }

    if (-not (Test-Path $CurrentImagePath)) {
        return $false
    }

    try {
        Copy-Item -Path $CurrentImagePath -Destination $BasePath -Force
        Write-Host "[OK] Restored $Label base from current image -> $BasePath"
        return $true
    }
    catch {
        Write-Host "[X] Failed restoring $Label base from current image: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function @(
    'Get-ImageState',
    'Restore-BaseFromCurrentImage'
)
