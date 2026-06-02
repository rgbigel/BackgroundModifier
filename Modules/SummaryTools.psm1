# =================================================================================================
#  Module:      SummaryTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\SummaryTools.psm1
  Module:     SummaryTools.psm1
  Version:    6.0.0
  Author:     Rolf Bercht

  Purpose:
      Small helpers for consistent end-of-run summaries.

   Change Log:
       Version 1.001 27.02.26 15:54
          Header updated, version incremented, aligned to new VSCode structure.
============================================================================================ #>

function Show-Summary {
    param([string]$Message)
    Write-Host "[SUMMARY] $Message"
}
Export-ModuleMember -Function *


