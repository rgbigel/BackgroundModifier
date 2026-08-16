<#
    Module: RuntimeContext.psm1
    Version: 1.0.0
    Purpose: Build and validate repository runtime context objects used by shared modules.

    Caller Contract (Module-Caller State Update Responsibility):
      This module builds context objects that carry runtime paths. Caller is responsible for:
      - New-RepoRuntimeContext: Returns context object with StateFilePath and LogRoot
      - Context is passed to modules; modules use StateFilePath to find state.json
      - Caller must ensure StateFilePath points to correct state.json location for repo
      - Context object carries no mutable state; it is a pure configuration carrier
      - Modules that receive context MUST use provided StateFilePath, not hardcoded paths
#>

# Import Constants to bind default RuntimeRoot
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

function New-RepoRuntimeContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [string]$RuntimeRoot = $Global:RuntimeRoot,
        [string]$AssetsRoot,
        [string]$LogRoot,
        [string]$StateFilePath,
        [string]$SchemaVersion = "1.0"
    )

    if ([string]::IsNullOrWhiteSpace($AssetsRoot)) {
        $AssetsRoot = Join-Path $RuntimeRoot "assets"
    }

    if ([string]::IsNullOrWhiteSpace($LogRoot)) {
        $LogRoot = Join-Path $RuntimeRoot "logs"
    }

    if ([string]::IsNullOrWhiteSpace($StateFilePath)) {
        $StateFilePath = Join-Path $AssetsRoot "state.json"
    }

    return [pscustomobject]@{
        ContractName    = "RepoRuntimeContext"
        ContractVersion = "1.0.0"
        RepoName        = $RepoName
        RuntimeRoot     = $RuntimeRoot
        AssetsRoot      = $AssetsRoot
        LogRoot         = $LogRoot
        StateFilePath   = $StateFilePath
        SchemaVersion   = $SchemaVersion
    }
}

function Test-RepoRuntimeContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    $required = @("RepoName", "RuntimeRoot", "AssetsRoot", "LogRoot", "StateFilePath", "SchemaVersion")
    foreach ($name in $required) {
        if (-not ($Context.PSObject.Properties.Name -contains $name)) {
            return $false
        }

        $value = [string]$Context.$name
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $false
        }
    }

    return $true
}

function Get-RepoRuntimeContextContract {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ContractName     = "RepoRuntimeContext"
        ContractVersion  = "1.0.0"
        RequiredFields   = @("RepoName", "RuntimeRoot", "AssetsRoot", "LogRoot", "StateFilePath", "SchemaVersion")
        Notes            = "Consumers should pass context to shared modules instead of relying on hardcoded paths."
    }
}

Export-ModuleMember -Function New-RepoRuntimeContext, Test-RepoRuntimeContext, Get-RepoRuntimeContextContract
