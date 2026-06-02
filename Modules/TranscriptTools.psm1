# =================================================================================================
#  Module:      TranscriptTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  --------  Reconciled module purpose; added transcript path/start/stop helpers
# =================================================================================================

function Get-TranscriptPath {
    [CmdletBinding()]
    param(
        [string]$LogRoot = $Global:LogRoot,
        [string]$Prefix = 'Session'
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot)) {
        $LogRoot = 'C:\BootOpsHub\logs'
    }

    $transcriptRoot = Join-Path $LogRoot 'transcripts'
    if (-not (Test-Path -LiteralPath $transcriptRoot)) {
        New-Item -Path $transcriptRoot -ItemType Directory -Force | Out-Null
    }

    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    return (Join-Path $transcriptRoot ("{0}_{1}.log" -f $Prefix, $stamp))
}

function Start-ToolTranscript {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$LogRoot = $Global:LogRoot,
        [string]$Prefix = 'Session',
        [switch]$PassThru
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-TranscriptPath -LogRoot $LogRoot -Prefix $Prefix
    }

    Start-Transcript -Path $Path -Force | Out-Null
    if ($PassThru) {
        return $Path
    }
}

function Stop-ToolTranscript {
    [CmdletBinding()]
    param()

    try {
        Stop-Transcript | Out-Null
    }
    catch {
    }
}

Export-ModuleMember -Function Get-TranscriptPath, Start-ToolTranscript, Stop-ToolTranscript


