# =================================================================================================
#  Module:      Uninstall.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
$16.0.0
#  Changelog:
#      6.0.0  --------  Added safe uninstall with repository protection guard and cmd entry cleanup.
# =================================================================================================

param(
    [switch]$t,
    [switch]$d,
    [string]$CmdRoot = "D:\OneDrive\cmd",
    [string]$RuntimeRoot = "C:\BackgroundMotives",
    [switch]$RemoveRuntimeData
)

$scriptItem = Get-Item -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue
$resolvedScriptPath = $PSCommandPath
if ($scriptItem -and $scriptItem.LinkType -eq "SymbolicLink" -and $scriptItem.Target) {
    $resolvedScriptPath = [string]$scriptItem.Target
}
$ScriptRootResolved = Split-Path -Parent ([System.IO.Path]::GetFullPath($resolvedScriptPath))
$RepoRootResolved = Split-Path -Parent $ScriptRootResolved
$ModuleRoot = Join-Path $RepoRootResolved "Modules"

Import-Module (Join-Path $ModuleRoot "InstallerTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force
Import-Module (Join-Path $ModuleRoot "BackgroundNoBlurReg.psm1") -Force

$flags = Set-Flags -T:$t -D:$d
$DebugMode = $flags.DebugMode

$16.0.0) ==="
if ($DebugMode) { Write-Host "Debug mode enabled" }

Require-Admin

$repoRoot = [System.IO.Path]::GetFullPath($RepoRootResolved)
$runtimeRootFull = [System.IO.Path]::GetFullPath($RuntimeRoot)

if ($runtimeRootFull.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[ERROR] Refusing uninstall: runtime root resolves inside repository path."
    Write-Host "[ERROR] Repo root:    $repoRoot"
    Write-Host "[ERROR] Runtime root: $runtimeRootFull"
    exit 1
}

Write-Host "--- Removing automation tasks ---"
$taskNames = @(
    "BackgroundModifier-BootIdentity",
    "BackgroundModifier-Autorun"
)

foreach ($taskName in $taskNames) {
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        Write-Host "[OK] Removed task: $taskName"
    }
    catch {
        Write-Host "[WARN] Task not removed (missing or inaccessible): $taskName"
    }
}

Write-Host "--- Removing logon policy customization ---"
try {
    Remove-NoBlur
    Write-Host "[OK] Removed no-blur policy customization"
}
catch {
    Write-Host "[WARN] Could not remove no-blur policy customization: $($_.Exception.Message)"
}

Write-Host "--- Removing cmd entry points ---"
$cmdEntries = @(
    "BackgroundModifier-Setup.ps1",
    "BackgroundModifier-Verify.ps1",
    "BackgroundModifier-Cleanup.ps1",
    "BackgroundModifier-Disable.ps1",
    "BackgroundModifier-Enable.ps1",
    "BackgroundModifier-Uninstall.ps1",
    "BackgroundModifier-BootIdentityTest.ps1",
    "BackgroundModifier-RenderTest.ps1",
    "BackgroundModifier-ApplyTest.ps1",
    "BackgroundModifier-LogonStage.ps1"
)

foreach ($entry in $cmdEntries) {
    $path = Join-Path $CmdRoot $entry
    if (Test-Path -LiteralPath $path) {
        try {
            Remove-Item -LiteralPath $path -Force
            Write-Host "[OK] Removed cmd entry: $path"
        }
        catch {
            Write-Host "[WARN] Could not remove cmd entry: $path"
        }
    }
}

Write-Host "--- Removing runtime links ---"
$solutionCodeRoot = Join-Path $runtimeRootFull "SolutionCode"
if (Test-Path -LiteralPath $solutionCodeRoot) {
    Get-ChildItem -LiteralPath $solutionCodeRoot -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Force
                Write-Host "[OK] Removed runtime link: $($_.FullName)"
            }
            catch {
                Write-Host "[WARN] Could not remove runtime link: $($_.FullName)"
            }
        }
}

if ($RemoveRuntimeData) {
    Write-Host "--- Removing runtime data (explicit) ---"
    if (Test-Path -LiteralPath $runtimeRootFull) {
        try {
            Remove-Item -LiteralPath $runtimeRootFull -Recurse -Force
            Write-Host "[OK] Removed runtime root: $runtimeRootFull"
        }
        catch {
            Write-Host "[ERROR] Failed to remove runtime root: $runtimeRootFull"
            exit 1
        }
    }
}
else {
    Write-Host "[OK] Runtime data retained (default). Use -RemoveRuntimeData to remove it."
}

Write-Host "[OK] Uninstall completed. Repository source was not modified."

