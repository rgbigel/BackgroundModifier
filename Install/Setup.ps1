<#
    Script: Setup.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Install and configure BackgroundModifier runtime structure and scheduled tasks.
    Requires: Windows 11, elevation (Administrator).
#>

param(
    [switch]$DebugMode,
    [switch]$TraceMode
)

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
if ($DebugMode) { Write-Host "Debug mode enabled" }
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
    if ($DebugMode) { $args += "-DebugMode" }
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
        if ($DebugMode) { Write-Host "[OK] Found: $s" }
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

# --- Runtime directory creation ---
Write-Host "--- Directory setup ---"
foreach ($dir in @($RuntimeRoot, $AssetsRoot, $LogRoot)) {
    if (Test-Path $dir) {
        Write-Host "[OK] Exists: $dir"
    } else {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
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

    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if (-not $pwsh) { $pwsh = "powershell.exe" }

    $action  = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId (whoami) -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -StartWhenAvailable

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $Description -Force | Out-Null
    Write-Host "[OK] Registered task: $TaskName"
}

Register-BackgroundTask -TaskName $TaskNameRenderer -ScriptPath $RendererScript -Description "BackgroundModifier: render background at logon"
Register-BackgroundTask -TaskName $TaskNameSetter   -ScriptPath $SetterScript   -Description "BackgroundModifier: apply background at logon"

# --- Run verifier ---
Write-Host "--- Running installation verifier ---"
$verifierArgs = @()
if ($DebugMode) { $verifierArgs += "-DebugMode" }
if ($TraceMode) { $verifierArgs += "-TraceMode" }
& $VerifierScript @verifierArgs
$verifierExit = $LASTEXITCODE

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
