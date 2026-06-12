<#
    Script: BackgroundInstallationVerifier.ps1
    Version: 7.0.0
    Author: Rolf Bercht
    Purpose: Deterministic verification of BackgroundModifier installation.
#>

param(
    [switch]$DebugMode,
    [switch]$TraceMode
)

# --- Absolute log root ---
$LogRoot = "C:\BackgroundMotives\logs"

# --- Transcript handling ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Verifier_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Installation Verifier (v7.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

# --- Directory invariants ---
$RequiredDirectories = @(
    "C:\BackgroundMotives",
    "C:\BackgroundMotives\assets",
    "C:\BackgroundMotives\logs"
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
Write-Host "(No file invariants defined in v7.0.0)"

# --- Summary ---
Write-Host "=== Summary ==="

if ($MissingDirectories.Count -gt 0) {
    foreach ($m in $MissingDirectories) {
        Write-Host " - Missing directory: $m"
    }
} else {
    Write-Host "All required directories are present."
}

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

