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
    Script: Installer.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Deploy BackgroundModifier runtime files from the repository to the runtime
             directory, then invoke Setup.ps1 from the deployed location.

    Runtime target: D:\OneDrive\cmd\runtimes\<ProjectName>\
    The project name is derived from the repository root directory name.
    This script must be run from within the repository's Install directory or
    via the BackgroundModifier_Install.cmd launcher.

.SYNOPSIS
    Deploys BackgroundModifier runtime files and hands off to Setup.

.DESCRIPTION
    Copies Source, Modules, and Install content from the repository into the
    runtime target folder and then invokes deployed Setup.ps1.

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
    .\Installer.ps1

.EXAMPLE
    .\Installer.ps1 -t

.EXAMPLE
    .\Installer.ps1 -d d -b

.EXAMPLE
    .\Installer.ps1 -h
#>

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

$ScriptVersion = "8.0.0"

# --- Derive source root from this script's location ($PSScriptRoot = Install\) ---
$RepoRoot    = Split-Path $PSScriptRoot -Parent
$ProjectName = Split-Path $RepoRoot -Leaf

# --- Runtime deployment target ---
$CmdRoot     = "D:\OneDrive\cmd"
$RuntimeBase = Join-Path $CmdRoot "runtimes"
$RuntimeDir  = Join-Path $RuntimeBase $ProjectName

# --- Paths to copy ---
$SourceSrc  = Join-Path $RepoRoot "Source"
$ModulesSrc = Join-Path $RepoRoot "Modules"
$InstallSrc = Join-Path $RepoRoot "Install"
$AssetsSrc  = Join-Path $RepoRoot "assets"

$SourceDst  = Join-Path $RuntimeDir "Source"
$ModulesDst = Join-Path $RuntimeDir "Modules"
$InstallDst = Join-Path $RuntimeDir "Install"
$AssetsDst  = Join-Path $RuntimeDir "assets"

# Import Constants to bind paths
$ConstantsPath = Join-Path $RepoRoot "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

$SetupDeployed = Join-Path $InstallDst "Setup.ps1"
$LogRoot       = $Global:LogRoot
$BToolsRoot    = $Global:DeploymentRoot
$InventoryRoot = Join-Path $BToolsRoot "Inventory"
$InventoryFile = Join-Path $InventoryRoot "$ProjectName.json"
$MinimumRuntimeContextContractVersion = "1.0.0"
$MinimumStateToolsContractVersion = "1.0.0"

function Get-CurrentSourceCommit {
    param(
        [string]$RepoPath
    )

    try {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) {
            return "(git-unavailable)"
        }

        $sha = (& $git.Source -C $RepoPath rev-parse --short HEAD 2>$null | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($sha)) {
            return "(unknown)"
        }

        return $sha.Trim()
    }
    catch {
        return "(unknown)"
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

# --- Bootstrap transcript before LogRoot is guaranteed ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $tempLog = Join-Path $env:TEMP "BackgroundModifier_Installer_$timestamp.log"
    Start-Transcript -Path $tempLog -Force | Out-Null
}

Write-Host "=== BackgroundModifier Installer (v$ScriptVersion) ==="
Write-Host "Project : $ProjectName"
Write-Host "Source  : $RepoRoot"
Write-Host "Target  : $RuntimeDir"
if ($TraceMode) { Write-Host "Trace mode enabled" }

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

# --- Verify source layout ---
Write-Host "--- Verifying source layout ---"
$missingDirs = @()
foreach ($dir in @($SourceSrc, $ModulesSrc, $InstallSrc, $AssetsSrc)) {
    if (Test-Path $dir) {
        if ($TraceMode) { Write-Host "[OK] Found: $dir" }
    } else {
        Write-Host "[X] Missing: $dir"
        $missingDirs += $dir
    }
}
if ($missingDirs.Count -gt 0) {
    Write-Host "[X] Repository layout incomplete. Cannot continue."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}
Write-Host "[OK] Source layout verified"

Write-Host "--- Verifying required seed assets ---"
$requiredSeedAssets = @(
    (Join-Path $AssetsSrc "state.json"),
    (Join-Path $AssetsSrc "DesktopBase.jpg"),
    (Join-Path $AssetsSrc "LogonBase.jpg")
)

$missingSeedAssets = @()
foreach ($assetPath in $requiredSeedAssets) {
    if (Test-Path $assetPath) {
        if ($TraceMode) { Write-Host "[OK] Seed asset: $assetPath" }
    }
    else {
        Write-Host "[X] Missing required seed asset: $assetPath"
        $missingSeedAssets += $assetPath
    }
}

if ($missingSeedAssets.Count -gt 0) {
    Write-Host "[X] Required seed assets are missing. Cannot continue."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Required seed assets verified"

# --- Create runtime deployment directories ---
Write-Host "--- Creating runtime directories ---"
foreach ($dir in @($RuntimeBase, $RuntimeDir, $SourceDst, $ModulesDst, $InstallDst, $AssetsDst)) {
    if (-not (Test-Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "[OK] Created: $dir"
        }
        catch {
            Write-Host "[X] Failed creating $dir : $($_.Exception.Message)"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
    } else {
        if ($TraceMode) { Write-Host "[OK] Exists: $dir" }
    }
}

# --- Deploy Source ---
Write-Host "--- Deploying Source ---"
try {
    Copy-Item -Path "$SourceSrc\*" -Destination $SourceDst -Recurse -Force
    Write-Host "[OK] Source deployed -> $SourceDst"
}
catch {
    Write-Host "[X] Failed deploying Source: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Deploy Modules ---
Write-Host "--- Deploying Modules ---"
try {
    Copy-Item -Path "$ModulesSrc\*" -Destination $ModulesDst -Recurse -Force
    Write-Host "[OK] Modules deployed -> $ModulesDst"
}
catch {
    Write-Host "[X] Failed deploying Modules: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Deploy Install ---
Write-Host "--- Deploying Install ---"
try {
    Copy-Item -Path "$InstallSrc\*" -Destination $InstallDst -Recurse -Force
    Write-Host "[OK] Install scripts deployed -> $InstallDst"
}
catch {
    Write-Host "[X] Failed deploying Install scripts: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Deploy Assets ---
Write-Host "--- Deploying Assets ---"
try {
    Copy-Item -Path "$AssetsSrc\*" -Destination $AssetsDst -Recurse -Force
    Write-Host "[OK] Assets deployed -> $AssetsDst"
}
catch {
    Write-Host "[X] Failed deploying Assets: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Compatibility gate ---
$CompatibilityScript = Join-Path $InstallDst "Test-SharedModuleCompatibility.ps1"
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

# --- Stop bootstrap transcript before Setup.ps1 starts its own ---
if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Installer transcript: $tempLog"

    # Move it to LogRoot once Setup creates it
    $moveScript = {
        param($src, $logRoot)
        Start-Sleep -Seconds 3
        if (Test-Path $logRoot) {
            Copy-Item -Path $src -Destination (Join-Path $logRoot (Split-Path $src -Leaf)) -Force
        }
    }
    Start-Job -ScriptBlock $moveScript -ArgumentList $tempLog, $LogRoot | Out-Null
}

# --- Create command-hub launchers ---
Write-Host "--- Provisioning command-hub launchers ---"
try {
    $RuntimeLauncherPath = Join-Path $CmdRoot "$ProjectName.cmd"
    $InstallerLauncherPath = Join-Path $CmdRoot "${ProjectName}_Install.cmd"
    
    # Runtime launcher template (points to deployed runtime)
    $runtimeLauncherContent = @"
@echo off
setlocal
set "TARGET_SCRIPT=$SourceDst\BackgroundModifier.ps1"
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%" %*
)
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@

    # Installer launcher template (points to source repository)
    $installerLauncherContent = @"
@echo off
setlocal
set "TARGET_SCRIPT=$PSCommandPath"
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%" %*
)
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@

    Set-Content -Path $RuntimeLauncherPath -Value $runtimeLauncherContent -Encoding ASCII -Force
    Write-Host "[OK] Runtime launcher created: $RuntimeLauncherPath"

    Set-Content -Path $InstallerLauncherPath -Value $installerLauncherContent -Encoding ASCII -Force
    Write-Host "[OK] Installer launcher created: $InstallerLauncherPath"
}
catch {
    Write-Host "[WARN] Failed to create command-hub launchers: $($_.Exception.Message)"
}

# --- Hand off to deployed Setup.ps1 ---
Write-Host "--- Handing off to Setup.ps1 ---"
if (-not (Test-Path $SetupDeployed)) {
    Write-Host "[X] Deployed Setup.ps1 not found -> $SetupDeployed"
    exit 1
}

# --- Inventory update (install phase) ---
Write-Host "--- Updating BTools inventory (install phase) ---"
try {
    $contracts = Get-ContractSnapshot -ModulePath $ModulesDst
    $record = Read-InventoryRecord -Path $InventoryFile

    if (-not ($record.PSObject.Properties.Name -contains "inventorySchemaVersion")) {
        $record | Add-Member -NotePropertyName "inventorySchemaVersion" -NotePropertyValue "1.0.0"
    }

    Set-ObjectProperty -Object $record -Name "repositoryName" -Value $ProjectName
    Set-ObjectProperty -Object $record -Name "solutionVersion" -Value $ScriptVersion
    Set-ObjectProperty -Object $record -Name "sourceCommit" -Value (Get-CurrentSourceCommit -RepoPath $RepoRoot)
    Set-ObjectProperty -Object $record -Name "lastUpdatedUtc" -Value ((Get-Date).ToUniversalTime().ToString("o"))
    Set-ObjectProperty -Object $record -Name "contracts" -Value $contracts

    Set-ObjectProperty -Object $record -Name "deployment" -Value ([pscustomobject]@{
        cmdRoot           = $CmdRoot
        runtimeBase       = $RuntimeBase
        deployedRuntimeRoot = $RuntimeDir
        deployedAssetsRoot = $AssetsDst
        setupScriptPath   = $SetupDeployed
        installerScriptPath = $PSCommandPath
    })

    Set-ObjectProperty -Object $record -Name "installSupport" -Value ([pscustomobject]@{
        installStatus = "deployed"
        installUpdatedUtc = (Get-Date).ToUniversalTime().ToString("o")
        setupStatus = "pending"
        setupScriptPath = $SetupDeployed
        verifierScriptPath = (Join-Path $InstallDst "BackgroundInstallationVerifier.ps1")
        compatibilityScriptPath = (Join-Path $InstallDst "Test-SharedModuleCompatibility.ps1")
    })

    Write-InventoryRecord -Path $InventoryFile -Record $record
    Write-Host "[OK] Inventory updated: $InventoryFile"
}
catch {
    Write-Host "[WARN] Failed to update inventory ${InventoryFile}: $($_.Exception.Message)"
}

$setupParams = @{}
if ($TraceMode) { $setupParams.TraceMode = $true }
if ($PSBoundParameters.ContainsKey("DetailLevel")) { $setupParams.DetailLevel = $DetailLevel }
if ($PSBoundParameters.ContainsKey("BcdLogEnabled")) { $setupParams.BcdLogEnabled = $true }

& $SetupDeployed @setupParams
exit $LASTEXITCODE
