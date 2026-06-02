# =================================================================================================
#  Module:      SetFlagsTool.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  --------  Reconciled module purpose; added command-line flag parsing via Set-Flags
# =================================================================================================

function Set-Flags {
    [CmdletBinding()]
    param(
        [switch]$T,

        [switch]$V
    )

    $traceMode = [bool]$T
    $debugMode = $traceMode
    $verboseMode = [bool]$V

    $mode = 'normal'
    if ($traceMode) {
        $mode = 'trace'
    }
    elseif ($debugMode) {
        $mode = 'debug'
    }

    return [PSCustomObject]@{
        TraceMode   = $traceMode
        DebugMode   = $debugMode
        VerboseMode = $verboseMode
        Mode        = $mode
    }
}

Export-ModuleMember -Function Set-Flags


