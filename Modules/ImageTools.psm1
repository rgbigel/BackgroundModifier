# =================================================================================================
#  Module:      ImageTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     5.000
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
    Export-ModuleMember -Function *
