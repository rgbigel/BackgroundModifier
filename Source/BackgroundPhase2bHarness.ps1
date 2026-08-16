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
    Script: BackgroundPhase2bHarness.ps1
    Version: 10.0.0
    Author: Rolf Bercht
    Purpose: Interactive phase 2b harness with explicit action routing.
#>

if ($HelpMode) {
    Write-Host "BackgroundPhase2bHarness (v10.0.0)"
    Write-Host "Interactive action harness for phase 2b."
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  1 - Update desktop background"
    Write-Host "  2 - Update logon background"
    Write-Host "  3 - Update desktop + logon background"
    Write-Host "  4 - Run renderer only"
    Write-Host "  5 - Run renderer then setter"
    Write-Host "  6 - Get new background image (capture/promote + apply all)"
    Write-Host "  7 - Show runtime state (JSON)"
    Write-Host "  8 - Open log directory"
    Write-Host "  0 - Exit"
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

function Get-EffectiveStateFilePath {
    if ($StateFilePath) {
        return $StateFilePath
    }

    if ($RuntimeRoot) {
        return (Join-Path (Join-Path $RuntimeRoot "assets") "state.json")
    }

    return (Join-Path $Global:AssetsRoot "state.json")
}

function Get-EffectiveLogRoot {
    if ($LogRoot) {
        return $LogRoot
    }

    if ($RuntimeRoot) {
        return (Join-Path $RuntimeRoot "logs")
    }

    return $Global:LogRoot
}

if ($TraceMode) {
    $effectiveLogRoot = Get-EffectiveLogRoot
    if (-not (Test-Path $effectiveLogRoot)) {
        New-Item -ItemType Directory -Path $effectiveLogRoot -Force | Out-Null
    }
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $effectiveLogRoot "Phase2bHarness_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
    $TranscriptStarted = $true
    Write-Host "[INFO] Trace mode enabled - transcript started: $TranscriptPath"
}

try {
    if ($Host -and $Host.UI -and $Host.UI.RawUI) {
        $Host.UI.RawUI.WindowTitle = "BackgroundModifier Phase2b Harness v$ScriptVersion"
    }
}
catch {}

function Test-IsInteractiveSession {
    try {
        return [Environment]::UserInteractive
    }
    catch {
        return $true
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$CommonParams
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[X] Missing script for $Label: $ScriptPath"
        return 2
    }

    Write-Host "[INFO] Phase2b action step: $Label"
    & $ScriptPath @CommonParams

    if ($LASTEXITCODE -is [int]) {
        return [int]$LASTEXITCODE
    }

    return 0
}

if (-not (Test-IsInteractiveSession)) {
    Write-Host "[X] Phase2b harness requires an interactive session."
    Exit-Harness 1
}

$rendererScript = Join-Path $PSScriptRoot "BackgroundRenderer.ps1"
$setterScript = Join-Path $PSScriptRoot "BackgroundSetter.ps1"

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

Write-Host "=== BackgroundModifier Phase2b Harness (v$ScriptVersion) ==="
Write-Host "Select action:"
Write-Host "  [1] Update desktop background"
Write-Host "  [2] Update logon background"
Write-Host "  [3] Update desktop + logon background"
Write-Host "  [4] Renderer only"
Write-Host "  [5] Renderer + Setter"
Write-Host "  [6] Get new background image (capture/promote + apply all)"
Write-Host "  [7] Show runtime state (JSON)"
Write-Host "  [8] Open log directory"
Write-Host "  [0] Exit"

$selection = Read-Host "Action"

switch ($selection) {
    "1" {
        $setterParams = $commonParams.Clone()
        $setterParams.ApplyDesktop = $true
        $exitCode = Invoke-Step -Label "Setter (Desktop)" -ScriptPath $setterScript -CommonParams $setterParams
        if ($exitCode -ne 0) {
            Write-Host "[X] Setter (Desktop) failed with exit code $exitCode"
            Exit-Harness $exitCode
        }
    }
    "2" {
        $setterParams = $commonParams.Clone()
        $setterParams.ApplyLockScreen = $true
        $exitCode = Invoke-Step -Label "Setter (Logon)" -ScriptPath $setterScript -CommonParams $setterParams
        if ($exitCode -ne 0) {
            Write-Host "[X] Setter (Logon) failed with exit code $exitCode"
            Exit-Harness $exitCode
        }
    }
    "3" {
        $setterParams = $commonParams.Clone()
        $setterParams.ApplyDesktop = $true
        $setterParams.ApplyLockScreen = $true
        $exitCode = Invoke-Step -Label "Setter (Desktop+Logon)" -ScriptPath $setterScript -CommonParams $setterParams
        if ($exitCode -ne 0) {
            Write-Host "[X] Setter (Desktop+Logon) failed with exit code $exitCode"
            Exit-Harness $exitCode
        }
    }
    "4" {
        $exitCode = Invoke-Step -Label "Renderer" -ScriptPath $rendererScript -CommonParams $commonParams
        if ($exitCode -ne 0) {
            Write-Host "[X] Renderer failed with exit code $exitCode"
            Exit-Harness $exitCode
        }
    }
    "5" {
        $rendererExit = Invoke-Step -Label "Renderer" -ScriptPath $rendererScript -CommonParams $commonParams
        if ($rendererExit -ne 0) {
            Write-Host "[X] Renderer failed with exit code $rendererExit"
            Exit-Harness $rendererExit
        }

        $setterExit = Invoke-Step -Label "Setter" -ScriptPath $setterScript -CommonParams $commonParams
        if ($setterExit -ne 0) {
            Write-Host "[X] Setter failed with exit code $setterExit"
            Exit-Harness $setterExit
        }
    }
    "6" {
        $setterParams = $commonParams.Clone()
        $setterParams.CaptureDesktopAsBase = $true
        $setterParams.PromoteDesktopBaseToLogonBase = $true
        $setterParams.ApplyDesktop = $true
        $setterParams.ApplyLockScreen = $true
        $exitCode = Invoke-Step -Label "Setter (Capture+Promote+Apply)" -ScriptPath $setterScript -CommonParams $setterParams
        if ($exitCode -ne 0) {
            Write-Host "[X] Setter capture/promote action failed with exit code $exitCode"
            Exit-Harness $exitCode
        }
    }
    "7" {
        $effectiveStateFile = Get-EffectiveStateFilePath
        if (-not (Test-Path $effectiveStateFile)) {
            Write-Host "[X] State file not found: $effectiveStateFile"
            Exit-Harness 1
        }

        Write-Host "[INFO] Runtime state file: $effectiveStateFile"
        try {
            $raw = Get-Content -Path $effectiveStateFile -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) {
                Write-Host "[WARN] State file is empty."
            }
            else {
                $obj = $raw | ConvertFrom-Json -ErrorAction Stop
                $obj | ConvertTo-Json -Depth 20
            }
        }
        catch {
            Write-Host "[X] Failed reading state file: $($_.Exception.Message)"
            Exit-Harness 1
        }
    }
    "8" {
        $effectiveLogRoot = Get-EffectiveLogRoot
        if (-not (Test-Path $effectiveLogRoot)) {
            New-Item -ItemType Directory -Path $effectiveLogRoot -Force | Out-Null
        }
        Write-Host "[INFO] Opening log directory: $effectiveLogRoot"
        Start-Process explorer.exe $effectiveLogRoot | Out-Null
    }
    "0" {
        Write-Host "[INFO] Phase2b harness exit requested by user."
        Exit-Harness 0
    }
    default {
        Write-Host "[X] Invalid selection: $selection"
        Exit-Harness 1
    }
}

Write-Host "[OK] Phase2b harness action completed successfully."
Exit-Harness 0
