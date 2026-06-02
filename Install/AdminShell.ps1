# =================================================================================================
#  Module:      AdminShell.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     16.0.0
#  Changelog:
#      16.0.0 --------  Added elevated PowerShell launcher for install and maintenance workflows.
# =================================================================================================

param(
    [string]$StartIn = "D:\OneDrive\cmd",
    [string]$Command
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

if (-not (Test-Path -LiteralPath $StartIn)) {
    Write-Host "[WARN] StartIn path not found, falling back to repository root: $StartIn"
    $StartIn = $RepoRootResolved
}

Write-Host "=== BackgroundModifier AdminShell.ps1 (v16.0.0) ==="
Write-Host "[OK] Launching elevated PowerShell in: $StartIn"

Start-ElevatedPowerShellSession -WorkingDirectory $StartIn -Command $Command