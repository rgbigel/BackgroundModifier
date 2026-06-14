<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     TranscriptTools.psm1
    Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides helper functions for starting and stopping transcripts.
============================================================================================ #>

function Start-TraceTranscript {
    param(
        [string]$Path
    )

    Start-Transcript -Path $Path -Append | Out-Null
}

function Stop-TraceTranscript {
    Stop-Transcript | Out-Null
}

