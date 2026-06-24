<#
    Module: StateTools.psm1
    Version: 1.0.1
    Purpose: Shared state.json helpers with explicit context and contract surface.

    Caller Contract (Module-Caller State Update Responsibility):
      This module is the ONLY module that directly modifies state.json. Functions here are used by callers to:
      - Get-RuntimeState: Read current state.json; safe, read-only
      - Set-RuntimeState: Write state.json atomically; MUST be called after module operations that change state
      - Set-StateObjectProperty: Update individual state properties; used by callers to accumulate changes
      - Important: Callers must accumulate all changes, then call Set-RuntimeState once to avoid partial writes
      - Atomic writes ensure Phase 2a/2b concurrent runs don't corrupt state
      - Caller must include audit trail: component version, timestamp, source
#>

function Set-StateObjectProperty {
    [CmdletBinding()]
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

function Get-StateFilePathFromContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [string]$StateFilePath
    )

    if (-not [string]::IsNullOrWhiteSpace($StateFilePath)) {
        return $StateFilePath
    }

    if ($Context -and ($Context.PSObject.Properties.Name -contains "StateFilePath")) {
        $contextPath = [string]$Context.StateFilePath
        if (-not [string]::IsNullOrWhiteSpace($contextPath)) {
            return $contextPath
        }
    }

    throw "State file path was not provided and Context.StateFilePath is missing."
}

function Read-RuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [string]$StateFilePath,
        [switch]$Quiet
    )

    $resolvedStateFile = Get-StateFilePathFromContext -Context $Context -StateFilePath $StateFilePath

    if (-not (Test-Path $resolvedStateFile)) {
        return [pscustomobject]@{}
    }

    try {
        $raw = Get-Content -Path $resolvedStateFile -Raw
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
        if (-not $Quiet) {
            Write-Host "[WARN] State file is unreadable and will be re-initialized when updated: $resolvedStateFile"
        }
        return [pscustomobject]@{}
    }
}

function Write-RuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [object]$StateObject,

        [string]$StateFilePath,
        [scriptblock]$OnPersist
    )

    $resolvedStateFile = Get-StateFilePathFromContext -Context $Context -StateFilePath $StateFilePath

    try {
        $stateDir = Split-Path $resolvedStateFile -Parent
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }

        if (-not ($StateObject.PSObject.Properties.Name -contains "meta") -or $null -eq $StateObject.meta) {
            Set-StateObjectProperty -Object $StateObject -Name "meta" -Value ([pscustomobject]@{})
        }

        Set-StateObjectProperty -Object $StateObject.meta -Name "schemaVersion" -Value $Context.SchemaVersion
        Set-StateObjectProperty -Object $StateObject.meta -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))

        $json = $StateObject | ConvertTo-Json -Depth 20
        Set-Content -Path $resolvedStateFile -Value $json -Encoding UTF8 -Force

        if ($OnPersist) {
            & $OnPersist $resolvedStateFile
        }

        return $true
    }
    catch {
        Write-Host "[WARN] Failed to persist runtime state to ${resolvedStateFile}: $($_.Exception.Message)"
        return $false
    }
}

function Update-PhaseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateSet("phase1", "phase2")]
        [string]$PhaseKey,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$CurrentPhase,
        [AllowNull()]
        [string]$BlockedReason,
        [string]$StateFilePath,
        [scriptblock]$OnPersist
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath

    if (-not ($state.PSObject.Properties.Name -contains "phase") -or $null -eq $state.phase) {
        Set-StateObjectProperty -Object $state -Name "phase" -Value ([pscustomobject]@{})
    }

    if ([string]::IsNullOrWhiteSpace($CurrentPhase)) {
        $CurrentPhase = if ($PhaseKey -eq "phase1") { "Phase1" } else { "Phase2" }
    }

    Set-StateObjectProperty -Object $state.phase -Name "currentPhase" -Value $CurrentPhase
    Set-StateObjectProperty -Object $state.phase -Name "${PhaseKey}Status" -Value $Status
    Set-StateObjectProperty -Object $state.phase -Name "blockedReason" -Value $BlockedReason

    [void](Write-RuntimeState -Context $Context -StateObject $state -StateFilePath $StateFilePath -OnPersist $OnPersist)
}

function Get-PhaseReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [ValidateSet("phase1", "phase2")]
        [string]$PhaseKey = "phase1",

        [string]$StateFilePath,
        [bool]$UnknownIsReady = $false
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath

    if (-not ($state.PSObject.Properties.Name -contains "phase") -or $null -eq $state.phase) {
        return [pscustomobject]@{ Known = $false; IsReady = $UnknownIsReady; Status = $null }
    }

    $statusProperty = "${PhaseKey}Status"
    $phase = $state.phase
    if (-not ($phase.PSObject.Properties.Name -contains $statusProperty)) {
        return [pscustomobject]@{ Known = $false; IsReady = $UnknownIsReady; Status = $null }
    }

    $status = [string]$phase.$statusProperty
    if ([string]::IsNullOrWhiteSpace($status)) {
        return [pscustomobject]@{ Known = $false; IsReady = $UnknownIsReady; Status = $null }
    }

    $readyStatuses = @("ready", "completed", "success", "ok")
    $isReady = $readyStatuses -contains $status.ToLowerInvariant()

    return [pscustomobject]@{ Known = $true; IsReady = $isReady; Status = $status }
}

function Get-PendingLogonSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [string]$StateFilePath
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath

    if (-not ($state.PSObject.Properties.Name -contains "transient")) {
        return $null
    }

    $transient = $state.transient
    if ($null -eq $transient) {
        return $null
    }

    if (-not ($transient.PSObject.Properties.Name -contains "pendingLogon")) {
        return $null
    }

    $pending = $transient.pendingLogon
    if ($null -eq $pending) {
        return $null
    }

    if ($pending -is [string]) {
        return $pending
    }

    if ($pending.PSObject.Properties.Name -contains "sourcePath") {
        return [string]$pending.sourcePath
    }

    return $null
}

function Set-PendingLogonSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [string]$Reason = "LockScreenApplyRequiresElevation",
        [string]$StateFilePath,
        [scriptblock]$OnPersist
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath

    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        Set-StateObjectProperty -Object $state -Name "transient" -Value ([pscustomobject]@{})
    }

    $pending = [pscustomobject]@{
        sourcePath        = $SourcePath
        requestedAtUtc    = (Get-Date).ToUniversalTime().ToString("o")
        reason            = $Reason
        requiresElevation = $true
        status            = "pending"
    }

    Set-StateObjectProperty -Object $state.transient -Name "pendingLogon" -Value $pending
    return (Write-RuntimeState -Context $Context -StateObject $state -StateFilePath $StateFilePath -OnPersist $OnPersist)
}

function Clear-PendingLogonSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [string]$StateFilePath,
        [scriptblock]$OnPersist
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $true
    }

    Set-StateObjectProperty -Object $state.transient -Name "pendingLogon" -Value $null
    return (Write-RuntimeState -Context $Context -StateObject $state -StateFilePath $StateFilePath -OnPersist $OnPersist)
}

function Set-InteractiveElevationRelaunchMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [int]$ProcessId,
        [string]$StateFilePath,
        [scriptblock]$OnPersist
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        Set-StateObjectProperty -Object $state -Name "transient" -Value ([pscustomobject]@{})
    }

    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchRequestedAtUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))
    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchPid" -Value $ProcessId

    if ($state.transient.PSObject.Properties.Name -contains "pendingLogon" -and $null -ne $state.transient.pendingLogon) {
        $pending = $state.transient.pendingLogon
        if ($pending -isnot [string]) {
            Set-StateObjectProperty -Object $pending -Name "status" -Value "relaunch_requested"
        }
    }

    return (Write-RuntimeState -Context $Context -StateObject $state -StateFilePath $StateFilePath -OnPersist $OnPersist)
}

function Clear-InteractiveElevationRelaunch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [string]$StateFilePath,
        [scriptblock]$OnPersist
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $true
    }

    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchRequestedAtUtc" -Value $null
    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchPid" -Value $null
    return (Write-RuntimeState -Context $Context -StateObject $state -StateFilePath $StateFilePath -OnPersist $OnPersist)
}

function Test-InteractiveElevationRelaunchRecentlyRequested {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [int]$WindowSeconds = 20,
        [string]$StateFilePath
    )

    $state = Read-RuntimeState -Context $Context -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $false
    }

    $transient = $state.transient
    if (-not ($transient.PSObject.Properties.Name -contains "interactiveElevationRelaunchRequestedAtUtc")) {
        return $false
    }

    $stampRaw = [string]$transient.interactiveElevationRelaunchRequestedAtUtc
    if ([string]::IsNullOrWhiteSpace($stampRaw)) {
        return $false
    }

    [datetime]$stamp = [datetime]::MinValue
    if (-not [datetime]::TryParse($stampRaw, [ref]$stamp)) {
        return $false
    }

    $age = ((Get-Date).ToUniversalTime() - $stamp.ToUniversalTime()).TotalSeconds
    return ($age -ge 0 -and $age -lt $WindowSeconds)
}

function Get-StateToolsContract {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ContractName    = "StateTools"
        ContractVersion = "1.0.0"
        RequiredContext = "RepoRuntimeContext 1.0.0"
        PublicFunctions = @(
            "Read-RuntimeState",
            "Write-RuntimeState",
            "Update-PhaseState",
            "Get-PhaseReadiness",
            "Get-PendingLogonSource",
            "Set-PendingLogonSource",
            "Clear-PendingLogonSource",
            "Set-InteractiveElevationRelaunchMarker",
            "Clear-InteractiveElevationRelaunch",
            "Test-InteractiveElevationRelaunchRecentlyRequested"
        )
    }
}

Export-ModuleMember -Function Set-StateObjectProperty, Read-RuntimeState, Write-RuntimeState, Update-PhaseState, Get-PhaseReadiness, Get-PendingLogonSource, Set-PendingLogonSource, Clear-PendingLogonSource, Set-InteractiveElevationRelaunchMarker, Clear-InteractiveElevationRelaunch, Test-InteractiveElevationRelaunchRecentlyRequested, Get-StateToolsContract
<#
    Module: StateTools.psm1
    Version: 1.0.0
    Purpose: Shared state.json helpers driven by explicit runtime context.
#>

function Set-StateObjectProperty {
    [CmdletBinding()]
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

function Assert-RepoRuntimeContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    $required = @("RepoName", "StateFilePath", "LogRoot", "SchemaVersion")
    foreach ($name in $required) {
        if (-not ($Context.PSObject.Properties.Name -contains $name)) {
            throw "Runtime context missing required field '$name'."
        }

        if ([string]::IsNullOrWhiteSpace([string]$Context.$name)) {
            throw "Runtime context field '$name' is empty."
        }
    }
}

function Get-RepoRuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [switch]$WarnOnUnreadable
    )

    Assert-RepoRuntimeContext -Context $Context

    if (-not (Test-Path $Context.StateFilePath)) {
        return [pscustomobject]@{
            schemaVersion = $Context.SchemaVersion
        }
    }

    try {
        $raw = Get-Content -Path $Context.StateFilePath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{
                schemaVersion = $Context.SchemaVersion
            }
        }

        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $parsed) {
            return [pscustomobject]@{
                schemaVersion = $Context.SchemaVersion
            }
        }

        if (-not ($parsed.PSObject.Properties.Name -contains "schemaVersion")) {
            Set-StateObjectProperty -Object $parsed -Name "schemaVersion" -Value $Context.SchemaVersion
        }

        return $parsed
    }
    catch {
        if ($WarnOnUnreadable) {
            Write-Host "[WARN] State file is unreadable and will be re-initialized when updated: $($Context.StateFilePath)"
        }

        return [pscustomobject]@{
            schemaVersion = $Context.SchemaVersion
        }
    }
}

function Save-RepoRuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [object]$StateObject,

        [switch]$WarnOnFailure
    )

    Assert-RepoRuntimeContext -Context $Context

    try {
        $stateDir = Split-Path $Context.StateFilePath -Parent
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }

        if (-not ($StateObject.PSObject.Properties.Name -contains "schemaVersion")) {
            Set-StateObjectProperty -Object $StateObject -Name "schemaVersion" -Value $Context.SchemaVersion
        }

        $json = $StateObject | ConvertTo-Json -Depth 20
        Set-Content -Path $Context.StateFilePath -Value $json -Encoding UTF8 -Force
        return $true
    }
    catch {
        if ($WarnOnFailure) {
            Write-Host "[WARN] Failed to persist runtime state to $($Context.StateFilePath): $($_.Exception.Message)"
        }

        return $false
    }
}

function Add-StateSections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$StateObject
    )

    if (-not ($StateObject.PSObject.Properties.Name -contains "phase") -or $null -eq $StateObject.phase) {
        Set-StateObjectProperty -Object $StateObject -Name "phase" -Value ([pscustomobject]@{})
    }

    if (-not ($StateObject.PSObject.Properties.Name -contains "meta") -or $null -eq $StateObject.meta) {
        Set-StateObjectProperty -Object $StateObject -Name "meta" -Value ([pscustomobject]@{})
    }
}

function Update-RepoPhaseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateSet("phase1", "phase2")]
        [string]$Phase,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$CurrentPhase,

        [AllowNull()]
        [string]$BlockedReason
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    Add-StateSections -StateObject $state

    Set-StateObjectProperty -Object $state.phase -Name "currentPhase" -Value $CurrentPhase
    Set-StateObjectProperty -Object $state.phase -Name "$($Phase)Status" -Value $Status
    Set-StateObjectProperty -Object $state.phase -Name "blockedReason" -Value $BlockedReason

    Set-StateObjectProperty -Object $state.meta -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))

    [void](Save-RepoRuntimeState -Context $Context -StateObject $state -WarnOnFailure)
}

function Get-RepoPhaseReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [ValidateSet("phase1", "phase2")]
        [string]$Phase = "phase1",

        [bool]$UnknownIsReady = $false
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    if (-not ($state.PSObject.Properties.Name -contains "phase") -or $null -eq $state.phase) {
        return [pscustomobject]@{ Known = $false; IsReady = $UnknownIsReady; Status = $null }
    }

    $statusName = "$($Phase)Status"
    if (-not ($state.phase.PSObject.Properties.Name -contains $statusName)) {
        return [pscustomobject]@{ Known = $false; IsReady = $UnknownIsReady; Status = $null }
    }

    $status = [string]$state.phase.$statusName
    if ([string]::IsNullOrWhiteSpace($status)) {
        return [pscustomobject]@{ Known = $false; IsReady = $UnknownIsReady; Status = $null }
    }

    $readyStatuses = @("ready", "completed", "success", "ok")
    $isReady = $readyStatuses -contains $status.ToLowerInvariant()
    return [pscustomobject]@{ Known = $true; IsReady = $isReady; Status = $status }
}

function Get-RepoPendingLogonSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable

    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $null
    }

    if (-not ($state.transient.PSObject.Properties.Name -contains "pendingLogon")) {
        return $null
    }

    $pending = $state.transient.pendingLogon
    if ($null -eq $pending) {
        return $null
    }

    if ($pending -is [string]) {
        return $pending
    }

    if ($pending.PSObject.Properties.Name -contains "sourcePath") {
        return [string]$pending.sourcePath
    }

    return $null
}

function Set-RepoPendingLogonSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [string]$Reason = "LockScreenApplyRequiresElevation"
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable

    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        Set-StateObjectProperty -Object $state -Name "transient" -Value ([pscustomobject]@{})
    }

    $pending = [pscustomobject]@{
        sourcePath        = $SourcePath
        requestedAtUtc    = (Get-Date).ToUniversalTime().ToString("o")
        reason            = $Reason
        requiresElevation = $true
        status            = "pending"
    }

    Set-StateObjectProperty -Object $state.transient -Name "pendingLogon" -Value $pending
    return (Save-RepoRuntimeState -Context $Context -StateObject $state -WarnOnFailure)
}

function Clear-RepoPendingLogonSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $true
    }

    Set-StateObjectProperty -Object $state.transient -Name "pendingLogon" -Value $null
    return (Save-RepoRuntimeState -Context $Context -StateObject $state -WarnOnFailure)
}

function Set-RepoInteractiveRelaunchMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [int]$Pid = $PID
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        Set-StateObjectProperty -Object $state -Name "transient" -Value ([pscustomobject]@{})
    }

    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchRequestedAtUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))
    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchPid" -Value $Pid

    if ($state.transient.PSObject.Properties.Name -contains "pendingLogon" -and $null -ne $state.transient.pendingLogon) {
        $pending = $state.transient.pendingLogon
        if ($pending -isnot [string]) {
            Set-StateObjectProperty -Object $pending -Name "status" -Value "relaunch_requested"
        }
    }

    return (Save-RepoRuntimeState -Context $Context -StateObject $state -WarnOnFailure)
}

function Clear-RepoInteractiveRelaunchMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $true
    }

    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchRequestedAtUtc" -Value $null
    Set-StateObjectProperty -Object $state.transient -Name "interactiveElevationRelaunchPid" -Value $null
    return (Save-RepoRuntimeState -Context $Context -StateObject $state -WarnOnFailure)
}

function Test-RepoInteractiveRelaunchRecentlyRequested {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [int]$WindowSeconds = 20
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    if (-not ($state.PSObject.Properties.Name -contains "transient") -or $null -eq $state.transient) {
        return $false
    }

    $transient = $state.transient
    if (-not ($transient.PSObject.Properties.Name -contains "interactiveElevationRelaunchRequestedAtUtc")) {
        return $false
    }

    $stampRaw = [string]$transient.interactiveElevationRelaunchRequestedAtUtc
    if ([string]::IsNullOrWhiteSpace($stampRaw)) {
        return $false
    }

    [datetime]$stamp = [datetime]::MinValue
    if (-not [datetime]::TryParse($stampRaw, [ref]$stamp)) {
        return $false
    }

    $age = ((Get-Date).ToUniversalTime() - $stamp.ToUniversalTime()).TotalSeconds
    return ($age -ge 0 -and $age -lt $WindowSeconds)
}

function Set-RepoBlockedReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [string]$CurrentPhase = "Blocked"
    )

    $state = Get-RepoRuntimeState -Context $Context -WarnOnUnreadable
    Add-StateSections -StateObject $state

    Set-StateObjectProperty -Object $state.phase -Name "currentPhase" -Value $CurrentPhase
    Set-StateObjectProperty -Object $state.phase -Name "blockedReason" -Value $Reason
    Set-StateObjectProperty -Object $state.meta -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))

    [void](Save-RepoRuntimeState -Context $Context -StateObject $state -WarnOnFailure)
}

function Get-RepoStateToolsContract {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ContractName      = "StateTools"
        ContractVersion   = "1.0.0"
        RequiredContext   = @("RepoName", "StateFilePath", "LogRoot", "SchemaVersion")
        ExportedFunctions = @(
            "Get-RepoRuntimeState",
            "Save-RepoRuntimeState",
            "Update-RepoPhaseState",
            "Get-RepoPhaseReadiness",
            "Get-RepoPendingLogonSource",
            "Set-RepoPendingLogonSource",
            "Clear-RepoPendingLogonSource",
            "Set-RepoInteractiveRelaunchMarker",
            "Clear-RepoInteractiveRelaunchMarker",
            "Test-RepoInteractiveRelaunchRecentlyRequested",
            "Set-RepoBlockedReason"
        )
    }
}

Export-ModuleMember -Function Set-StateObjectProperty, Get-RepoRuntimeState, Save-RepoRuntimeState, Update-RepoPhaseState, Get-RepoPhaseReadiness, Get-RepoPendingLogonSource, Set-RepoPendingLogonSource, Clear-RepoPendingLogonSource, Set-RepoInteractiveRelaunchMarker, Clear-RepoInteractiveRelaunchMarker, Test-RepoInteractiveRelaunchRecentlyRequested, Set-RepoBlockedReason, Get-RepoStateToolsContract
