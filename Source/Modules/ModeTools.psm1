<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules
  Module:     ModeTools.psm1
  Version:    7.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides helpers for handling Debug and Trace modes.
============================================================================================ #>

function Apply-DebugMode {
    param(
        [switch]$DebugMode
    )

    if ($DebugMode) {
        $DebugPreference   = "Continue"
        $VerbosePreference = "Continue"
    }
}

