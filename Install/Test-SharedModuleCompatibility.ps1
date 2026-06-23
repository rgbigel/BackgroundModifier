<#
    Script: Test-SharedModuleCompatibility.ps1
    Purpose: Verify shared module interface compatibility for BackgroundModifier.
#>

[CmdletBinding()]
param(
    [string]$MinimumRuntimeContextVersion = "1.0.0",
    [string]$MinimumStateToolsVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$moduleRoot = Join-Path $repoRoot "Modules"

$runtimeContextModule = Join-Path $moduleRoot "RuntimeContext.psm1"
$stateToolsModule = Join-Path $moduleRoot "StateTools.psm1"

foreach ($modulePath in @($runtimeContextModule, $stateToolsModule)) {
    if (-not (Test-Path $modulePath)) {
        throw "Missing module: $modulePath"
    }
}

Import-Module $runtimeContextModule -Force
Import-Module $stateToolsModule -Force

function Test-MinVersion {
    param(
        [string]$Actual,
        [string]$Minimum
    )

    try {
        return ([version]$Actual -ge [version]$Minimum)
    }
    catch {
        return $false
    }
}

$requiredRuntimeContextFunctions = @(
    "New-RepoRuntimeContext",
    "Test-RepoRuntimeContext",
    "Get-RepoRuntimeContextContract"
)

$requiredStateToolsFunctions = @(
    "Read-RuntimeState",
    "Write-RuntimeState",
    "Update-PhaseState",
    "Get-PhaseReadiness",
    "Get-PendingLogonSource",
    "Set-PendingLogonSource",
    "Clear-PendingLogonSource",
    "Set-InteractiveElevationRelaunchMarker",
    "Clear-InteractiveElevationRelaunch",
    "Test-InteractiveElevationRelaunchRecentlyRequested",
    "Get-StateToolsContract"
)

function Assert-FunctionsPresent {
    param(
        [string]$ModuleName,
        [string[]]$FunctionNames
    )

    foreach ($name in $FunctionNames) {
        $cmd = Get-Command -Name $name -Module $ModuleName -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Missing required exported function '$name' in module '$ModuleName'."
        }
    }
}

Assert-FunctionsPresent -ModuleName "RuntimeContext" -FunctionNames $requiredRuntimeContextFunctions
Assert-FunctionsPresent -ModuleName "StateTools" -FunctionNames $requiredStateToolsFunctions

$context = New-RepoRuntimeContext -RepoName "BackgroundModifier"
if (-not (Test-RepoRuntimeContext -Context $context)) {
    throw "Runtime context validation failed."
}

$runtimeContextContract = Get-RepoRuntimeContextContract
if (-not $runtimeContextContract) {
    throw "RuntimeContext contract metadata is unavailable."
}

if (-not (Test-MinVersion -Actual ([string]$runtimeContextContract.ContractVersion) -Minimum $MinimumRuntimeContextVersion)) {
    throw "RuntimeContext contract version $($runtimeContextContract.ContractVersion) is below required minimum $MinimumRuntimeContextVersion"
}

$stateToolsContract = Get-StateToolsContract
if (-not $stateToolsContract) {
    throw "StateTools contract metadata is unavailable."
}

if (-not (Test-MinVersion -Actual ([string]$stateToolsContract.ContractVersion) -Minimum $MinimumStateToolsVersion)) {
    throw "StateTools contract version $($stateToolsContract.ContractVersion) is below required minimum $MinimumStateToolsVersion"
}

Write-Host "[OK] Shared module compatibility check passed."
exit 0
