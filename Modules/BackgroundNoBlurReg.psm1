# =================================================================================================
#  Module:      BackgroundNoBlurReg.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  --------  Added registry helper functions to manage logon background blur behavior
# =================================================================================================

function Set-NoBlur {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $regName = "DisableAcrylicBackgroundOnLogon"
    $regValue = 1

    # Check if the registry key exists
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Set the policy value to disable acrylic blur while keeping background image enabled
    Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Force
}

function Remove-NoBlur {
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    $regName = "DisableAcrylicBackgroundOnLogon"

    # Check if the registry key exists and remove it
    if (Test-Path $regPath) {
        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    }
}

# Export the functions for use in other scripts
Export-ModuleMember -Function Set-NoBlur, Remove-NoBlur


