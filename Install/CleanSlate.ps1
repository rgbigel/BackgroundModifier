[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode,
    [switch]$All,
    [switch]$RemoveInventory,
    [switch]$KeepRuntimeState,
    [switch]$KeepDeployedRuntime
)

<#
    Script: CleanSlate.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Remove BackgroundModifier deployed runtime, runtime state, and scheduled tasks
             so setup/install testing can start from a deterministic clean slate.

.SYNOPSIS
    Performs full uninstall-style cleanup for BackgroundModifier.

.DESCRIPTION
    Removes BackgroundModifier scheduled tasks, deployed runtime folder under
    D:\OneDrive\cmd\runtimes\<ProjectName>, and runtime state/log/assets under
    C:\BackgroundMotives. Optionally removes the inventory record.

.PARAMETER TraceMode
    Enables transcript logging to C:\BackgroundMotives\logs when possible.
    Alias: t

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?

.PARAMETER RemoveInventory
    Also remove D:\OneDrive\BTools\Inventory\<ProjectName>.json.

.PARAMETER All
    Full clean-slate wipe. Equivalent to removing deployed runtime, runtime root,
    and inventory in one operation.

.PARAMETER KeepRuntimeState
    Do not remove C:\BackgroundMotives.

.PARAMETER KeepDeployedRuntime
    Do not remove D:\OneDrive\cmd\runtimes\<ProjectName>.

.EXAMPLE
    .\CleanSlate.ps1 -WhatIf

.EXAMPLE
    .\CleanSlate.ps1 -RemoveInventory

.EXAMPLE
    .\CleanSlate.ps1 -RemoveInventory -TraceMode

.EXAMPLE
    .\CleanSlate.ps1 -All
#>

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

if ($All) {
    if ($KeepRuntimeState -or $KeepDeployedRuntime) {
        Write-Host "[X] -All cannot be combined with -KeepRuntimeState or -KeepDeployedRuntime."
        exit 1
    }

    $RemoveInventory = $true
}

# Import Constants to bind RuntimeRoot
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

$ScriptVersion = "8.0.0"
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ProjectName = Split-Path $RepoRoot -Leaf

$TaskNames = @(
    "BackgroundModifier-Startup",
    "BackgroundModifier-Renderer",
    "BackgroundModifier-Setter"
)

$CmdRoot = "D:\OneDrive\cmd"
$RuntimeBase = Join-Path $CmdRoot "runtimes"
$RuntimeDir = Join-Path $RuntimeBase $ProjectName

$RuntimeRoot = $Global:RuntimeRoot
$BToolsRoot = "D:\OneDrive\BTools"
$InventoryRoot = Join-Path $BToolsRoot "Inventory"
$InventoryFile = Join-Path $InventoryRoot "$ProjectName.json"

function Test-IsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Restart-ScriptElevated {
    param(
        [string[]]$ForwardArgs
    )

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwsh = if ($pwshCmd) { $pwshCmd.Source } else { "powershell.exe" }

    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$PSCommandPath`""
    ) + $ForwardArgs

    Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $argumentList | Out-Null
}

function Remove-PathIfExists {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[OK] Not present: $Label -> $Path"
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, "Remove $Label")) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $Label -> $Path"
    }
}

Write-Host "=== BackgroundModifier Clean Slate (v$ScriptVersion) ==="

$runningWhatIf = [bool]$WhatIfPreference
if (-not (Test-IsElevated)) {
    if ($runningWhatIf) {
        Write-Host "[WARN] Running non-elevated in WhatIf preview mode."
    }
    else {
        Write-Host "[X] Clean-slate execution requires elevation. Re-launching as Administrator..."

        # Close open resources before elevating (prevents file lock issues during cleanup)
        try {
            if ((Get-PSCallStack | Where-Object { $_.Command -eq '<ScriptBlock>' }).Count -gt 0) {
                Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            }
        }
        catch {}

        $forwardArgs = @()
        if ($TraceMode) { $forwardArgs += "-TraceMode" }
        if ($All) { $forwardArgs += "-All" }
        if ($RemoveInventory) { $forwardArgs += "-RemoveInventory" }
        if ($KeepRuntimeState) { $forwardArgs += "-KeepRuntimeState" }
        if ($KeepDeployedRuntime) { $forwardArgs += "-KeepDeployedRuntime" }

        Restart-ScriptElevated -ForwardArgs $forwardArgs
        exit 0
    }
}

if ($TraceMode) {
    $logRoot = Join-Path $RuntimeRoot "logs"
    try {
        if (-not (Test-Path $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        }

        $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
        $transcriptPath = Join-Path $logRoot "CleanSlate_$timestamp.log"
        Start-Transcript -Path $transcriptPath -Force | Out-Null
        Write-Host "[INFO] Transcript: $transcriptPath"
    }
    catch {
        Write-Host "[WARN] Could not start transcript: $($_.Exception.Message)"
    }
}

$errors = @()
$transcriptStarted = [bool]$TraceMode

Write-Host "--- Removing scheduled tasks ---"
foreach ($taskName in $TaskNames) {
    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) {
            Write-Host "[OK] Task not present: $taskName"
            continue
        }

        if ($PSCmdlet.ShouldProcess($taskName, "Unregister scheduled task")) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "[OK] Unregistered task: $taskName"
        }
    }
    catch {
        $msg = "Task cleanup failed for ${taskName}: $($_.Exception.Message)"
        $errors += $msg
        Write-Host "[X] $msg"
    }
}

if (-not $KeepDeployedRuntime) {
    Write-Host "--- Removing deployed runtime ---"
    try {
        Remove-PathIfExists -Path $RuntimeDir -Label "DeployedRuntime"
    }
    catch {
        $msg = "Runtime deployment cleanup failed: $($_.Exception.Message)"
        $errors += $msg
        Write-Host "[X] $msg"
    }
}
else {
    Write-Host "[INFO] Keeping deployed runtime by request: $RuntimeDir"
}

if (-not $KeepRuntimeState) {
    Write-Host "--- Removing runtime state/log/assets root ---"
    try {
        if ($transcriptStarted) {
            Stop-Transcript | Out-Null
            $transcriptStarted = $false
        }

        Remove-PathIfExists -Path $RuntimeRoot -Label "RuntimeRoot"
    }
    catch {
        $msg = "Runtime root cleanup failed: $($_.Exception.Message)"
        $errors += $msg
        Write-Host "[X] $msg"
    }
}
else {
    Write-Host "[INFO] Keeping runtime state by request: $RuntimeRoot"
}

if ($RemoveInventory) {
    Write-Host "--- Removing inventory record ---"
    try {
        Remove-PathIfExists -Path $InventoryFile -Label "InventoryRecord"
    }
    catch {
        $msg = "Inventory cleanup failed: $($_.Exception.Message)"
        $errors += $msg
        Write-Host "[X] $msg"
    }
}
else {
    Write-Host "[INFO] Inventory preserved: $InventoryFile"
}

Write-Host "=== Clean Slate Summary ==="
if ($errors.Count -gt 0) {
    Write-Host "[WARN] Completed with $($errors.Count) error(s)."
    foreach ($err in $errors) {
        Write-Host "[WARN] $err"
    }

    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch {}
    }

    if ($TraceMode) {
        Write-Host "`nPress any key to continue..."
        $null = Read-Host
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    exit 1
}

Write-Host "[OK] Clean-slate operation completed successfully."
if ($transcriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
}

if ($TraceMode) {
    Write-Host "`nPress any key to continue..."
    $null = Read-Host
}

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
exit 0
