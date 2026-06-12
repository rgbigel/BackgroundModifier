<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules
  Module:     PathTools.psm1
  Version:    7.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides helper functions for working with paths and directories.
============================================================================================ #>

function Ensure-Directory {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

