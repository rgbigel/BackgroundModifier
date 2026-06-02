# =================================================================================================
#  Module:      BackgroundInstallationVerifier.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Added cmd entry-point verification and explicit root overrides.
#      5.000  --------  Initial module creation for Consolidated Architecture (installation verifier)
# =================================================================================================

param(
    [switch]$t,
    [switch]$d,
    [Alias('c')]
    [string]$CmdRoot = "D:\OneDrive\cmd",
    [Alias('r')]
    [string]$RuntimeRoot = "C:\BackgroundMotives",
    [Alias('i')]
    [switch]$IncludeTestLinks
)

if ($t) {
    if (-not $PSBoundParameters.ContainsKey('d')) {
        $d = $true
    }
    if (-not $PSBoundParameters.ContainsKey('IncludeTestLinks')) {
        $IncludeTestLinks = $true
    }
}

$scriptItem = Get-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
$resolvedScriptPath = $PSCommandPath
if ($scriptItem -and $scriptItem.LinkType -eq "SymbolicLink" -and $scriptItem.Target) {
    $resolvedScriptPath = [string]$scriptItem.Target
}
$ScriptRootResolved = Split-Path -Parent ([System.IO.Path]::GetFullPath($resolvedScriptPath))
$RepoRootResolved = Split-Path -Parent $ScriptRootResolved
$ModuleRoot = Join-Path $RepoRootResolved "Modules"
$prev = $WarningPreference
$WarningPreference = "SilentlyContinue"

Import-Module (Join-Path $ModuleRoot "Constants.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force
Import-Module (Join-Path $ModuleRoot "TranscriptTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "PathTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t -D:$d
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

$LogRoot     = Join-Path $RuntimeRoot "logs"
$AssetsRoot  = Join-Path $RuntimeRoot "assets"
$RenderRoot  = Join-Path $RuntimeRoot "rendered"
$SystemRoot  = Join-Path $RuntimeRoot "system"

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $TranscriptPath = Join-Path $LogRoot "Verifier_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier BackgroundInstallationVerifier.ps1 (v6.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier BackgroundInstallationVerifier.ps1 help" -UsageLines @(
        "Usage: BackgroundInstallationVerifier.ps1 [-t] [-d] [-CmdRoot <path>] [-RuntimeRoot <path>] [-IncludeTestLinks]",
        "  -t: Trace mode (starts transcript; implies -d and -IncludeTestLinks when not explicitly set).",
        "  -d: Debug mode (verbose console diagnostics and pause-on-exit in interactive runs).",
        "  -IncludeTestLinks (-i): Verify test cmd entry points in addition to operational checks.",
        "  -CmdRoot (-c): Folder where cmd entry-point links are validated.",
        "  -RuntimeRoot (-r): Runtime root containing logs/assets/rendered/system folders.",
        "Use /?, /H, or -Help to show this message.",
        "This script does not require elevation."
    )
    exit 0
}

Write-Host "--- Checking folder structure ---"

$folders = @(
    $LogRoot,
    $AssetsRoot,
    $RenderRoot,
    $SystemRoot
)

foreach ($folder in $folders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        Write-Host "[X] Missing folder -> $folder"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
    Write-Host "[OK] $folder"
}

Write-Host "--- Checking required modules ---"

$requiredModules = @(
    "Constants.psm1",
    "Logging.psm1",
    "TranscriptTools.psm1",
    "PathTools.psm1",
    "ErrorTools.psm1",
    "Validation.psm1",
    "ModeTools.psm1",
    "SummaryTools.psm1",
    "SetFlagsTool.psm1"
)

foreach ($mod in $requiredModules) {
    $path = Join-Path $ModuleRoot $mod
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[X] Missing module -> $path"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
    Write-Host "[OK] $mod"
}

Write-Host "--- Checking base assets ---"

$DesktopBase = Join-Path $AssetsRoot "DesktopBase.jpg"
$LogonBase   = Join-Path $AssetsRoot "LogonBase.jpg"

if (-not (Test-Path -LiteralPath $DesktopBase)) {
    Write-Host "[X] Missing DesktopBase -> $DesktopBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-Path -LiteralPath $LogonBase)) {
    Write-Host "[X] Missing LogonBase -> $LogonBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Base assets present"

Write-Host "--- Checking operational cmd entry points ---"

$cmdEntries = @(
    "BackgroundModifier-AdminShell.ps1",
    "BackgroundModifier-Setup.ps1",
    "BackgroundModifier-Verify.ps1",
    "BackgroundModifier-Cleanup.ps1",
    "BackgroundModifier-Disable.ps1",
    "BackgroundModifier-Enable.ps1",
    "BackgroundModifier-Uninstall.ps1"
)

foreach ($entry in $cmdEntries) {
    $path = Join-Path $CmdRoot $entry
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[X] Missing cmd entry point -> $path"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
    Write-Host "[OK] $path"
}

if ($IncludeTestLinks) {
    Write-Host "--- Checking testing cmd entry points (opt-in) ---"
    $testCmdEntries = @(
        "BackgroundModifier-BootIdentityTest.ps1",
        "BackgroundModifier-RenderTest.ps1",
        "BackgroundModifier-ApplyTest.ps1",
        "BackgroundModifier-LogonStage.ps1"
    )

    foreach ($entry in $testCmdEntries) {
        $path = Join-Path $CmdRoot $entry
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "[X] Missing cmd test entry point -> $path"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
        Write-Host "[OK] $path"
    }
}
else {
    Write-Host "[OK] Test cmd entry point verification skipped (default)."
}

Write-Host "--- Checking operational scheduled tasks ---"

$taskEntries = @(
    "BackgroundModifier-BootIdentity",
    "BackgroundModifier-Autorun"
)

foreach ($taskName in $taskEntries) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "[X] Missing scheduled task -> $taskName"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
    Write-Host "[OK] $taskName"
}

Write-Host "--- Summary ---"
Write-Host "[OK] Installation verified successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

Wait-ForInstallerExit -Pause:($TraceMode -or $DebugMode) -Message "Verification completed. Press Enter to exit..."

