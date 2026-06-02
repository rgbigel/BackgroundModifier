# =================================================================================================
#  Module:      TaskTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\TaskTools.psm1
  Module:     TaskTools.psm1
  Version:    6.0.0
  Author:     Rolf Bercht

  Purpose:
      Internal helpers for task-oriented orchestration steps.
      Currently minimal by design, reserved for future workflow expansion.

   Change Log:
       Version 1.001 27.02.26 16:06
          Initial module creation, aligned to new VSCode structure.
============================================================================================ #>

function Invoke-TaskStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host "[TASK] $Name"
    try {
        & $Action
        Write-Host "[OK] $Name completed"
    }
    catch {
        Write-Host "[ERROR] $Name failed: $($_.Exception.Message)"
        exit 1
    }
}
    Export-ModuleMember -Function *


