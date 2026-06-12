<#
    Script: BackgroundRenderer.ps1
    Version: 7.0.0
    Author: Rolf Bercht
    Purpose: Deterministic generation of logon and desktop background output images.
#>

param(
    [switch]$DebugMode,
    [switch]$TraceMode
)

$LogRoot = "C:\BackgroundMotives\logs"

$ModuleRoot = Join-Path $PSScriptRoot "Modules"
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

$WarningPreference = $prev

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Renderer_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Renderer (v7.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

# --- Correct asset names (JPG) ---
$DesktopBase = "C:\BackgroundMotives\assets\DesktopBase.jpg"
$LogonBase   = "C:\BackgroundMotives\assets\LogonBase.jpg"

$OutputLogon   = "C:\BackgroundMotives\assets\Logon.jpg"
$OutputDesktop = "C:\BackgroundMotives\assets\Desktop.jpg"

Write-Host "--- Asset check ---"

if (-not (Test-Path $DesktopBase)) {
    Write-Host "[X] Missing DesktopBase -> $DesktopBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-Path $LogonBase)) {
    Write-Host "[X] Missing LogonBase -> $LogonBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Base assets present"

Write-Host "--- Rendering images ---"

try {
    Copy-Item -Path $LogonBase   -Destination $OutputLogon   -Force
    Write-Host "[OK] Generated logon image -> $OutputLogon"

    Copy-Item -Path $DesktopBase -Destination $OutputDesktop -Force
    Write-Host "[OK] Generated desktop image -> $OutputDesktop"
}
catch {
    Write-Host "[X] Rendering failed: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "--- Summary ---"
Write-Host "[OK] Rendering completed successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

