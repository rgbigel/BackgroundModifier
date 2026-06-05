# =================================================================================================
#  Module:      Verifyer.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Added cmd entry-point verification and explicit root overrides.
#      5.000  --------  Initial module creation for Consolidated Architecture (installation verifier)
# =================================================================================================

param(
    [switch]$t,
    [Alias('i')]
    [switch]$IncludeTestLinks,
    [Alias('c')]
    [string]$CmdRoot = "D:\OneDrive\cmd",
    [Alias('r')]
    [string]$RuntimeRoot = "C:\BootOpsHub"
)

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
Import-Module (Join-Path $ModuleRoot "InstallerTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t
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

Write-Host "=== BackgroundModifier Verifyer.ps1 (v6.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier Verifyer.ps1 help" -UsageLines @(
        "Usage: Verifyer.ps1 [-t] [-IncludeTestLinks] [-CmdRoot <path>] [-RuntimeRoot <path>]",
        "  -t: Trace mode (starts transcript and enables implied debug behavior).",
        "  -IncludeTestLinks (-i): Also require the cmd test entry links to exist.",
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
    $SystemRoot,
    (Join-Path $RuntimeRoot "SolutionCode"),
    (Join-Path $RuntimeRoot "SolutionCode\Source"),
    (Join-Path $RuntimeRoot "SolutionCode\Modules"),
    (Join-Path $RuntimeRoot "SolutionCode\Install")
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
    "BackgroundNoBlurReg.psm1",
    "BackgroundStateMgr.psm1",
    "BootTools.psm1",
    "CleanupTools.psm1",
    "ConfigTools.psm1",
    "Constants.psm1",
    "ImageTools.psm1",
    "InstallerTools.psm1",
    "Logging.psm1",
    "LoggingTools.psm1",
    "ProfileTools.psm1",
    "RenderTools.psm1",
    "SchedulerTools.psm1",
    "TranscriptTools.psm1",
    "PathTools.psm1",
    "ErrorTools.psm1",
    "Validation.psm1",
    "ValidationTools.psm1",
    "WallpaperTools.psm1",
    "ModeTools.psm1",
    "SummaryTools.psm1",
    "SetFlagsTool.psm1",
    "SystemTools.psm1",
    "TaskTools.psm1",
    "TimeTools.psm1"
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
    "BackgroundModifier_Install.cmd",
    "BackgroundModifier.cmd"
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

Write-Host "[OK] Test cmd entry point verification is menu-driven in current model."

if ($IncludeTestLinks) {
    Write-Host "--- Checking test cmd entry points ---"

    $testCmdEntries = @(
        "BackgroundModifier-BootIdentityTest.ps1",
        "BackgroundModifier-RenderTest.ps1",
        "BackgroundModifier-ApplyTest.ps1",
        "BackgroundModifier-LogonStage.ps1"
    )

    foreach ($entry in $testCmdEntries) {
        $path = Join-Path $CmdRoot $entry
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host "[X] Missing test cmd entry -> $path"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
        Write-Host "[OK] $path"
    }
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


