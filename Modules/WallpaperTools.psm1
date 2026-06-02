# =================================================================================================
#  Module:      WallpaperTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\WallpaperTools.psm1
  Module:     WallpaperTools.psm1
  Version:    6.0.0
  Author:     Rolf Bercht

  Purpose:
      Deterministic helpers for setting Windows wallpapers without side effects.
      Isolated from renderer and installer to maintain strict module boundaries.

   Change Log:
       Version 1.001 27.02.26 16:12
          Initial module creation, aligned to new VSCode structure.
============================================================================================ #>

Add-Type @"
using System.Runtime.InteropServices;

public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

function Set-Wallpaper {
    param([string]$ImagePath)

    if (-not (Test-Path $ImagePath)) {
        Write-Host "[ERROR] Wallpaper image not found: $ImagePath"
        return
    }

    $SPI_SETDESKWALLPAPER = 0x0014
    $SPIF_UPDATEINIFILE   = 0x01
    $SPIF_SENDWININICHANGE = 0x02

    try {
        [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $ImagePath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE) | Out-Null
        Write-Host "[OK] Wallpaper applied -> $ImagePath"
    }
    catch {
        Write-Host "[ERROR] Failed to set wallpaper: $($_.Exception.Message)"
    }
}
    Export-ModuleMember -Function *


