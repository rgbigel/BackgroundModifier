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

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [object]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-RuntimeState {
    param(
        [string]$StateFilePath
    )

    if (-not (Test-Path $StateFilePath)) {
        return [pscustomobject]@{}
    }

    try {
        $raw = Get-Content -Path $StateFilePath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{}
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) {
            return [pscustomobject]@{}
        }

        return $parsed
    }
    catch {
        Write-Host "[WARN] State file unreadable: $StateFilePath"
        return [pscustomobject]@{}
    }
}

function Save-RuntimeState {
    param(
        [string]$StateFilePath,
        [object]$StateObject
    )

    try {
        $stateDir = Split-Path $StateFilePath -Parent
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }

        $json = $StateObject | ConvertTo-Json -Depth 20
        Set-Content -Path $StateFilePath -Value $json -Encoding UTF8 -Force
        return $true
    }
    catch {
        Write-Host "[WARN] Failed writing state file ${StateFilePath}: $($_.Exception.Message)"
        return $false
    }
}

function Set-OrchestratorBlockedReason {
    param(
        [string]$StateFilePath,
        [string]$Reason
    )

    $state = Get-RuntimeState -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "phase") -or $null -eq $state.phase) {
        Set-ObjectProperty -Object $state -Name "phase" -Value ([pscustomobject]@{})
    }

    Set-ObjectProperty -Object $state.phase -Name "currentPhase" -Value "Blocked"
    Set-ObjectProperty -Object $state.phase -Name "blockedReason" -Value $Reason

    if (-not ($state.PSObject.Properties.Name -contains "meta") -or $null -eq $state.meta) {
        Set-ObjectProperty -Object $state -Name "meta" -Value ([pscustomobject]@{})
    }
    Set-ObjectProperty -Object $state.meta -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))

    [void](Save-RuntimeState -StateFilePath $StateFilePath -StateObject $state)
}

function Get-Phase1Readiness {
    param(
        [string]$StateFilePath
    )

    $state = Get-RuntimeState -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "phase") -or $null -eq $state.phase) {
        return [pscustomobject]@{ Known = $false; IsReady = $false; Status = $null }
    }

    $phase = $state.phase
    if (-not ($phase.PSObject.Properties.Name -contains "phase1Status")) {
        return [pscustomobject]@{ Known = $false; IsReady = $false; Status = $null }
    }

    $status = [string]$phase.phase1Status
    if ([string]::IsNullOrWhiteSpace($status)) {
        return [pscustomobject]@{ Known = $false; IsReady = $false; Status = $null }
    }

    $readyStatuses = @("ready", "completed", "success", "ok")
    $isReady = $readyStatuses -contains $status.ToLowerInvariant()
    return [pscustomobject]@{ Known = $true; IsReady = $isReady; Status = $status }
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

$stateFile = "C:\BackgroundMotives\assets\state.json"
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
