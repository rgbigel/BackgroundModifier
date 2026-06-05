# =================================================================================================
#  Module:      Cleanup.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Converted to maintenance-only cleanup and aligned module root to top-level Modules.
#      5.000  --------  Initial module creation for Consolidated Architecture (cleanup utility)
# =================================================================================================

param(
    [switch]$t,
    [switch]$f,
    [Alias('c')]
    [string]$CmdRoot = "D:\OneDrive\cmd"
)

$scriptItem = Get-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
$resolvedScriptPath = $PSCommandPath
if ($scriptItem -and $scriptItem.LinkType -eq "SymbolicLink" -and $scriptItem.Target) {
    $resolvedScriptPath = [string]$scriptItem.Target
}
$ScriptRootResolved = Split-Path -Parent ([System.IO.Path]::GetFullPath($resolvedScriptPath))
$RepoRoot = Split-Path $ScriptRootResolved -Parent
$ModuleRoot = Join-Path $RepoRoot "Modules"

Import-Module (Join-Path $ModuleRoot "InstallerTools.psm1") -Force

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier Cleanup.ps1 help" -UsageLines @(
        "Usage: Cleanup.ps1 [-t] [-f] [-CmdRoot <path>]",
        "  -t: Removes test links from CmdRoot during cleanup.",
        "  -f: Full log cleanup; removes all log files instead of only older logs.",
        "  -CmdRoot (-c): Folder where test links are removed when -t is used.",
        "Use /?, /H, or -Help to show this message.",
        "This is a maintenance-only operation and does not require elevation."
    )
    exit 0
}

# Runtime root is explicitly outside the repo
$RuntimeRoot = "C:\BootOpsHub"
$RenderRoot  = Join-Path $RuntimeRoot "rendered"
$LogRoot     = Join-Path $RuntimeRoot "logs"

Write-Host "=== BackgroundModifier Cleanup (Maintenance Only) ==="

if (-not (Test-Path -LiteralPath $ModuleRoot)) {
    Write-Host "[ERROR] Module root not found: $ModuleRoot"
    exit 1
}

$CleanupModule = Join-Path $ModuleRoot "CleanupTools.psm1"
if (Test-Path -LiteralPath $CleanupModule) {
    Import-Module $CleanupModule -Force

    Write-Host "`n=== Running CleanupTools against C:\BootOpsHub (logs + rendered) ==="

    Clear-RenderFolder -RenderRoot $RenderRoot
    if ($f) {
        Remove-OldLogs -LogRoot $LogRoot -Full
    }
    else {
        Remove-OldLogs -LogRoot $LogRoot -Days 7
    }

    if ($t) {
        Remove-TestLinks -CmdRoot $CmdRoot
    }
}
else {
    Write-Host "[ERROR] CleanupTools.psm1 not found. Cannot run cleanup."
    exit 1
}

Write-Host "`n=== Cleanup Complete ==="


