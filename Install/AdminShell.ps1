# =================================================================================================
#  Module:      AdminShell.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      16.0.0 --------  Added elevated PowerShell launcher for install and maintenance workflows.
# =================================================================================================

param(
    [string]$StartIn = "D:\OneDrive\cmd",
    [string]$CmdRoot = "D:\OneDrive\cmd",
    [switch]$t
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

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier AdminShell.ps1 help" -UsageLines @(
        "Usage: AdminShell.ps1 [-StartIn <path>] [-CmdRoot <path>] [-t]",
        "Use /?, /H, or -Help to show this message.",
        "Always opens the elevated action menu for Setup/Verify/Cleanup/Disable/Enable/Uninstall, plus Source actions (BootIdentity/Renderer/Setter).",
        "Apply runs automatically after successful Setter; the Apply menu entry is shown only after Setter problems.",
        "Includes test-link cleanup action."
    )
    exit 0
}

if (-not (Test-Admin)) {
    $elevatedExitCode = Invoke-SelfElevated -ScriptPath $resolvedScriptPath -WorkingDirectory $RepoRootResolved -NamedArguments @{
        StartIn = $StartIn
        CmdRoot = $CmdRoot
        t = [bool]$t
    }
    exit $elevatedExitCode
}

if (-not (Test-Path -LiteralPath $StartIn)) {
    Write-Host "[WARN] StartIn path not found, falling back to repository root: $StartIn"
    $StartIn = $RepoRootResolved
}

Write-Host "=== BackgroundModifier AdminShell.ps1 (v6.0.0) ==="

$sourceRoot = Join-Path $RepoRootResolved "Source"

$actionScripts = @{
    "S" = @{ Name = "Setup"; Path = (Join-Path $ScriptRootResolved "Setup.ps1"); PassTrace = $true }
    "V" = @{ Name = "Verify"; Path = (Join-Path $ScriptRootResolved "Verifyer.ps1"); PassTrace = $true }
    "C" = @{ Name = "Cleanup"; Path = (Join-Path $ScriptRootResolved "Cleanup.ps1"); PassTrace = $true }
    "D" = @{ Name = "Disable"; Path = (Join-Path $ScriptRootResolved "Disable.ps1"); PassTrace = $true }
    "E" = @{ Name = "Enable"; Path = (Join-Path $ScriptRootResolved "Enable.ps1"); PassTrace = $true }
    "U" = @{ Name = "Uninstall"; Path = (Join-Path $ScriptRootResolved "Uninstall.ps1"); PassTrace = $true }
    "B" = @{ Name = "BootIdentity"; Path = (Join-Path $sourceRoot "BootIdentity.ps1"); PassTrace = $false }
    "R" = @{ Name = "Renderer"; Path = (Join-Path $sourceRoot "BackgroundRenderer.ps1"); PassTrace = $true }
    "A" = @{ Name = "Setter"; Path = (Join-Path $sourceRoot "BackgroundSetter.ps1"); PassTrace = $true }
    "L" = @{ Name = "Apply"; Path = (Join-Path $sourceRoot "BackgroundApply.ps1"); PassTrace = $true }
}

$menuTraceMode = [bool]$t
$showApplyAction = $false
$testCmdEntries = @(
    "BackgroundModifier-BootIdentityTest.ps1",
    "BackgroundModifier-RenderTest.ps1",
    "BackgroundModifier-ApplyTest.ps1",
    "BackgroundModifier-LogonStage.ps1"
)

while ($true) {
    Write-Host ""
    Write-Host "=== BackgroundModifier Action Menu ==="
    Write-Host ("Flags: -t={0}  (-t enables debug/test-link behavior where applicable)" -f $menuTraceMode)
    Write-Host "T - Toggle -t"
    Write-Host "S - Setup"
    Write-Host "V - Verify"
    Write-Host "C - Cleanup"
    Write-Host "D - Disable"
    Write-Host "E - Enable"
    Write-Host "U - Uninstall"
    Write-Host "B - BootIdentity"
    Write-Host "R - Renderer"
    Write-Host "A - Setter"
    if ($showApplyAction) {
        Write-Host "L - Apply (available after Setter failure)"
    }
    Write-Host "X - Delete test links"
    Write-Host "Q - Quit"

    $selection = (Read-Host "Select action").Trim().ToUpperInvariant()
    if ($selection -eq "Q") {
        break
    }

    if ($selection -eq "T") {
        $menuTraceMode = -not $menuTraceMode
        continue
    }

    if ($selection -eq "X") {
        foreach ($entryName in $testCmdEntries) {
            $entryPath = Join-Path $CmdRoot $entryName
            if (Test-Path -LiteralPath $entryPath) {
                try {
                    Remove-Item -LiteralPath $entryPath -Force
                    Write-Host "[OK] Removed test link: $entryPath"
                }
                catch {
                    Write-Host "[WARN] Could not remove test link: $entryPath"
                }
            }
            else {
                Write-Host "[OK] Test link not present: $entryPath"
            }
        }
        continue
    }

    if (($selection -eq "L") -and (-not $showApplyAction)) {
        Write-Host "[WARN] Apply is hidden until Setter reports a problem."
        continue
    }

    if (-not $actionScripts.ContainsKey($selection)) {
        Write-Host "[WARN] Unknown selection: $selection"
        continue
    }

    $action = $actionScripts[$selection]
    if (-not (Test-Path -LiteralPath $action.Path)) {
        Write-Host "[ERROR] Action script not found: $($action.Path)"
        continue
    }

    Write-Host ("--- Running action: {0} ---" -f $action.Name)

    if ($action.PassTrace) {
        & $action.Path -t:$menuTraceMode
    }
    else {
        & $action.Path
    }

    $actionExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }

    if ($selection -eq "A") {
        if ($actionExitCode -eq 0) {
            $showApplyAction = $false
            Write-Host "[OK] Setter completed. Running Apply automatically."
            $applyAction = $actionScripts["L"]
            & $applyAction.Path -t:$menuTraceMode
        }
        else {
            $showApplyAction = $true
            Write-Host "[WARN] Setter reported a problem. Apply is now available in the menu."
        }
    }
}

exit 0