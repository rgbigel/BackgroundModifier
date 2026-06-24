<#
    Script: BackgroundInstallationVerifier.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Deterministic verification of BackgroundModifier installation.
#>

<#
.SYNOPSIS
    Verifies BackgroundModifier runtime installation state.

.DESCRIPTION
    Checks required runtime directories and files, then validates scheduled
    task action paths against the deployed renderer and setter scripts.

.PARAMETER TraceMode
    Enables transcript logging for verifier execution.
    Alias: t

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?

.EXAMPLE
    .\BackgroundInstallationVerifier.ps1

.EXAMPLE
    .\BackgroundInstallationVerifier.ps1 -t

.EXAMPLE
    .\BackgroundInstallationVerifier.ps1 -h
#>

[CmdletBinding()]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode
)

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

# Import Constants to bind paths
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

$ScriptVersion = "8.0.0"

# --- Absolute log root ---
$LogRoot = $Global:LogRoot

# --- Transcript handling ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Verifier_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Installation Verifier (v$ScriptVersion) ==="

if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$DeployedRoot = Split-Path $PSScriptRoot -Parent
$SeedAssetsRoot = Join-Path $DeployedRoot "assets"
$SeedStateFile = Join-Path $SeedAssetsRoot "state.json"
$SeedDesktopBase = Join-Path $SeedAssetsRoot "DesktopBase.jpg"
$SeedLogonBase = Join-Path $SeedAssetsRoot "LogonBase.jpg"
$RuntimeStateFile = Join-Path $Global:AssetsRoot "state.json"
$RuntimeDesktopBase = Join-Path $Global:AssetsRoot "DesktopBase.jpg"
$RuntimeLogonBase = Join-Path $Global:AssetsRoot "LogonBase.jpg"
$OrchestratorScript = Join-Path $DeployedRoot "Source\BackgroundModifier.ps1"
$RendererScript = Join-Path $DeployedRoot "Source\BackgroundRenderer.ps1"
$SetterScript = Join-Path $DeployedRoot "Source\BackgroundSetter.ps1"
$RenderToolsModule = Join-Path $DeployedRoot "Modules\RenderTools.psm1"

# --- Directory invariants ---
$RequiredDirectories = @(
    $Global:RuntimeRoot,
    $Global:AssetsRoot,
    $Global:LogRoot,
    (Join-Path $DeployedRoot "Modules"),
    $SeedAssetsRoot
)

$RequiredFiles = @(
    $OrchestratorScript,
    $RendererScript,
    $SetterScript,
    $RenderToolsModule,
    $SeedStateFile,
    $SeedDesktopBase,
    $SeedLogonBase,
    $RuntimeStateFile,
    $RuntimeDesktopBase,
    $RuntimeLogonBase
)

Write-Host "--- Directory check ---"

$MissingDirectories = @()

foreach ($dir in $RequiredDirectories) {
    if (Test-Path $dir) {
        Write-Host "[OK] $dir"
    } else {
        Write-Host "[X] Missing: $dir"
        $MissingDirectories += $dir
    }
}

# --- File checks (currently none by architectural design) ---
Write-Host "--- File check ---"

$MissingFiles = @()
foreach ($file in $RequiredFiles) {
    if (Test-Path $file) {
        Write-Host "[OK] $file"
    }
    else {
        Write-Host "[X] Missing: $file"
        $MissingFiles += $file
    }
}

Write-Host "--- Scheduled task action check ---"

function Test-TaskActionPath {
    param(
        [string]$TaskName,
        [string]$ExpectedScriptPath
    )

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "[X] Missing task: $TaskName"
        return
    }

    $action = $task.Actions | Select-Object -First 1
    if (-not $action) {
        Write-Host "[X] Task has no action: $TaskName"
        return
    }

    $normalizedArgs = [string]$action.Arguments
    $isEnabled = $true
    try {
        $isEnabled = [bool]$task.Settings.Enabled
    }
    catch {
        $isEnabled = $true
    }

    $enabledLabel = if ($isEnabled) { "Enabled" } else { "Disabled" }

    if ($normalizedArgs -like "*${ExpectedScriptPath}*") {
        Write-Host "[OK] $TaskName -> $ExpectedScriptPath [$enabledLabel]"
    }
    else {
        Write-Host "[WARN] $TaskName action path differs from deployed runtime"
        Write-Host "[WARN]   Expected contains: $ExpectedScriptPath"
        Write-Host "[WARN]   Actual args: $normalizedArgs"
        Write-Host "[WARN]   Task state: $enabledLabel"
    }

    if (-not $isEnabled) {
        Write-Host "[WARN] Task is currently disabled: $TaskName"
    }
}

Test-TaskActionPath -TaskName "BackgroundModifier-Startup"  -ExpectedScriptPath $OrchestratorScript
Test-TaskActionPath -TaskName "BackgroundModifier-Renderer" -ExpectedScriptPath $RendererScript
Test-TaskActionPath -TaskName "BackgroundModifier-Setter" -ExpectedScriptPath $SetterScript

# --- Summary ---
Write-Host "=== Summary ==="

if ($MissingDirectories.Count -gt 0) {
    foreach ($m in $MissingDirectories) {
        Write-Host " - Missing directory: $m"
    }
} else {
    Write-Host "All required directories are present."
}

if ($MissingFiles.Count -gt 0) {
    foreach ($m in $MissingFiles) {
        Write-Host " - Missing file: $m"
    }
}

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

