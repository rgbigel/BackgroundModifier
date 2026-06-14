<#
    Module: SetFlagsTool.psm1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Provide invariant -t / -d flag handling for all operator-facing scripts and flag-aware modules.
#>

function Set-Flags {
    param(
        [switch]$T,
        [switch]$D
    )

    $result = [ordered]@{
        TraceMode = $false
        DebugMode = $false
    }

    if ($T) {
        $result.TraceMode = $true
        $result.DebugMode = $true
    }

    if ($D) {
        $result.DebugMode = $true
    }

    return $result
}

