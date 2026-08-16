[CmdletBinding()]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("d")]
    [ValidateSet("m","n","d","f","M","N","D","F")]
    [string]$DetailLevel,
    [Alias("b")]
    [switch]$BcdLogEnabled,
    [Alias("h","?")]
    [switch]$HelpMode,
    [string]$RuntimeRoot = $Global:RuntimeRoot,
    [string]$StateFilePath,
    [string]$LogRoot
)

<#
    Script: BackgroundPhase2aHarness.ps1
    Version: 10.0.0
    Author: Rolf Bercht
    Purpose: Phase 2a harness that runs renderer and setter sequentially in one task execution.
#>

if ($HelpMode) {
    Write-Host "BackgroundPhase2aHarness (v10.0.0)"
    Write-Host "Runs BackgroundRenderer then BackgroundSetter sequentially for Phase 2a automation."
    exit 0
}

# Import Constants so defaults can bind to $Global:* variables
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

$ScriptVersion = "10.0.0"
$TranscriptStarted = $false

function Stop-HarnessTranscriptIfNeeded {
    if ($TraceMode -and $TranscriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}

function Exit-Harness {
    param(
        [int]$Code
    )

    if ($TraceMode) {
        Write-Host ""
        $null = Read-Host "Trace mode: Press Enter to exit"
    }

    Stop-HarnessTranscriptIfNeeded
    exit $Code
}

if ($TraceMode) {
    $effectiveLogRoot = if ($LogRoot) { $LogRoot } else { $Global:LogRoot }
    if (-not (Test-Path $effectiveLogRoot)) {
        New-Item -ItemType Directory -Path $effectiveLogRoot -Force | Out-Null
    }
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $effectiveLogRoot "Phase2aHarness_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
    $TranscriptStarted = $true
    Write-Host "[INFO] Trace mode enabled - transcript started: $TranscriptPath"
}

try {
    if ($Host -and $Host.UI -and $Host.UI.RawUI) {
        $Host.UI.RawUI.WindowTitle = "BackgroundModifier Phase2a Harness v$ScriptVersion"
    }
}
catch {}

$rendererScript = Join-Path $PSScriptRoot "BackgroundRenderer.ps1"
$setterScript = Join-Path $PSScriptRoot "BackgroundSetter.ps1"

if (-not (Test-Path $rendererScript)) {
    Write-Host "[X] Missing renderer script: $rendererScript"
    Exit-Harness 2
}

if (-not (Test-Path $setterScript)) {
    Write-Host "[X] Missing setter script: $setterScript"
    Exit-Harness 2
}

Write-Host "=== BackgroundModifier Phase2a Harness (v$ScriptVersion) ==="
Write-Host "[INFO] Phase2a mode: scheduled non-interactive autorun."

$commonParams = @{
    RuntimeRoot = $RuntimeRoot
}
if ($StateFilePath) {
    $commonParams.StateFilePath = $StateFilePath
}
if ($LogRoot) {
    $commonParams.LogRoot = $LogRoot
}
if ($TraceMode) {
    $commonParams.TraceMode = $true
}
if ($DetailLevel) {
    $commonParams.DetailLevel = $DetailLevel
}
if ($BcdLogEnabled) {
    $commonParams.BcdLogEnabled = $true
}
$commonParams.Phase2aAutorun = $true

Write-Host "[INFO] Phase2a step 1/2: renderer"
& $rendererScript @commonParams
$rendererExit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
if ($rendererExit -ne 0) {
    Write-Host "[X] Renderer failed with exit code $rendererExit"
    Exit-Harness $rendererExit
}

Write-Host "[INFO] Phase2a step 2/2: setter"
& $setterScript @commonParams
$setterExit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
if ($setterExit -ne 0) {
    Write-Host "[X] Setter failed with exit code $setterExit"
    Exit-Harness $setterExit
}

Write-Host "[OK] Phase2a harness completed successfully."
Exit-Harness 0
