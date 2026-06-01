# =================================================================================================
#  Module:      Enable.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
$16.0.0
#  Changelog:
#      6.0.0  --------  Added explicit enable operation for scheduled automation.
# =================================================================================================

param(
    [switch]$t,
    [switch]$d
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

$flags = Set-Flags -T:$t -D:$d
$DebugMode = $flags.DebugMode

$16.0.0) ==="
if ($DebugMode) { Write-Host "Debug mode enabled" }

Require-Admin

$taskNames = @(
    "BackgroundModifier-BootIdentity",
    "BackgroundModifier-Autorun"
)

$enabledCount = 0

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "[WARN] Task not found: $taskName"
        continue
    }

    try {
        Enable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
        Write-Host "[OK] Enabled task: $taskName"
        $enabledCount++
    }
    catch {
        Write-Host "[ERROR] Failed to enable task '$taskName': $($_.Exception.Message)"
    }
}

Write-Host "[OK] Enable operation completed. Tasks enabled: $enabledCount"

