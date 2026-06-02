# =================================================================================================
#  Module:      TimeTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\TimeTools.psm1
  Module:     TimeTools.psm1
  Version:    6.0.0
  Author:     Rolf Bercht

  Purpose:
      Deterministic helpers for timestamp generation, run-ID creation,
      and time-based workflow utilities.

   Change Log:
       Version 1.001 27.02.26 16:16
          Initial module creation, aligned to new VSCode structure.
============================================================================================ #>

function Get-RunTimestamp {
    return (Get-Date -Format "yyyyMMdd_HHmmss")
}

function Get-ShortDate {
    return (Get-Date -Format "yyyy-MM-dd")
}

function Get-RunId {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    return "RUN_$ts"
}

function Measure-Block {
    param([scriptblock]$Action)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Action
    $sw.Stop()

    return [PSCustomObject]@{
        Milliseconds = $sw.ElapsedMilliseconds
        Seconds      = [math]::Round($sw.Elapsed.TotalSeconds, 3)
    }
}
    Export-ModuleMember -Function *


