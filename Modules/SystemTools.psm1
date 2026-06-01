# =================================================================================================
#  Module:      SystemTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\SystemTools.psm1
  Module:     SystemTools.psm1
$16.0.0
  Author:     Rolf Bercht

  Purpose:
      Minimal, deterministic system-level helpers.
      Reserved for environment checks, OS capability detection,
      and future expansion of system-integration logic.

   Change Log:
       Version 1.001 27.02.26 16:18
          Initial module creation, aligned to new VSCode structure.
============================================================================================ #>

function Get-OSInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    return [PSCustomObject]@{
        Caption      = $os.Caption
        Version      = $os.Version
        BuildNumber  = $os.BuildNumber
        Architecture = $os.OSArchitecture
    }
}

function Test-IsWindows {
    return $IsWindows
}

function Get-UserName {
    return $env:USERNAME
}

function Get-ComputerName {
    return $env:COMPUTERNAME
}
Export-ModuleMember -Function *

