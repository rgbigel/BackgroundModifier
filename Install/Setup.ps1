# =================================================================================================
#  Module:      Setup.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     16.0.0
#  Changelog:
#      6.0.0  --------  Added cmd entry-point provisioning and verifier alignment.
#      5.000  --------  Initial module creation for Consolidated Architecture (installer)
# =================================================================================================

param(
    [switch]$t,
    [switch]$d,
    [string]$CmdRoot = "D:\OneDrive\cmd",
    [string]$RuntimeRoot = "C:\BackgroundMotives",
    [switch]$IncludeTestLinks
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
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force
Import-Module (Join-Path $ModuleRoot "InstallerTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SchedulerTools.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t -D:$d
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $TranscriptPath = Join-Path $Global:LogRoot "Setup_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setup.ps1 (v16.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

if (-not (Test-Admin)) {
    Write-Host "[WARN] Setup requires elevation. Relaunching via UAC prompt."
    $elevatedExitCode = Invoke-SelfElevated -ScriptPath $resolvedScriptPath -WorkingDirectory $RepoRootResolved -NamedArguments @{
        CmdRoot = $CmdRoot
        RuntimeRoot = $RuntimeRoot
        IncludeTestLinks = [bool]$IncludeTestLinks
        t = [bool]$t
        d = [bool]$d
    }
    exit $elevatedExitCode
}

try {
    Require-Admin

    # Runtime roots are explicit install-time inputs and become active constants for the process.
    $Global:RootPath = $RuntimeRoot
    $Global:LogRoot = Join-Path $Global:RootPath "logs"
    $Global:AssetsRoot = Join-Path $Global:RootPath "assets"
    $Global:RenderRoot = Join-Path $Global:RootPath "rendered"
    $Global:SystemRoot = Join-Path $Global:RootPath "system"

    function New-OrReplaceLink {
        param(
            [string]$Target,
            [string]$Source
        )

        if (-not (Test-Path -LiteralPath $Source)) {
            Write-Host "[WARN] Link source missing: $Source"
            return
        }

        if (Test-Path -LiteralPath $Target) {
            Remove-Item -LiteralPath $Target -Force
        }

        New-Item -Path $Target -ItemType SymbolicLink -Value $Source -Force | Out-Null
        Write-Host "[OK] Linked $Target -> $Source"
    }

    Write-Host "--- Preparing runtime folders ---"
    $solutionCodeRoot = Join-Path $Global:RootPath "SolutionCode"
    Ensure-Path -Path $Global:RootPath | Out-Null
    Ensure-Path -Path $Global:LogRoot | Out-Null
    Ensure-Path -Path $Global:AssetsRoot | Out-Null
    Ensure-Path -Path $Global:RenderRoot | Out-Null
    Ensure-Path -Path $Global:SystemRoot | Out-Null
    Ensure-Path -Path $solutionCodeRoot | Out-Null
    Write-Host "[OK] Runtime folder structure prepared under $($Global:RootPath)"

    Write-Host "--- Checking required assets ---"
    $desktopBase = Join-Path $Global:AssetsRoot "DesktopBase.jpg"
    $logonBase = Join-Path $Global:AssetsRoot "LogonBase.jpg"
    if (-not (Test-Path -LiteralPath $desktopBase)) {
        Write-Host "[WARN] Missing asset: $desktopBase"
    }
    else {
        Write-Host "[OK] Found asset: $desktopBase"
    }
    if (-not (Test-Path -LiteralPath $logonBase)) {
        Write-Host "[WARN] Missing asset: $logonBase"
    }
    else {
        Write-Host "[OK] Found asset: $logonBase"
    }

    Write-Host "--- Creating script links in SolutionCode ---"
    $repoRoot = $RepoRootResolved
    $links = @(
        @{ Name = "BootIdentity.ps1"; Source = (Join-Path $repoRoot "Source\BootIdentity.ps1") },
        @{ Name = "BackgroundRenderer.ps1"; Source = (Join-Path $repoRoot "Source\BackgroundRenderer.ps1") },
        @{ Name = "BackgroundSetter.ps1"; Source = (Join-Path $repoRoot "Source\BackgroundSetter.ps1") },
        @{ Name = "BackgroundSetterStart.ps1"; Source = (Join-Path $repoRoot "Source\BackgroundSetterStart.ps1") },
        @{ Name = "BackgroundInstallationVerifier.ps1"; Source = (Join-Path $repoRoot "Install\BackgroundInstallationVerifier.ps1") }
    )

    foreach ($item in $links) {
        $target = Join-Path $solutionCodeRoot $item.Name
        New-OrReplaceLink -Target $target -Source $item.Source
    }

    Write-Host "--- Creating operational entry points in cmd ---"
    Ensure-Path -Path $CmdRoot | Out-Null

    $cmdLinks = @(
        @{ Name = "BackgroundModifier-AdminShell.ps1"; Source = (Join-Path $repoRoot "Install\AdminShell.ps1") },
        @{ Name = "BackgroundModifier-Setup.ps1"; Source = (Join-Path $repoRoot "Install\Setup.ps1") },
        @{ Name = "BackgroundModifier-Verify.ps1"; Source = (Join-Path $repoRoot "Install\BackgroundInstallationVerifier.ps1") },
        @{ Name = "BackgroundModifier-Cleanup.ps1"; Source = (Join-Path $repoRoot "Install\Cleanup.ps1") },
        @{ Name = "BackgroundModifier-Disable.ps1"; Source = (Join-Path $repoRoot "Install\Disable.ps1") },
        @{ Name = "BackgroundModifier-Enable.ps1"; Source = (Join-Path $repoRoot "Install\Enable.ps1") },
        @{ Name = "BackgroundModifier-Uninstall.ps1"; Source = (Join-Path $repoRoot "Install\Uninstall.ps1") }
    )

    foreach ($item in $cmdLinks) {
        $target = Join-Path $CmdRoot $item.Name
        New-OrReplaceLink -Target $target -Source $item.Source
    }

    $testCmdLinks = @(
        @{ Name = "BackgroundModifier-BootIdentityTest.ps1"; Source = (Join-Path $repoRoot "Source\BootIdentity.ps1") },
        @{ Name = "BackgroundModifier-RenderTest.ps1"; Source = (Join-Path $repoRoot "Source\BackgroundRenderer.ps1") },
        @{ Name = "BackgroundModifier-ApplyTest.ps1"; Source = (Join-Path $repoRoot "Source\BackgroundSetter.ps1") },
        @{ Name = "BackgroundModifier-LogonStage.ps1"; Source = (Join-Path $repoRoot "Source\BackgroundSetterStart.ps1") }
    )

    if ($IncludeTestLinks) {
        Write-Host "--- Creating testing entry points in cmd (opt-in) ---"
        foreach ($item in $testCmdLinks) {
            $target = Join-Path $CmdRoot $item.Name
            New-OrReplaceLink -Target $target -Source $item.Source
        }
    }
    else {
        Write-Host "--- Removing testing entry points in cmd (default mode) ---"
        foreach ($item in $testCmdLinks) {
            $target = Join-Path $CmdRoot $item.Name
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Force
                Write-Host "[OK] Removed test entry point: $target"
            }
        }
        Write-Host "[OK] Test entry points removed/skipped. Use -IncludeTestLinks to create them."
    }

    Write-Host "--- Registering scheduled automation tasks ---"
    Register-BackgroundTask -TaskName "BackgroundModifier-BootIdentity" -ScriptPath (Join-Path $solutionCodeRoot "BootIdentity.ps1") -TriggerType Startup -RunAs System
    Register-BackgroundTask -TaskName "BackgroundModifier-Autorun" -ScriptPath (Join-Path $solutionCodeRoot "BackgroundSetterStart.ps1") -TriggerType LogOn -RunAs Interactive

    Write-Host "--- Setup verification ---"
    $verifierScript = Join-Path $PSScriptRoot "BackgroundInstallationVerifier.ps1"
    & $verifierScript -t:$t -d:$d -CmdRoot $CmdRoot -RuntimeRoot $RuntimeRoot -IncludeTestLinks:$IncludeTestLinks
    if ($LASTEXITCODE -ne 0) {
        throw "BackgroundInstallationVerifier failed with exit code $LASTEXITCODE"
    }

    Write-Host "[OK] Setup completed successfully"
}
catch {
    Write-Host "[X] Setup failed: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

