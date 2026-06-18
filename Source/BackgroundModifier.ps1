<#
    Script: BackgroundModifier.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Orchestrate phase-aware execution of renderer (phase 1) and setter (phase 2).
#>

[CmdletBinding()]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode,
    [string]$RuntimeRoot = "C:\BackgroundMotives",
    [string]$StateFilePath,
    [string]$LogRoot,
    [switch]$Phase1Only,
    [switch]$Phase2Only,
    [switch]$Interactive
)

if ($HelpMode) {
    Write-Host "BackgroundModifier orchestrator"
    Write-Host "  -Phase1Only   Run renderer phase only"
    Write-Host "  -Phase2Only   Run setter phase only"
    Write-Host "  -Interactive  Allow interactive prompts in setter"
    Write-Host "  -TraceMode    Enable transcript logging in child scripts"
    exit 0
}

$ModuleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
Import-Module (Join-Path $ModuleRoot "RuntimeContext.psm1") -Force
Import-Module (Join-Path $ModuleRoot "StateTools.psm1") -Force

$RuntimeContext = New-RepoRuntimeContext -RepoName "BackgroundModifier" -RuntimeRoot $RuntimeRoot -LogRoot $LogRoot -StateFilePath $StateFilePath

function Get-RuntimeState {
    param(
        [string]$StateFilePath
    )

    return Read-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath
}

function Save-RuntimeState {
    param(
        [string]$StateFilePath,
        [object]$StateObject
    )

    return (Write-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath -StateObject $StateObject)
}

function Set-OrchestratorBlockedReason {
    param(
        [string]$StateFilePath,
        [string]$Reason
    )

    $state = Get-RuntimeState -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "phase") -or $null -eq $state.phase) {
        Set-StateObjectProperty -Object $state -Name "phase" -Value ([pscustomobject]@{})
    }

    Set-StateObjectProperty -Object $state.phase -Name "currentPhase" -Value "Blocked"
    Set-StateObjectProperty -Object $state.phase -Name "blockedReason" -Value $Reason

    [void](Save-RuntimeState -StateFilePath $StateFilePath -StateObject $state)
}

function Get-Phase1Readiness {
    param(
        [string]$StateFilePath
    )

    return Get-PhaseReadiness -Context $RuntimeContext -StateFilePath $StateFilePath -PhaseKey "phase1" -UnknownIsReady $false
}

function Test-IsInteractiveSession {
    try {
        return [Environment]::UserInteractive
    }
    catch {
        return $true
    }
}

function Invoke-ToolScript {
    param(
        [string]$ScriptPath,
        [string[]]$ForwardArgs
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[X] Missing script: $ScriptPath"
        return 2
    }

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $shellExe = if ($pwshCmd) { $pwshCmd.Source } else { "powershell.exe" }

    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$ScriptPath`""
    ) + $ForwardArgs

    $p = Start-Process -FilePath $shellExe -ArgumentList $argList -Wait -PassThru
    return [int]$p.ExitCode
}

$stateFile = $RuntimeContext.StateFilePath
$rendererScript = Join-Path $PSScriptRoot "BackgroundRenderer.ps1"
$setterScript = Join-Path $PSScriptRoot "BackgroundSetter.ps1"

$phase1Info = Get-Phase1Readiness -StateFilePath $stateFile

$runPhase1 = $false
$runPhase2 = $false

if ($Phase1Only -and -not $Phase2Only) {
    $runPhase1 = $true
}
elseif ($Phase2Only -and -not $Phase1Only) {
    $runPhase2 = $true
}
else {
    # default (or both switches set): phase-aware full flow
    $runPhase1 = (-not $phase1Info.IsReady)
    $runPhase2 = $true
}

Write-Host "=== BackgroundModifier Orchestrator (v8.0.0) ==="
Write-Host "Phase1 status: $($phase1Info.Status)"
Write-Host "Plan: RunPhase1=$runPhase1 RunPhase2=$runPhase2"

if ($runPhase1) {
    $rendererArgs = @(
        if ($TraceMode) { "-TraceMode" }
    )

    Write-Host "[INFO] Running phase 1 renderer..."
    $rendererExit = Invoke-ToolScript -ScriptPath $rendererScript -ForwardArgs $rendererArgs
    if ($rendererExit -ne 0) {
        Write-Host "[X] Renderer failed with exit code $rendererExit"
        Set-OrchestratorBlockedReason -StateFilePath $stateFile -Reason "RendererFailed"
        exit $rendererExit
    }
}

if ($runPhase2) {
    $setterArgs = @(
        if ($TraceMode) { "-TraceMode" }
    )

    if ($Interactive) {
        if (Test-IsInteractiveSession) {
            $setterArgs += "-Interactive"
        }
        else {
            Write-Host "[WARN] -Interactive requested in non-interactive session; ignoring."
        }
    }

    Write-Host "[INFO] Running phase 2 setter..."
    $setterExit = Invoke-ToolScript -ScriptPath $setterScript -ForwardArgs $setterArgs
    if ($setterExit -ne 0) {
        Write-Host "[X] Setter failed with exit code $setterExit"
        Set-OrchestratorBlockedReason -StateFilePath $stateFile -Reason "SetterFailed"
        exit $setterExit
    }
}

Write-Host "[OK] Orchestrator flow completed successfully."
exit 0
