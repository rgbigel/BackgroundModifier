# =================================================================================================
#  Module:      ImageTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     8.0.1
#  Purpose:     Additional image-related helpers used by renderer and installer.
#
#  Caller Contract (Module-Caller State Update Responsibility):
#    This module validates and processes images but does NOT modify state.json. Caller is responsible for:
#    - Test-Image: Safe to call; read-only validation, no state changes needed
#    - Any output path returned: Caller must verify and update state.json if image paths affect rendering state
#    - This module does NOT touch state.json; caller owns artifact tracking and state consistency
#
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (image rendering)
# =================================================================================================

function Test-Image {
    [CmdletBinding()]
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Image not found: $Path"
        return $false
    }

    try {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($Path)
        $img.Dispose()
        return $true
    }
    catch {
        Write-Host "[ERROR] Invalid or unreadable image: $Path"
        return $false
    }
}

function Get-ImageSize {
    [CmdletBinding()]
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Image not found: $Path"
        return $null
    }

    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($Path)

    $size = [PSCustomObject]@{
        Width  = $img.Width
        Height = $img.Height
    }

    $img.Dispose()
    return $size
}

function Get-CurrentDesktopWallpaperPath {
    [CmdletBinding()]
    param()

    <#
    .SYNOPSIS
        Retrieves the path to the current desktop wallpaper.
    .DESCRIPTION
        Queries registry for user wallpaper setting, checks TranscodedWallpaper fallback.
        Returns null if no wallpaper found or accessible.
    .OUTPUTS
        [string] Path to current wallpaper or $null if unavailable.
    #>

    $wallpaperPath = ""

    try {
        $wallpaperPath = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -ErrorAction SilentlyContinue)
    }
    catch {
        $wallpaperPath = ""
    }

    if ($wallpaperPath -and (Test-Path $wallpaperPath)) {
        return $wallpaperPath
    }

    $transcoded = Join-Path $env:APPDATA "Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path $transcoded) {
        return $transcoded
    }

    return $null
}

    Export-ModuleMember -Function *


