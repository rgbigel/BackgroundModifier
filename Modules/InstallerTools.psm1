# =================================================================================================
#  Module:      InstallerTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Shared helper functions used by installation and setup scripts.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (installation utilities)
# =================================================================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Test-Admin)) {
        Write-Host "[ERROR] Administrator rights required."
        exit 1
    }
}

function Copy-Safe {
    param(
        [string]$Source,
        [string]$Destination
    )
    Copy-Item -Path $Source -Destination $Destination -Force
}
    Export-ModuleMember -Function *

