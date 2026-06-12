<#
    Script: BackgroundSetter.ps1
    Version: 7.0.0
    Author: Rolf Bercht
    Purpose: Deterministic application of rendered background images to logon and desktop.
#>

param(
    [switch]$DebugMode,
    [switch]$TraceMode
)

# --- Absolute log root ---
$LogRoot = "C:\BackgroundMotives\logs"

# --- Import modules ---
$ModuleRoot = Join-Path $PSScriptRoot "Modules"
Import-Module (Join-Path $ModuleRoot "Constants.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force
Import-Module (Join-Path $ModuleRoot "TranscriptTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "PathTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force

# --- Transcript handling ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Setter_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setter (v7.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

# --- Paths ---
$RenderedLogon = "C:\BackgroundMotives\assets\Logon.jpg"
$RenderedDesktop = "C:\BackgroundMotives\assets\Desktop.jpg"

Write-Host "--- File check ---"

if (-not (Test-Path $RenderedLogon)) {
    Write-Host "[X] Missing rendered logon image -> $RenderedLogon"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-Path $RenderedDesktop)) {
    Write-Host "[X] Missing rendered desktop image -> $RenderedDesktop"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Rendered images present"

# --- Apply logon background ---
Write-Host "--- Applying logon background ---"

try {
    Copy-Item -Path $RenderedLogon -Destination "C:\Windows\System32\oobe\info\backgrounds\backgroundDefault.jpg" -Force
    Write-Host "[OK] Logon background applied -> backgroundDefault.jpg"
}
catch {
    Write-Host "[X] Failed to apply logon background: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Apply desktop background ---
Write-Host "--- Applying desktop background ---"

try {
    Copy-Item -Path $RenderedDesktop -Destination "$env:USERPROFILE\Pictures\Background.jpg" -Force
    Write-Host "[OK] Desktop background applied -> $env:USERPROFILE\Pictures\Background.jpg"
}
catch {
    Write-Host "[X] Failed to apply desktop background: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Summary ---
Write-Host "--- Summary ---"
Write-Host "[OK] Backgrounds applied successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

