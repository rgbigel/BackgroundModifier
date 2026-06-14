<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     ErrorTools.psm1
    Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides simple error collection and reporting utilities.
============================================================================================ #>

$script:Errors = @()

function Add-ErrorMessage {
    param(
        [string]$Message
    )

    $script:Errors += $Message
}

function Get-Errors {
    return $script:Errors
}

