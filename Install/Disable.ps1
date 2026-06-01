# =================================================================================================
#  Module:      Disable.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Added explicit disable operation for scheduled automation.
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

Write-Host "=== BackgroundModifier Disable (v6.0.0) ==="
if ($DebugMode) { Write-Host "Debug mode enabled" }

Require-Admin

$taskNames = @(
    "BackgroundModifier-BootIdentity",
    "BackgroundModifier-Autorun"
)

$disabledCount = 0

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        Write-Host "[WARN] Task not found: $taskName"
        continue
    }

    try {
        Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
        Write-Host "[OK] Disabled task: $taskName"
        $disabledCount++
    }
    catch {
        Write-Host "[ERROR] Failed to disable task '$taskName': $($_.Exception.Message)"
    }
}

Write-Host "[OK] Disable operation completed. Tasks disabled: $disabledCount"
