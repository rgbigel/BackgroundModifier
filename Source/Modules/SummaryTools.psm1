<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules
  Module:     SummaryTools.psm1
  Version:    7.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides helper functions for printing summary sections in scripts.
============================================================================================ #>

function Write-SummaryHeader {
    param([string]$Title)

    Write-Host "=== $Title ==="
}

function Write-SummaryItem {
    param([string]$Message)

    Write-Host " - $Message"
}

Export-ModuleMember -Function Write-SummaryHeader, Write-SummaryItem

