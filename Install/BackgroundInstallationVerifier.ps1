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

$ScriptVersion = "8.0.0"

# --- Absolute log root ---
$LogRoot = "C:\BackgroundMotives\logs"

# --- Transcript handling ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Verifier_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Installation Verifier (v$ScriptVersion) ==="

if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$DeployedRoot = Split-Path $PSScriptRoot -Parent
$RendererScript = Join-Path $DeployedRoot "Source\BackgroundRenderer.ps1"
$SetterScript = Join-Path $DeployedRoot "Source\BackgroundSetter.ps1"
$RenderToolsModule = Join-Path $DeployedRoot "Modules\RenderTools.psm1"

# --- Directory invariants ---
$RequiredDirectories = @(
    "C:\BackgroundMotives",
    "C:\BackgroundMotives\assets",
    "C:\BackgroundMotives\logs",
    (Join-Path $DeployedRoot "Modules")
)

$RequiredFiles = @(
    $RendererScript,
    $SetterScript,
    $RenderToolsModule
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
    if ($normalizedArgs -like "*${ExpectedScriptPath}*") {
        Write-Host "[OK] $TaskName -> $ExpectedScriptPath"
    }
    else {
        Write-Host "[WARN] $TaskName action path differs from deployed runtime"
        Write-Host "[WARN]   Expected contains: $ExpectedScriptPath"
        Write-Host "[WARN]   Actual args: $normalizedArgs"
    }
}

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

