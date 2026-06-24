<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     ErrorTools.psm1
    Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides simple error collection and reporting utilities.

  Caller Contract (Module-Caller State Update Responsibility):
    This module collects errors in a script-local array. Caller is responsible for:
    - Add-ErrorMessage: Accumulate errors during phase execution
    - Get-ErrorCount / Get-ErrorMessages: Retrieve errors before phase completion
    - Caller MUST write critical errors to state.json diagnostics section:
      * diagnostics.lastCriticalError (full error details)
      * diagnostics.lastCriticalErrorAtUtc (timestamp)
      * diagnostics.lastCriticalErrorPhase (phase identifier)
      * diagnostics.lastCriticalErrorComponent (component name + version)
      * diagnostics.userVisibleErrorMessage (human-readable for end user, non-technical)
    - If error occurs: Caller blocks phase, updates state, logs with version, exits with error code
============================================================================================ #>

$script:Errors = @()

function Add-ErrorMessage {
    [CmdletBinding()]
    param(
        [string]$Message
    )

    $script:Errors += $Message
}

function Get-Errors {
    [CmdletBinding()]
    param()

    return $script:Errors
}

