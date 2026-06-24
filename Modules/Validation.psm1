<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     Validation.psm1
    Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides reusable validation helpers for scripts and modules.

  Caller Contract: Read-only validation utility module. Validation failures should be logged by caller with component $Version (Requirement #15).
============================================================================================ #>

function Test-FileExists {
    param(
        [string]$Path
    )

    return (Test-Path $Path)
}

