<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\ErrorTools.psm1
  Module:     ErrorTools.psm1
$16.0.0
  Author:     Rolf Bercht

  Purpose:
      Centralized, deterministic errorâ€‘handling helpers.
      Ensures consistent formatting, predictable exit behavior,
      and clean separation between error signalling and logging.

   Change Log:
       Version 1.001 27.02.26 16:24
          Initial module creation, aligned to new VSCode structure.
============================================================================================ #>

function Throw-Error {
    param([string]$Message)

    Write-Host "[ERROR] $Message"
    throw $Message
}

function Fail-IfNull {
    param(
        [object]$Value,
        [string]$Name = "Value"
    )

    if ($null -eq $Value) {
        Throw-Error "$Name is null or missing."
    }
}

function Fail-IfFalse {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        Throw-Error $Message
    }
}

