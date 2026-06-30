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
    [switch]$HelpMode
)

<#
    Script: BackgroundInstallationVerifier.ps1
    Version: 10.0.0
    Author: Rolf Bercht
    Purpose: Deterministic verification of BackgroundModifier installation.

.SYNOPSIS
    Verifies BackgroundModifier runtime installation state.

.DESCRIPTION
    Checks required runtime directories and files, then validates scheduled
    task action paths against the deployed startup and phase2a harness scripts.

.PARAMETER TraceMode
    Enables transcript logging for verifier execution.
    Alias: t

.PARAMETER DetailLevel
    Expected logging detail level override (m/n/d/f).
    Alias: d

.PARAMETER BcdLogEnabled
    Expected BCDEDIT raw logging override.
    Alias: b

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

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

# Import Constants to bind paths
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

$ScriptVersion = "10.0.0"

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
$Phase2aHarnessScript = Join-Path $DeployedRoot "Source\BackgroundPhase2aHarness.ps1"
$Phase2bHarnessScript = Join-Path $DeployedRoot "Source\BackgroundPhase2bHarness.ps1"
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
    $Phase2aHarnessScript,
    $Phase2bHarnessScript,
    $RenderToolsModule,
    $SeedStateFile,
    $SeedDesktopBase,
    $SeedLogonBase,
    $RuntimeStateFile,
    $RuntimeDesktopBase,
    $RuntimeLogonBase
)

$PersistedLoggingDetailLevel = $null
$PersistedBcdLogEnabled = $null

try {
    if (Test-Path $RuntimeStateFile) {
        $runtimeStateRaw = Get-Content -Path $RuntimeStateFile -Raw
        if (-not [string]::IsNullOrWhiteSpace($runtimeStateRaw)) {
            $runtimeState = $runtimeStateRaw | ConvertFrom-Json -ErrorAction Stop
            if ($runtimeState -and ($runtimeState.PSObject.Properties.Name -contains "logging") -and $runtimeState.logging) {
                if ($runtimeState.logging.PSObject.Properties.Name -contains "detailLevel") {
                    $PersistedLoggingDetailLevel = [string]$runtimeState.logging.detailLevel
                }
                if ($runtimeState.logging.PSObject.Properties.Name -contains "bcdLogEnabled") {
                    $PersistedBcdLogEnabled = [bool]$runtimeState.logging.bcdLogEnabled
                }
            }
        }
    }
}
catch {
    Write-Host "[WARN] Could not read logging defaults from runtime state: $($_.Exception.Message)"
}

$ExpectedDetailLevel = if ($PSBoundParameters.ContainsKey("DetailLevel")) {
    $DetailLevel.ToLowerInvariant()
}
elseif ($PersistedLoggingDetailLevel) {
    $PersistedLoggingDetailLevel.ToLowerInvariant()
}
elseif ($TraceMode) {
    "d"
}
else {
    "n"
}

$ExpectedTraceMode = $ExpectedDetailLevel -in @("d", "f")
$ExpectedBcdLogEnabled = if ($PSBoundParameters.ContainsKey("BcdLogEnabled")) {
    [bool]$BcdLogEnabled
}
elseif ($null -ne $PersistedBcdLogEnabled) {
    [bool]$PersistedBcdLogEnabled
}
else {
    $ExpectedDetailLevel -in @("d", "f")
}

Write-Host "[INFO] Expected logging defaults -> detail=$($ExpectedDetailLevel.ToUpperInvariant()) bcdLog=$ExpectedBcdLogEnabled traceMode=$ExpectedTraceMode"

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
        [string]$ExpectedScriptPath,
        [string]$ExpectedDetailLevel,
        [bool]$ExpectedTraceMode,
        [bool]$ExpectedBcdLogEnabled
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

    $hasTraceArg = $normalizedArgs -like "*-TraceMode*"
    $hasHiddenWindow = $normalizedArgs -like "*-WindowStyle Hidden*"
    $hasBcdLogArg = $normalizedArgs -like "*-BcdLogEnabled*"
    $hasDetailLevelArg = $normalizedArgs -match "(?i)-DetailLevel\s+([MNDF])"

    if ($hasDetailLevelArg) {
        $actualDetailLevel = $Matches[1].ToLowerInvariant()
        if ($actualDetailLevel -eq $ExpectedDetailLevel) {
            Write-Host "[OK] $TaskName detail level matches expected: $($ExpectedDetailLevel.ToUpperInvariant())"
        }
        else {
            Write-Host "[WARN] $TaskName detail level mismatch: expected $($ExpectedDetailLevel.ToUpperInvariant()) actual $($actualDetailLevel.ToUpperInvariant())"
        }
    }
    else {
        Write-Host "[WARN] $TaskName missing -DetailLevel argument"
    }

    if ($ExpectedBcdLogEnabled) {
        if ($hasBcdLogArg) {
            Write-Host "[OK] $TaskName includes -BcdLogEnabled argument"
        }
        else {
            Write-Host "[WARN] $TaskName is missing expected -BcdLogEnabled argument"
        }
    }
    else {
        if ($hasBcdLogArg) {
            Write-Host "[WARN] $TaskName unexpectedly includes -BcdLogEnabled argument"
        }
        else {
            Write-Host "[OK] $TaskName has no -BcdLogEnabled argument"
        }
    }

    if ($ExpectedTraceMode) {
        if ($hasTraceArg) {
            Write-Host "[OK] $TaskName includes -TraceMode argument"
        }
        else {
            Write-Host "[WARN] $TaskName is missing expected -TraceMode argument"
        }

        if ($hasHiddenWindow) {
            Write-Host "[WARN] $TaskName is hidden although trace mode is expected"
        }
        else {
            Write-Host "[OK] $TaskName is not hidden in trace mode"
        }
    }
    else {
        if ($hasTraceArg) {
            Write-Host "[WARN] $TaskName unexpectedly includes -TraceMode argument"
        }
        else {
            Write-Host "[OK] $TaskName has no -TraceMode argument"
        }

        if ($hasHiddenWindow) {
            Write-Host "[OK] $TaskName uses hidden window style"
        }
        else {
            Write-Host "[WARN] $TaskName is not hidden in non-trace mode"
        }
    }
}

Test-TaskActionPath -TaskName "BackgroundModifier-Startup"  -ExpectedScriptPath $OrchestratorScript -ExpectedDetailLevel $ExpectedDetailLevel -ExpectedTraceMode $ExpectedTraceMode -ExpectedBcdLogEnabled $ExpectedBcdLogEnabled
Test-TaskActionPath -TaskName "BackgroundModifier-Phase2a" -ExpectedScriptPath $Phase2aHarnessScript -ExpectedDetailLevel $ExpectedDetailLevel -ExpectedTraceMode $ExpectedTraceMode -ExpectedBcdLogEnabled $ExpectedBcdLogEnabled

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

