# =================================================================================================
#  Module:      BackgroundStateMgr.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
#      5.000  --------  Added state management functions for reading/updating/clearing State.json
# =================================================================================================

function Get-BackgroundState {
    param (
        [string]$StateFilePath
    )

    if (-Not (Test-Path $StateFilePath)) {
        throw "State file not found at path: $StateFilePath"
    }

    $state = Get-Content -Path $StateFilePath | ConvertFrom-Json
    return $state
}

function Update-BackgroundState {
    param (
        [string]$StateFilePath,
        [hashtable]$NewData
    )

    if (-Not (Test-Path $StateFilePath)) {
        throw "State file not found at path: $StateFilePath"
    }

    $state = Get-Content -Path $StateFilePath | ConvertFrom-Json

    foreach ($key in $NewData.Keys) {
        $state.PSObject.Properties[$key].Value = $NewData[$key]
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content -Path $StateFilePath
}

function Clear-BackgroundState {
    param (
        [string]$StateFilePath
    )

    if (Test-Path $StateFilePath) {
        Remove-Item $StateFilePath -Force
    }
}

Export-ModuleMember -Function Get-BackgroundState, Update-BackgroundState, Clear-BackgroundState
