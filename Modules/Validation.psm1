# =================================================================================================
#  Module:      Validation.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\Validation.psm1
  Module:     Validation.psm1
  Version:    5.000
  Author:     Rolf Bercht

  Purpose:
      Lightweight validation helpers for files, folders, and inputs.

   Change Log:
       Version 1.001 27.02.26 15:50
          Header updated, version incremented, aligned to new VSCode structure.
============================================================================================ #>

function Test-FileExists {
    param([string]$Path)
    return (Test-Path $Path)
}

function Test-FolderExists {
    param([string]$Path)
    return (Test-Path $Path)
}

function Require-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Required file missing: $Path"
        exit 1
    }
}

function Require-Folder {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Required folder missing: $Path"
        exit 1
    }
}
    Export-ModuleMember -Function *
