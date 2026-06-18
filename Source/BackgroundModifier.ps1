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
    [ValidateSet("Run", "Setup")]
    [string]$Action = "Run",
    [string]$RuntimeRoot = "C:\BackgroundMotives",
    [string]$StateFilePath,
    [string]$LogRoot,
    [switch]$Phase1Only,
    [switch]$Phase2Only
)

if ($HelpMode) {
    Write-Host "BackgroundModifier orchestrator"
    Write-Host "  -Action       Run (default) or Setup"
    Write-Host "  -Phase1Only   Run renderer phase only"
    Write-Host "  -Phase2Only   Run setter phase only"
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

function Test-AutomationEnabledMode {
    param(
        [string]$StateFilePath
    )

    $state = Get-RuntimeState -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "automation") -or $null -eq $state.automation) {
        return $true
    }

    $automation = $state.automation
    if (-not ($automation.PSObject.Properties.Name -contains "enabledmode")) {
        return $true
    }

    return [bool]$automation.enabledmode
}

function Get-OrchestratorForwardArgsForRelaunch {
    $forwardArgs = @(
        if ($TraceMode) { "-TraceMode" }
        if ($RuntimeRoot) { "-RuntimeRoot"; $RuntimeRoot }
        if ($StateFilePath) { "-StateFilePath"; $StateFilePath }
        if ($LogRoot) { "-LogRoot"; $LogRoot }
        if ($Phase1Only) { "-Phase1Only" }
        if ($Phase2Only) { "-Phase2Only" }
    )

    return $forwardArgs
}

function Test-IsInteractiveSession {
    try {
        return [Environment]::UserInteractive
    }
    catch {
        return $true
    }
}

function Test-IsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Restart-ScriptElevated {
    param(
        [string[]]$ForwardArgs
    )

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwsh = if ($pwshCmd) { $pwshCmd.Source } else { "powershell.exe" }

    $argumentList = @(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$PSCommandPath`""
    ) + $ForwardArgs

    Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $argumentList | Out-Null
}

function Set-OrchestratorLifecycleState {
    param(
        [string]$StateFilePath,
        [string]$Action,
        [string]$Status,
        [string]$Details = "",
        [AllowNull()]
        [object]$EnabledMode = $null
    )

    $state = Get-RuntimeState -StateFilePath $StateFilePath

    if (-not ($state.PSObject.Properties.Name -contains "lifecycle") -or $null -eq $state.lifecycle) {
        Set-StateObjectProperty -Object $state -Name "lifecycle" -Value ([pscustomobject]@{})
    }

    Set-StateObjectProperty -Object $state.lifecycle -Name "lastAction" -Value $Action
    Set-StateObjectProperty -Object $state.lifecycle -Name "lastStatus" -Value $Status
    Set-StateObjectProperty -Object $state.lifecycle -Name "lastDetails" -Value $Details
    Set-StateObjectProperty -Object $state.lifecycle -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))

    if (-not ($state.PSObject.Properties.Name -contains "automation") -or $null -eq $state.automation) {
        Set-StateObjectProperty -Object $state -Name "automation" -Value ([pscustomobject]@{})
    }

    if ($null -ne $EnabledMode) {
        Set-StateObjectProperty -Object $state.automation -Name "enabledmode" -Value ([bool]$EnabledMode)
    }
    Set-StateObjectProperty -Object $state.automation -Name "lastLifecycleAction" -Value $Action
    Set-StateObjectProperty -Object $state.automation -Name "lastLifecycleStatus" -Value $Status
    Set-StateObjectProperty -Object $state.automation -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))

    [void](Save-RuntimeState -StateFilePath $StateFilePath -StateObject $state)
}

function Get-AutomationTaskNames {
    return @(
        "BackgroundModifier-Startup",
        "BackgroundModifier-Renderer",
        "BackgroundModifier-Setter"
    )
}

function Set-AutomationTaskState {
    param(
        [bool]$Enable
    )

    $taskNames = Get-AutomationTaskNames
    $missing = @()
    $failed = @()
    $changed = @()

    foreach ($taskName in $taskNames) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            $missing += $taskName
            continue
        }

        try {
            if ($Enable) {
                Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
            }
            else {
                Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
            }

            $changed += $taskName
        }
        catch {
            $failed += "${taskName}: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Changed = $changed
        Missing = $missing
        Failed  = $failed
    }
}

function Get-SetupScriptPath {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    return Join-Path $repoRoot "Install\Setup.ps1"
}

function Invoke-SetupAction {
    param(
        [string]$StateFilePath
    )

    $desiredEnabledMode = Test-AutomationEnabledMode -StateFilePath $StateFilePath
    $setupScript = Get-SetupScriptPath
    if (-not (Test-Path $setupScript)) {
        Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SetupAction" -Status "failed" -Details "Setup script missing: $setupScript" -EnabledMode $desiredEnabledMode
        Write-Host "[X] Setup action unavailable. Missing script: $setupScript"
        return $false
    }

    Write-Host "[INFO] Running setup action from orchestrator."

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwsh = if ($pwshCmd) { $pwshCmd.Source } else { "powershell.exe" }

    $argumentList = @(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$setupScript`""
    )
    if ($TraceMode) {
        $argumentList += "-TraceMode"
    }

    try {
        [int]$setupExit = 0

        if (-not (Test-IsElevated)) {
            if (-not (Test-IsInteractiveSession)) {
                Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SetupAction" -Status "blocked" -Details "Setup action requires interactive elevation" -EnabledMode $desiredEnabledMode
                Write-Host "[X] Setup action requires an interactive session for elevation prompt."
                return $false
            }

            Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SetupAction" -Status "elevation-requested" -Details "Elevated setup action requested" -EnabledMode $desiredEnabledMode
            $p = Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $argumentList -Wait -PassThru
            $setupExit = [int]$p.ExitCode
        }
        else {
            $setupParams = @{}
            if ($TraceMode) { $setupParams.TraceMode = $true }

            & $setupScript @setupParams
            if ($LASTEXITCODE -is [int]) {
                $setupExit = $LASTEXITCODE
            }
        }

        if ($setupExit -ne 0) {
            Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SetupAction" -Status "failed" -Details "Setup exit code: $setupExit" -EnabledMode $desiredEnabledMode
            Write-Host "[X] Setup action failed with exit code $setupExit"
            return $false
        }

        Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SetupAction" -Status "completed" -Details "Setup completed successfully" -EnabledMode $desiredEnabledMode
        Write-Host "[OK] Setup action completed successfully."
        return $true
    }
    catch {
        Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SetupAction" -Status "failed" -Details "Setup invocation exception: $($_.Exception.Message)" -EnabledMode $desiredEnabledMode
        Write-Host "[X] Setup action failed: $($_.Exception.Message)"
        return $false
    }
}

function Ensure-AutomationTaskModeFromState {
    param(
        [string]$StateFilePath
    )

    $desiredEnabledMode = Test-AutomationEnabledMode -StateFilePath $StateFilePath
    $taskNames = Get-AutomationTaskNames
    $missing = @()
    $mismatch = @()

    foreach ($taskName in $taskNames) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            $missing += $taskName
            continue
        }

        $currentEnabled = $true
        try {
            $currentEnabled = [bool]$task.Settings.Enabled
        }
        catch {
            $currentEnabled = $true
        }

        if ($currentEnabled -ne $desiredEnabledMode) {
            $mismatch += $taskName
        }
    }

    if ($desiredEnabledMode -and $missing.Count -gt 0) {
        Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SyncAutomationMode" -Status "failed" -Details "Required tasks missing while enabledmode=True: $($missing -join ', ')" -EnabledMode $desiredEnabledMode
        Write-Host "[X] Required automation tasks are missing while automation.enabledmode=True"
        foreach ($name in $missing) { Write-Host "[X] Missing task: $name" }
        return $false
    }

    if ($mismatch.Count -eq 0) {
        return $true
    }

    if (-not (Test-IsElevated)) {
        if (Test-IsInteractiveSession) {
            Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SyncAutomationMode" -Status "elevation-requested" -Details "Task mode mismatch requires elevated sync" -EnabledMode $desiredEnabledMode
            Write-Host "[INFO] Relaunching elevated to sync automation task mode to state."
            Restart-ScriptElevated -ForwardArgs (Get-OrchestratorForwardArgsForRelaunch)
            exit 0
        }

        Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SyncAutomationMode" -Status "blocked" -Details "Task mode mismatch requires elevation in non-interactive session" -EnabledMode $desiredEnabledMode
        Write-Host "[X] Automation task mode mismatch requires elevation and an interactive session."
        return $false
    }

    $taskResult = Set-AutomationTaskState -Enable:$desiredEnabledMode
    foreach ($name in $taskResult.Changed) {
        Write-Host "[OK] Synced task state: $name"
    }
    foreach ($name in $taskResult.Missing) {
        Write-Host "[WARN] Missing task during sync: $name"
    }
    foreach ($err in $taskResult.Failed) {
        Write-Host "[X] $err"
    }

    if ($taskResult.Failed.Count -gt 0) {
        Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SyncAutomationMode" -Status "failed" -Details "Sync failures: $($taskResult.Failed.Count)" -EnabledMode $desiredEnabledMode
        return $false
    }

    Set-OrchestratorLifecycleState -StateFilePath $StateFilePath -Action "SyncAutomationMode" -Status "completed" -Details "SyncedTasks=$($taskResult.Changed.Count)" -EnabledMode $desiredEnabledMode
    return $true
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

if ($Action -eq "Setup") {
    if (Invoke-SetupAction -StateFilePath $stateFile) {
        exit 0
    }
    exit 1
}

if (-not (Ensure-AutomationTaskModeFromState -StateFilePath $stateFile)) {
    exit 1
}

if (-not (Test-AutomationEnabledMode -StateFilePath $stateFile)) {
    Write-Host "[X] Automation is disabled (automation.enabledmode=False)."
    Write-Host "[INFO] Update state automation.enabledmode=True and run orchestrator in an interactive session."
    Set-OrchestratorBlockedReason -StateFilePath $stateFile -Reason "AutomationDisabledMode"
    Set-OrchestratorLifecycleState -StateFilePath $stateFile -Action "PhaseExecution" -Status "blocked" -Details "automation.enabledmode=False" -EnabledMode $false
    exit 1
}

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
