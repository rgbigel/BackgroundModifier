# =================================================================================================
#  Module:      Disable.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Added explicit disable operation for scheduled automation.
# =================================================================================================

param(
    [switch]$t
)

$scriptItem = Get-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
$resolvedScriptPath = $PSCommandPath
if ($scriptItem -and $scriptItem.LinkType -eq "SymbolicLink" -and $scriptItem.Target) {
    $resolvedScriptPath = [string]$scriptItem.Target
}
$ScriptRootResolved = Split-Path -Parent ([System.IO.Path]::GetFullPath($resolvedScriptPath))
$RepoRootResolved = Split-Path -Parent $ScriptRootResolved
$ModuleRoot = Join-Path $RepoRootResolved "Modules"

Import-Module (Join-Path $ModuleRoot "InstallerTools.psm1") -Force

$TraceMode = [bool]$t
$DebugMode = [bool]$t

Write-Host "=== BackgroundModifier Disable.ps1 (v6.0.0) ==="
if ($DebugMode) { Write-Host "Debug mode enabled" }

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier Disable.ps1 help" -UsageLines @(
        "Usage: Disable.ps1 [-t]",
        "  -t: Trace mode (implies debug mode for richer diagnostics).",
        "Use /?, /H, or -Help to show this message.",
        "Requires administrator privileges."
    )
    exit 0
}

Require-Admin

$taskNames = @(
    "BackgroundModifier-BootIdentity",
    "BackgroundModifier-Autorun"
)

$disabledCount = 0

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "[WARN] Task not found: $taskName"
        continue
    }

    try {
        Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
        Write-Host "[OK] Disabled task: $taskName"
        $disabledCount++
    }
    catch {
        Write-Host "[ERROR] Failed to disable task '$taskName': $($_.Exception.Message)"
    }
}

Write-Host "[OK] Disable operation completed. Tasks disabled: $disabledCount"

Wait-ForInstallerExit -Pause:($DebugMode -or $TraceMode) -Message "Disable completed. Press Enter to exit..."


