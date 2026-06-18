<#
    Script: Setup.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Install and configure BackgroundModifier runtime structure and scheduled tasks.
    Requires: Windows 11, elevation (Administrator).
#>

<#
.SYNOPSIS
    Installs and configures BackgroundModifier runtime directories and scheduled tasks.

.DESCRIPTION
    Validates source layout, ensures required runtime folders exist, (re)registers
    logon tasks for renderer and setter, then runs installation verification.

.PARAMETER TraceMode
    Enables setup transcript logging and registers tasks with trace-mode arguments.
    Alias: t

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?

.EXAMPLE
    .\Setup.ps1

.EXAMPLE
    .\Setup.ps1 -t

.EXAMPLE
    .\Setup.ps1 -h
#>

[CmdletBinding()]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode
)

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

# --- Constants ---
$ScriptVersion   = "8.0.0"
$RuntimeRoot     = "C:\BackgroundMotives"
$AssetsRoot      = "C:\BackgroundMotives\assets"
$LogRoot         = "C:\BackgroundMotives\logs"

# Paths are derived from this script's location so Setup.ps1 works from both
# the repository (Install\) and the deployed runtime (runtimes\BackgroundModifier\Install\).
$DeployedRoot    = Split-Path $PSScriptRoot -Parent
$SourceRoot      = Join-Path $DeployedRoot "Source"
$ModulesRoot     = Join-Path $DeployedRoot "Modules"
$RendererScript  = Join-Path $SourceRoot "BackgroundRenderer.ps1"
$SetterScript    = Join-Path $SourceRoot "BackgroundSetter.ps1"
$VerifierScript  = Join-Path $PSScriptRoot "BackgroundInstallationVerifier.ps1"

$TaskNameRenderer = "BackgroundModifier-Renderer"
$TaskNameSetter   = "BackgroundModifier-Setter"

# --- Transcript ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
    $TranscriptPath = Join-Path $LogRoot "Setup_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setup (v$ScriptVersion) ==="
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
foreach ($s in @($RendererScript, $SetterScript, $VerifierScript, $ModulesRoot)) {
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

# Import logging after module location has been validated.
Import-Module (Join-Path $ModulesRoot "Logging.psm1") -Force

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

# --- Scheduled tasks ---
Write-Host "--- Scheduled task setup ---"

function Register-BackgroundTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$Description
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
        # Keep task consoles open in trace mode to allow post-run review.
        $taskArgs += "-NoExit"
    }

    $taskArgs += @(
        "-File"
        "`"$ScriptPath`""
    )

    if ($TraceMode) {
        $taskArgs += "-TraceMode"
    }

    $taskArgLine = ($taskArgs -join " ")
    $action  = New-ScheduledTaskAction -Execute $pwsh -Argument $taskArgLine
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $Description -Force | Out-Null
    Write-Host "[OK] Registered task: $TaskName"
    if ($TraceMode) {
        Write-Host "[INFO] $TaskName args: $taskArgLine"
    }
}

Register-BackgroundTask -TaskName $TaskNameRenderer -ScriptPath $RendererScript -Description "BackgroundModifier: render background at logon"
Register-BackgroundTask -TaskName $TaskNameSetter   -ScriptPath $SetterScript   -Description "BackgroundModifier: apply background at logon"

# --- Run verifier ---
Write-Host "--- Running installation verifier ---"
$verifierParams = @{}
if ($TraceMode) { $verifierParams.TraceMode = $true }

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

# --- Summary ---
Write-Host "=== Setup Summary ==="
if ($verifierExit -eq 0) {
    Write-Host "[OK] Setup completed successfully."
} else {
    Write-Host "[WARN] Setup completed but verifier reported issues. Review output above."
}

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

exit $verifierExit
