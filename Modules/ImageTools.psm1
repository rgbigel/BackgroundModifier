# =================================================================================================
#  Module:      ImageTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     8.0.1
#  Purpose:     Additional image-related helpers used by renderer and installer.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (image rendering)
# =================================================================================================

function Test-Image {
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


