<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
    Module:     RuntimeStateTools.psm1
    Version:    8.0.1
    Author:     Rolf Bercht

    Purpose:
        Provides utility functions for runtime state management and object manipulation.
        Shared functions used by both BackgroundRenderer and BackgroundSetter.
============================================================================================ #>

function Set-ObjectProperty {
    <#
    .SYNOPSIS
        Sets or adds a property on a PSCustomObject.
    .DESCRIPTION
        Updates existing property or adds new property via Add-Member if needed.
        Allows dynamic property updates without error checking.
    .PARAMETER Object
        Target object to modify.
    .PARAMETER Name
        Property name.
    .PARAMETER Value
        Property value.
    .OUTPUTS
        None. Modifies object in-place.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-RuntimeState {
    <#
    .SYNOPSIS
        Reads runtime state from state file using RuntimeContext.
    .DESCRIPTION
        Wrapper for Read-RuntimeState module function with RuntimeContext binding.
        Requires $RuntimeContext variable to be in calling scope.
    .PARAMETER StateFilePath
        Path to state file.
    .OUTPUTS
        [PSCustomObject] containing persisted runtime state.
    #>
    param(
        [string]$StateFilePath
    )

    return Read-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath
}

function Save-RuntimeState {
    <#
    .SYNOPSIS
        Persists runtime state to state file using RuntimeContext with change detection.
    .DESCRIPTION
        Compares new state to existing file content before writing.
        Only persists if state has changed (prevents unnecessary I/O and elevation).
        Logs mutation via Write-MutationLog callback only when write occurs.
        In trace mode, also logs when state is unchanged (no-op skipped).
        Requires $RuntimeContext variable to be in calling scope.
    .PARAMETER StateFilePath
        Path to state file.
    .PARAMETER StateObject
        Runtime state object to persist.
    .PARAMETER TraceMode
        When true, logs no-op operations (unchanged state) to assist debugging.
    .OUTPUTS
        [bool] $true if state was written or unchanged (always success).
    #>
    param(
        [string]$StateFilePath,
        [object]$StateObject,
        [bool]$TraceMode = $false
    )

    # Serialize new state to JSON
    $newStateJson = $StateObject | ConvertTo-Json -Depth 10 -Compress

    # Read existing state if file exists
    $stateChanged = $true
    if (Test-Path $StateFilePath) {
        try {
            $existingStateJson = Get-Content -Path $StateFilePath -Raw -ErrorAction SilentlyContinue
            if ($null -ne $existingStateJson) {
                $stateChanged = ($newStateJson -ne $existingStateJson)
            }
        }
        catch {
            # If read fails, assume state changed (safe default)
            $stateChanged = $true
        }
    }

    # Only persist if state actually changed
    if ($stateChanged) {
        $result = Write-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath -StateObject $StateObject -OnPersist {
            param($persistedPath)
            Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
        }
        return $result
    }
    else {
        # State unchanged - no-op. In trace mode, log this decision.
        if ($TraceMode) {
            Write-Host "[TRACE] State unchanged - skipped I/O write to $StateFilePath"
        }
        return $true
    }
}

Export-ModuleMember -Function @(
    'Set-ObjectProperty',
    'Get-RuntimeState',
    'Save-RuntimeState'
)
