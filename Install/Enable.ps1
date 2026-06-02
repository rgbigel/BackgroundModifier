# =================================================================================================
#  Module:      Enable.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Added explicit enable operation for scheduled automation.
# =================================================================================================

param(
    [switch]$t,
    [switch]$d
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
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force

$flags = Set-Flags -T:$t -D:$d
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

Write-Host "=== BackgroundModifier Enable.ps1 (v6.0.0) ==="
if ($DebugMode) { Write-Host "Debug mode enabled" }

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier Enable.ps1 help" -UsageLines @(
        "Usage: Enable.ps1 [-t] [-d]",
        "  -t: Trace mode (implies debug mode for richer diagnostics).",
        "  -d: Debug mode (verbose console diagnostics and pause-on-exit in interactive runs).",
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

$enabledCount = 0

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "[WARN] Task not found: $taskName"
        continue
    }

    try {
        Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
        Write-Host "[OK] Enabled task: $taskName"
        $enabledCount++
    }
    catch {
        Write-Host "[ERROR] Failed to enable task '$taskName': $($_.Exception.Message)"
    }
}

Write-Host "[OK] Enable operation completed. Tasks enabled: $enabledCount"

Wait-ForInstallerExit -Pause:($DebugMode -or $TraceMode) -Message "Enable completed. Press Enter to exit..."

