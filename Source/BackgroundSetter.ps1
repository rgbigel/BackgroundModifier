# =================================================================================================
#  Module:      BackgroundSetter.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (wallpaper application)
# =================================================================================================

param(
    [switch]$t
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
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force
Import-Module (Join-Path $ModuleRoot "WallpaperTools.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

$RenderRoot = $Global:RenderRoot
$SystemRoot = $Global:SystemRoot
$AssetsRoot = $Global:AssetsRoot

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $TranscriptPath = Join-Path $Global:LogRoot "Setter_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier BackgroundSetter.ps1 (v6.0.0) ==="

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

function Save-HistoryImageIfMissing {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return
    }

    if (Test-Path -LiteralPath $TargetPath) {
        Write-Host "[OK] $Label history already exists -> $TargetPath"
        return
    }

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Write-Host "[WARN] $Label source not found for history backup -> $SourcePath"
        return
    }

    Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    Write-Host "[OK] Backed up current $Label image -> $TargetPath"
}

Write-Host "--- Backing up current live images (once) ---"

if (-not (Test-Path -LiteralPath $AssetsRoot)) {
    New-Item -Path $AssetsRoot -ItemType Directory -Force | Out-Null
}

$DesktopHist = Join-Path $AssetsRoot "DesktopHist.jpg"
$LogonHist = Join-Path $AssetsRoot "LogonHist.jpg"

$currentDesktopPath = $null
try {
    $desktopReg = Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction SilentlyContinue
    if ($desktopReg -and -not [string]::IsNullOrWhiteSpace([string]$desktopReg.Wallpaper)) {
        $currentDesktopPath = [string]$desktopReg.Wallpaper
    }
}
catch {
    $currentDesktopPath = $null
}

$currentLogonPath = $null
$logonCandidates = @(
    $SystemLogon,
    "C:\Windows\Web\Screen\img100.jpg"
)
foreach ($candidate in $logonCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
        $currentLogonPath = $candidate
        break
    }
}

Save-HistoryImageIfMissing -SourcePath $currentDesktopPath -TargetPath $DesktopHist -Label "desktop"
Save-HistoryImageIfMissing -SourcePath $currentLogonPath -TargetPath $LogonHist -Label "logon"

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


