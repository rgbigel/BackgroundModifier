<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     SummaryTools.psm1
    Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides helper functions for printing summary sections in scripts.

  Caller Contract: Read-only display utility module. No state implications.
============================================================================================ #>

function Write-SummaryHeader {
    [CmdletBinding()]
    param([string]$Title)

    Write-Host "=== $Title ==="
}

function Write-SummaryItem {
    [CmdletBinding()]
    param([string]$Message)

    Write-Host " - $Message"
}

Export-ModuleMember -Function Write-SummaryHeader, Write-SummaryItem

