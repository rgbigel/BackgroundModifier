<#
    Script: Installer.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Deploy BackgroundModifier runtime files from the repository to the runtime
             directory, then invoke Setup.ps1 from the deployed location.

    Runtime target: D:\OneDrive\cmd\runtimes\<ProjectName>\
    The project name is derived from the repository root directory name.
    This script must be run from within the repository's Install directory or
    via the BackgroundModifier_Install.cmd launcher.
#>

<#
.SYNOPSIS
    Deploys BackgroundModifier runtime files and hands off to Setup.

.DESCRIPTION
    Copies Source, Modules, and Install content from the repository into the
    runtime target folder and then invokes deployed Setup.ps1.

.PARAMETER DebugMode
    Enables debug output.

.PARAMETER TraceMode
    Enables installer transcript logging.
    Alias: t

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?

.EXAMPLE
    .\Installer.ps1

.EXAMPLE
    .\Installer.ps1 -t

.EXAMPLE
    .\Installer.ps1 -h
#>

[CmdletBinding()]
param(
    [switch]$DebugMode,
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode
)

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

if ($DebugMode -and -not $TraceMode) {
    $TraceMode = $true
}

$ScriptVersion = "8.0.0"

# --- Derive source root from this script's location ($PSScriptRoot = Install\) ---
$RepoRoot    = Split-Path $PSScriptRoot -Parent
$ProjectName = Split-Path $RepoRoot -Leaf

# --- Runtime deployment target ---
$CmdRoot     = "D:\OneDrive\cmd"
$RuntimeBase = Join-Path $CmdRoot "runtimes"
$RuntimeDir  = Join-Path $RuntimeBase $ProjectName

# --- Paths to copy ---
$SourceSrc  = Join-Path $RepoRoot "Source"
$ModulesSrc = Join-Path $RepoRoot "Modules"
$InstallSrc = Join-Path $RepoRoot "Install"

$SourceDst  = Join-Path $RuntimeDir "Source"
$ModulesDst = Join-Path $RuntimeDir "Modules"
$InstallDst = Join-Path $RuntimeDir "Install"

$SetupDeployed = Join-Path $InstallDst "Setup.ps1"
$LogRoot       = "C:\BackgroundMotives\logs"

# --- Bootstrap transcript before LogRoot is guaranteed ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $tempLog = Join-Path $env:TEMP "BackgroundModifier_Installer_$timestamp.log"
    Start-Transcript -Path $tempLog -Force | Out-Null
}

Write-Host "=== BackgroundModifier Installer (v$ScriptVersion) ==="
Write-Host "Project : $ProjectName"
Write-Host "Source  : $RepoRoot"
Write-Host "Target  : $RuntimeDir"
if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled" }

# --- Windows 11 check ---
function Test-IsWindows11 {
    try {
        $build = [int](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber")
        return ($build -ge 22000)
    }
    catch { return $false }
}

if (-not (Test-IsWindows11)) {
    Write-Host "[X] Unsupported OS. This solution supports Windows 11 only."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Verify source layout ---
Write-Host "--- Verifying source layout ---"
$missingDirs = @()
foreach ($dir in @($SourceSrc, $ModulesSrc, $InstallSrc)) {
    if (Test-Path $dir) {
        if ($DebugMode) { Write-Host "[OK] Found: $dir" }
    } else {
        Write-Host "[X] Missing: $dir"
        $missingDirs += $dir
    }
}
if ($missingDirs.Count -gt 0) {
    Write-Host "[X] Repository layout incomplete. Cannot continue."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}
Write-Host "[OK] Source layout verified"

# --- Create runtime deployment directories ---
Write-Host "--- Creating runtime directories ---"
foreach ($dir in @($RuntimeBase, $RuntimeDir, $SourceDst, $ModulesDst, $InstallDst)) {
    if (-not (Test-Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "[OK] Created: $dir"
        }
        catch {
            Write-Host "[X] Failed creating $dir : $($_.Exception.Message)"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
    } else {
        if ($DebugMode) { Write-Host "[OK] Exists: $dir" }
    }
}

# --- Deploy Source ---
Write-Host "--- Deploying Source ---"
try {
    Copy-Item -Path "$SourceSrc\*" -Destination $SourceDst -Recurse -Force
    Write-Host "[OK] Source deployed -> $SourceDst"
}
catch {
    Write-Host "[X] Failed deploying Source: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Deploy Modules ---
Write-Host "--- Deploying Modules ---"
try {
    Copy-Item -Path "$ModulesSrc\*" -Destination $ModulesDst -Recurse -Force
    Write-Host "[OK] Modules deployed -> $ModulesDst"
}
catch {
    Write-Host "[X] Failed deploying Modules: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Deploy Install ---
Write-Host "--- Deploying Install ---"
try {
    Copy-Item -Path "$InstallSrc\*" -Destination $InstallDst -Recurse -Force
    Write-Host "[OK] Install scripts deployed -> $InstallDst"
}
catch {
    Write-Host "[X] Failed deploying Install scripts: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Stop bootstrap transcript before Setup.ps1 starts its own ---
if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Installer transcript: $tempLog"

    # Move it to LogRoot once Setup creates it
    $moveScript = {
        param($src, $logRoot)
        Start-Sleep -Seconds 3
        if (Test-Path $logRoot) {
            Copy-Item -Path $src -Destination (Join-Path $logRoot (Split-Path $src -Leaf)) -Force
        }
    }
    Start-Job -ScriptBlock $moveScript -ArgumentList $tempLog, $LogRoot | Out-Null
}

# --- Hand off to deployed Setup.ps1 ---
Write-Host "--- Handing off to Setup.ps1 ---"
if (-not (Test-Path $SetupDeployed)) {
    Write-Host "[X] Deployed Setup.ps1 not found -> $SetupDeployed"
    exit 1
}

$setupParams = @{}
if ($DebugMode) { $setupParams.DebugMode = $true }
if ($TraceMode) { $setupParams.TraceMode = $true }

& $SetupDeployed @setupParams
exit $LASTEXITCODE
