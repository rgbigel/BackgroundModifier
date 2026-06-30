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
    Script: Setup.ps1
    Version: 10.0.0
    Author: Rolf Bercht
    Purpose: Install and configure BackgroundModifier runtime structure and scheduled tasks.
    Requires: Windows 11, elevation (Administrator).

.SYNOPSIS
    Installs and configures BackgroundModifier runtime directories and scheduled tasks.

.DESCRIPTION
    Validates source layout, ensures required runtime folders exist, (re)registers
    startup and phase 2a harness tasks, then runs installation verification.

.PARAMETER TraceMode
    Legacy trace switch. Equivalent to detail level d when -DetailLevel is not provided.
    Alias: t

.PARAMETER DetailLevel
    Global logging detail level: m=minimal, n=normal, d=diagnostic, f=full.
    Alias: d

.PARAMETER BcdLogEnabled
    Enables raw BCDEDIT output logging to log files.
    Alias: b

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?

.EXAMPLE
    .\Setup.ps1

.EXAMPLE
    .\Setup.ps1 -t

.EXAMPLE
    .\Setup.ps1 -d d -b

.EXAMPLE
    .\Setup.ps1 -h
#>

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

# Import Constants to bind paths
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

# --- Constants ---
$ScriptVersion   = "10.0.0"
$RuntimeRoot     = $Global:RuntimeRoot
$AssetsRoot      = $Global:AssetsRoot
$LogRoot         = $Global:LogRoot

# Paths are derived from this script's location so Setup.ps1 works from both
# the repository (Install\) and the deployed runtime (runtimes\BackgroundModifier\Install\).
$DeployedRoot    = Split-Path $PSScriptRoot -Parent
$SourceRoot      = Join-Path $DeployedRoot "Source"
$ModulesRoot     = Join-Path $DeployedRoot "Modules"
$SeedAssetsRoot  = Join-Path $DeployedRoot "assets"
$OrchestratorScript = Join-Path $SourceRoot "BackgroundModifier.ps1"
$RendererScript  = Join-Path $SourceRoot "BackgroundRenderer.ps1"
$SetterScript    = Join-Path $SourceRoot "BackgroundSetter.ps1"
$Phase2aHarnessScript = Join-Path $SourceRoot "BackgroundPhase2aHarness.ps1"
$VerifierScript  = Join-Path $PSScriptRoot "BackgroundInstallationVerifier.ps1"
$RuntimeStateFile = Join-Path $AssetsRoot "state.json"

$TaskNameStartup  = "BackgroundModifier-Startup"
$TaskNamePhase2a  = "BackgroundModifier-Phase2a"
$ProjectName      = Split-Path $DeployedRoot -Leaf
$BToolsRoot       = $Global:DeploymentRoot
$InventoryRoot    = Join-Path $BToolsRoot "Inventory"
$InventoryFile    = Join-Path $InventoryRoot "$ProjectName.json"
$MinimumRuntimeContextContractVersion = "1.0.0"
$MinimumStateToolsContractVersion = "1.0.0"
$CompatibilityScript = Join-Path $PSScriptRoot "Test-SharedModuleCompatibility.ps1"
$SupportedTaskNames = @(
    $TaskNameStartup,
    $TaskNamePhase2a
)

$EffectiveDetailLevel = if ($PSBoundParameters.ContainsKey("DetailLevel")) {
    $DetailLevel.ToLowerInvariant()
}
elseif ($TraceMode) {
    "d"
}
else {
    "n"
}

$EffectiveTraceMode = $EffectiveDetailLevel -in @("d","f")
$EffectiveBcdLogEnabled = if ($PSBoundParameters.ContainsKey("BcdLogEnabled")) {
    [bool]$BcdLogEnabled
}
else {
    $EffectiveDetailLevel -in @("d","f")
}

# Normalize legacy switch behavior to the computed effective mode.
$TraceMode = $EffectiveTraceMode

function Remove-StaleBackgroundModifierTasks {
    param(
        [string[]]$KeepTaskNames
    )

    $existing = Get-ScheduledTask -TaskName "BackgroundModifier-*" -ErrorAction SilentlyContinue
    foreach ($task in $existing) {
        if ($KeepTaskNames -contains $task.TaskName) {
            continue
        }

        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false | Out-Null
        Write-Host "[OK] Removed stale task: $($task.TaskName)"
    }
}

function Get-ContractSnapshot {
    param(
        [string]$ModulePath
    )

    $snapshot = [pscustomobject]@{
        runtimeContext = [pscustomobject]@{ contractName = "RepoRuntimeContext"; contractVersion = "(unavailable)" }
        stateTools     = [pscustomobject]@{ contractName = "StateTools"; contractVersion = "(unavailable)" }
    }

    try {
        $runtimeContextModule = Join-Path $ModulePath "RuntimeContext.psm1"
        $stateToolsModule = Join-Path $ModulePath "StateTools.psm1"

        if (Test-Path $runtimeContextModule) {
            Import-Module $runtimeContextModule -Force -DisableNameChecking -WarningAction SilentlyContinue
            $ctxContract = Get-RepoRuntimeContextContract
            if ($ctxContract) {
                $snapshot.runtimeContext = [pscustomobject]@{
                    contractName    = [string]$ctxContract.ContractName
                    contractVersion = [string]$ctxContract.ContractVersion
                }
            }
        }

        if (Test-Path $stateToolsModule) {
            Import-Module $stateToolsModule -Force -DisableNameChecking -WarningAction SilentlyContinue
            $stateContract = Get-StateToolsContract
            if ($stateContract) {
                $snapshot.stateTools = [pscustomobject]@{
                    contractName    = [string]$stateContract.ContractName
                    contractVersion = [string]$stateContract.ContractVersion
                }
            }
        }
    }
    catch {}

    return $snapshot
}

function Read-InventoryRecord {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return [pscustomobject]@{}
    }

    try {
        $raw = Get-Content -Path $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]@{}
        }

        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return [pscustomobject]@{}
    }
}

function Write-InventoryRecord {
    param(
        [string]$Path,
        [object]$Record
    )

    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $json = $Record | ConvertTo-Json -Depth 20
    Set-Content -Path $Path -Value $json -Encoding UTF8 -Force
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

# --- Transcript ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $TranscriptPath = Join-Path $LogRoot "Setup_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setup (v$ScriptVersion) ==="
Write-Host "[INFO] Effective detail level: $($EffectiveDetailLevel.ToUpperInvariant())"
Write-Host "[INFO] BCDEDIT raw logging: $EffectiveBcdLogEnabled"
if ($TraceMode) { Write-Host "Trace mode enabled - transcript started" }

# --- Windows 11 check ---
function Test-IsWindows11 {
    try {
        $build = [int](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber")
        return ($build -ge 22000)
    }
    catch { return $false }
}

if (-not (Test-IsWindows11)) {
    Write-Host "[X] Unsupported OS. This solution supports Windows 11 only."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Elevation check ---
function Test-IsElevated {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsElevated)) {
    Write-Host "[X] Setup requires elevation. Re-launching as Administrator..."
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    if ($TraceMode) { $args += "-TraceMode" }
    Start-Process pwsh -Verb RunAs -ArgumentList $args
    exit 0
}

Write-Host "[OK] Running as Administrator"

# --- Source script checks ---
Write-Host "--- Source script check ---"
$missingSource = @()
foreach ($s in @($OrchestratorScript, $RendererScript, $SetterScript, $VerifierScript, $ModulesRoot, $SeedAssetsRoot)) {
    if (Test-Path $s) {
        if ($TraceMode) { Write-Host "[OK] Found: $s" }
    } else {
        Write-Host "[X] Missing: $s"
        $missingSource += $s
    }
}
if ($missingSource.Count -gt 0) {
    Write-Host "[X] Cannot continue. Resolve missing source files first."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}
Write-Host "[OK] Source scripts and Modules present"

# --- Compatibility gate ---
Write-Host "--- Verifying shared module contracts ---"
if (-not (Test-Path $CompatibilityScript)) {
    Write-Host "[X] Compatibility script missing: $CompatibilityScript"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

try {
    $compatParams = @{
        MinimumRuntimeContextVersion = $MinimumRuntimeContextContractVersion
        MinimumStateToolsVersion     = $MinimumStateToolsContractVersion
    }
    & $CompatibilityScript @compatParams
    if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) {
        throw "Compatibility gate failed with exit code $LASTEXITCODE"
    }
    Write-Host "[OK] Shared module contracts satisfy minimum versions"
}
catch {
    Write-Host "[X] Compatibility gate failed: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# Import logging after module location has been validated.
Import-Module (Join-Path $ModulesRoot "Logging.psm1") -Force -WarningAction SilentlyContinue

$MutationScriptName = "Setup.ps1"

function Write-MutationLog {
    param(
        [string]$Operation,
        [string]$Path,
        [string]$Target,
        [string]$Outcome = "OK"
    )

    Write-ContentMutationLog -Operation $Operation -Path $Path -Target $Target -ScriptName $MutationScriptName -Outcome $Outcome
}

function Initialize-SeedAssets {
    param(
        [string]$SeedRoot,
        [string]$RuntimeAssetsRoot,
        [string]$RuntimeStateFilePath
    )

    Write-Host "--- Runtime asset initialization from deployed seed ---"

    if (-not (Test-Path $SeedRoot)) {
        Write-Host "[X] Seed assets folder missing: $SeedRoot"
        return $false
    }

    try {
        $requiredSeedFiles = @(
            "DesktopBase.jpg",
            "LogonBase.jpg",
            "state.json"
        )

        foreach ($requiredSeedFile in $requiredSeedFiles) {
            $requiredPath = Join-Path $SeedRoot $requiredSeedFile
            if (-not (Test-Path $requiredPath)) {
                Write-Host "[X] Required seed asset missing: $requiredPath"
                return $false
            }
        }

        $resolvedSeedRoot = (Resolve-Path $SeedRoot).Path
        $seedFiles = Get-ChildItem -Path $SeedRoot -File -Recurse -ErrorAction Stop

        foreach ($seedFile in $seedFiles) {
            $relativePath = $seedFile.FullName.Substring($resolvedSeedRoot.Length).TrimStart('\\')
            $targetPath = Join-Path $RuntimeAssetsRoot $relativePath
            $targetParent = Split-Path $targetPath -Parent
            $fileName = [System.IO.Path]::GetFileName($targetPath)
            $isRenderedArtifact = ($fileName -match '(?i)_rendered\.(jpg|jpeg)$')

            if (-not (Test-Path $targetParent)) {
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                Write-MutationLog -Operation "NewDirectory" -Path $targetParent -Target ""
            }

            if ((Test-Path $targetPath) -and -not $isRenderedArtifact) {
                Write-Host "[OK] Preserving existing runtime asset: $targetPath"
                continue
            }

            Copy-Item -Path $seedFile.FullName -Destination $targetPath -Force
            Write-MutationLog -Operation "CopyItem" -Path $seedFile.FullName -Target $targetPath
            if ($isRenderedArtifact) {
                Write-Host "[OK] Refreshed runtime rendered asset: $targetPath"
            }
            else {
                Write-Host "[OK] Seeded runtime asset: $targetPath"
            }
        }

        if (-not (Test-Path $RuntimeStateFilePath)) {
            Set-Content -Path $RuntimeStateFilePath -Value "{}" -Encoding UTF8 -Force
            Write-MutationLog -Operation "SetContent" -Path $RuntimeStateFilePath -Target ""
            Write-Host "[OK] Initialized fallback state file: $RuntimeStateFilePath"
        }

        return $true
    }
    catch {
        Write-Host "[X] Runtime asset initialization failed: $($_.Exception.Message)"
        return $false
    }
}

# --- Runtime directory creation ---
Write-Host "--- Directory setup ---"
foreach ($dir in @($RuntimeRoot, $AssetsRoot, $LogRoot)) {
    if (Test-Path $dir) {
        Write-Host "[OK] Exists: $dir"
    } else {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-MutationLog -Operation "NewDirectory" -Path $dir -Target ""
            Write-Host "[OK] Created: $dir"
        }
        catch {
            Write-Host "[X] Failed creating $dir : $($_.Exception.Message)"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
    }
}

if (-not (Initialize-SeedAssets -SeedRoot $SeedAssetsRoot -RuntimeAssetsRoot $AssetsRoot -RuntimeStateFilePath $RuntimeStateFile)) {
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# Persist global logging defaults for runtime and verifier reconciliation.
try {
    $runtimeState = Read-InventoryRecord -Path $RuntimeStateFile
    if (-not $runtimeState) {
        $runtimeState = [pscustomobject]@{}
    }

    Set-ObjectProperty -Object $runtimeState -Name "logging" -Value ([pscustomobject]@{
        detailLevel   = $EffectiveDetailLevel
        bcdLogEnabled = [bool]$EffectiveBcdLogEnabled
        updatedUtc    = (Get-Date).ToUniversalTime().ToString("o")
        source        = "Setup"
    })

    Write-InventoryRecord -Path $RuntimeStateFile -Record $runtimeState
    Write-MutationLog -Operation "SetContent" -Path $RuntimeStateFile -Target ""
    Write-Host "[OK] Persisted logging defaults to state: level=$($EffectiveDetailLevel.ToUpperInvariant()) bcdLog=$EffectiveBcdLogEnabled"
}
catch {
    Write-Host "[WARN] Failed persisting logging defaults to state: $($_.Exception.Message)"
}

# --- Scheduled tasks ---
Write-Host "--- Scheduled task setup ---"

function Register-BackgroundTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Description,
        [ValidateSet("AtLogOn","AtStartup")]
        [string]$TriggerType = "AtLogOn",
        [string[]]$ScriptArgs = @()
    )

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "[OK] Removed existing task: $TaskName"
    }

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwsh = if ($pwshCmd) { $pwshCmd.Source } else { $null }
    if (-not $pwsh) { $pwsh = "powershell.exe" }

    $taskArgs = @(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
    )

    if ($TraceMode) {
        $taskArgs += "-NoExit"
    }

    if (-not $TraceMode) {
        $taskArgs += @(
            "-WindowStyle"
            "Hidden"
        )
    }

    $taskArgs += @(
        "-File"
        "`"$ScriptPath`""
    )

    foreach ($scriptArg in $ScriptArgs) {
        $taskArgs += $scriptArg
    }

    $taskArgs += @("-DetailLevel", $EffectiveDetailLevel.ToUpperInvariant())
    if ($EffectiveBcdLogEnabled) {
        $taskArgs += "-BcdLogEnabled"
    }

    if ($TraceMode) {
        $taskArgs += "-TraceMode"
    }

    $taskArgLine = ($taskArgs -join " ")
    $action  = New-ScheduledTaskAction -Execute $pwsh -Argument $taskArgLine

    if ($TriggerType -eq "AtStartup") {
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    }
    else {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive -RunLevel Highest
    }

    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $Description -Force | Out-Null
    Write-Host "[OK] Registered task: $TaskName"
    if ($TraceMode) {
        Write-Host "[INFO] $TaskName args: $taskArgLine"
    }
}

Remove-StaleBackgroundModifierTasks -KeepTaskNames $SupportedTaskNames

Register-BackgroundTask -TaskName $TaskNameStartup  -ScriptPath $OrchestratorScript -Description "BackgroundModifier: orchestrate pre-logon phase at startup" -TriggerType "AtStartup" -ScriptArgs @("-Phase1Only")
Register-BackgroundTask -TaskName $TaskNamePhase2a  -ScriptPath $Phase2aHarnessScript -Description "BackgroundModifier: phase 2a harness at logon (renderer+setter, sequential)" -TriggerType "AtLogOn"

# --- Initial elevated render/apply sequence ---
Write-Host "--- Running initial elevated render/apply sequence ---"
$initialRendererExit = 0
$initialSetterExit = 0

try {
    $rendererParams = @{
        RuntimeRoot   = $RuntimeRoot
        StateFilePath = $RuntimeStateFile
        LogRoot       = $LogRoot
    }
    if ($TraceMode) { $rendererParams.TraceMode = $true }
    $rendererParams.DetailLevel = $EffectiveDetailLevel.ToUpperInvariant()
    if ($EffectiveBcdLogEnabled) { $rendererParams.BcdLogEnabled = $true }

    & $RendererScript @rendererParams
    if ($LASTEXITCODE -is [int]) {
        $initialRendererExit = $LASTEXITCODE
    }
}
catch {
    Write-Host "[X] Initial renderer invocation failed: $($_.Exception.Message)"
    $initialRendererExit = 1
}

if ($initialRendererExit -eq 0) {
    Write-Host "[OK] Initial elevated renderer run completed."
}
else {
    Write-Host "[WARN] Initial elevated renderer run reported exit code $initialRendererExit"
}

if ($initialRendererExit -eq 0) {
    try {
        $setterParams = @{
            RuntimeRoot   = $RuntimeRoot
            StateFilePath = $RuntimeStateFile
            LogRoot       = $LogRoot
        }
        if ($TraceMode) { $setterParams.TraceMode = $true }
        $setterParams.DetailLevel = $EffectiveDetailLevel.ToUpperInvariant()
        if ($EffectiveBcdLogEnabled) { $setterParams.BcdLogEnabled = $true }

        & $SetterScript @setterParams
        if ($LASTEXITCODE -is [int]) {
            $initialSetterExit = $LASTEXITCODE
        }
    }
    catch {
        Write-Host "[X] Initial setter invocation failed: $($_.Exception.Message)"
        $initialSetterExit = 1
    }
}
else {
    Write-Host "[WARN] Skipping initial setter run because renderer failed."
    $initialSetterExit = 1
}

if ($initialSetterExit -eq 0) {
    Write-Host "[OK] Initial elevated setter apply completed."
}
else {
    Write-Host "[WARN] Initial elevated setter apply reported exit code $initialSetterExit"
}

# --- Run verifier ---
Write-Host "--- Running installation verifier ---"
$verifierParams = @{}
if ($TraceMode) { $verifierParams.TraceMode = $true }
$verifierParams.DetailLevel = $EffectiveDetailLevel.ToUpperInvariant()
if ($EffectiveBcdLogEnabled) { $verifierParams.BcdLogEnabled = $true }

$verifierExit = 0
try {
    & $VerifierScript @verifierParams
    if ($LASTEXITCODE -is [int]) {
        $verifierExit = $LASTEXITCODE
    }
}
catch {
    Write-Host "[X] Verifier invocation failed: $($_.Exception.Message)"
    $verifierExit = 1
}

# --- Inventory update (setup phase) ---
Write-Host "--- Updating BTools inventory (setup phase) ---"
try {
    $contracts = Get-ContractSnapshot -ModulePath $ModulesRoot
    $record = Read-InventoryRecord -Path $InventoryFile

    if (-not ($record.PSObject.Properties.Name -contains "inventorySchemaVersion")) {
        $record | Add-Member -NotePropertyName "inventorySchemaVersion" -NotePropertyValue "1.0.0"
    }

    Set-ObjectProperty -Object $record -Name "repositoryName" -Value $ProjectName
    Set-ObjectProperty -Object $record -Name "solutionVersion" -Value $ScriptVersion
    Set-ObjectProperty -Object $record -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))
    Set-ObjectProperty -Object $record -Name "contracts" -Value $contracts

    Set-ObjectProperty -Object $record -Name "setupSupport" -Value ([pscustomobject]@{
        setupStatus      = $(if ($verifierExit -eq 0 -and $initialRendererExit -eq 0 -and $initialSetterExit -eq 0) { "completed" } else { "completed-with-warnings" })
        setupUpdatedUtc  = (Get-Date).ToUniversalTime().ToString("o")
        loggingDetailLevel = $EffectiveDetailLevel
        bcdLogEnabled = [bool]$EffectiveBcdLogEnabled
        traceModeEnabled = [bool]$TraceMode
        initialRendererExitCode = $initialRendererExit
        initialSetterExitCode = $initialSetterExit
        verifierExitCode = $verifierExit
        taskNames        = @($TaskNameStartup, $TaskNamePhase2a)
        runtimeRoot      = $RuntimeRoot
        assetsRoot       = $AssetsRoot
        logRoot          = $LogRoot
        stateFilePath    = (Join-Path $AssetsRoot "state.json")
    })

    Write-InventoryRecord -Path $InventoryFile -Record $record
    Write-Host "[OK] Inventory updated: $InventoryFile"
}
catch {
    Write-Host "[WARN] Failed to update inventory ${InventoryFile}: $($_.Exception.Message)"
}

# --- Summary ---
Write-Host "=== Setup Summary ==="
if ($verifierExit -eq 0 -and $initialRendererExit -eq 0 -and $initialSetterExit -eq 0) {
    Write-Host "[OK] Setup completed successfully."
} else {
    Write-Host "[WARN] Setup completed but verifier reported issues. Review output above."
}

$setupExit = if ($verifierExit -eq 0 -and $initialRendererExit -eq 0 -and $initialSetterExit -eq 0) { 0 } else { 1 }

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
    Write-Host ""
    Write-Host "=== Production Phase Ready ==="
    Write-Host "Review the output above before closing this window."
    Write-Host ""
    $null = Read-Host "Press Enter to exit"
}

exit $setupExit
