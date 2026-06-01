# =================================================================================================
#  Module:      BackgroundSetter.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (wallpaper application)
# =================================================================================================

param(
    [switch]$t,
    [switch]$d
)

$ModuleRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "Modules"
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
Import-Module (Join-Path $ModuleRoot "WallpaperTools.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t -D:$d
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

$RenderRoot = $Global:RenderRoot
$SystemRoot = $Global:SystemRoot

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $TranscriptPath = Join-Path $Global:LogRoot "Setter_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setter (v1.001) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$RenderedLogon   = Join-Path $RenderRoot "Logon.jpg"
$RenderedDesktop = Join-Path $RenderRoot "Desktop.jpg"

$SystemLogon   = Join-Path $SystemRoot "Logon.jpg"
$SystemDesktop = Join-Path $SystemRoot "Desktop.jpg"

Write-Host "--- Checking rendered images ---"

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

Write-Host "[OK] Rendered images found"

Write-Host "--- Applying backgrounds ---"

try {
    Copy-Item -Path $RenderedLogon -Destination $SystemLogon -Force
    Write-Host "[OK] Applied logon background -> $SystemLogon"

    Copy-Item -Path $RenderedDesktop -Destination $SystemDesktop -Force
    Write-Host "[OK] Applied desktop background -> $SystemDesktop"

    Set-Wallpaper -ImagePath $SystemDesktop
}
catch {
    Write-Host "[X] Failed to apply backgrounds: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "--- Summary ---"
Write-Host "[OK] Backgrounds applied successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}
