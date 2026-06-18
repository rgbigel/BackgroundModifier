<#
    Script: BackgroundSetter.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Deterministic application of generated background output images to logon and desktop.
#>

<#
.SYNOPSIS
    Applies rendered desktop and lock/sign-in background images.

.DESCRIPTION
    Validates generated assets, applies desktop wallpaper, and updates
    lock/sign-in policy with elevation-aware flow.

.PARAMETER TraceMode
    Enables transcript logging for setter execution.
    Alias: t

.PARAMETER HelpMode
    Shows full help and exits.
    Aliases: h, ?
#>

[CmdletBinding()]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode,
    [string]$RuntimeRoot = "C:\BackgroundMotives",
    [string]$StateFilePath,
    [string]$LogRoot,
    [switch]$ApplyDesktop,
    [switch]$ApplyLockScreen,
    [switch]$CaptureDesktopAsBase,
    [switch]$PromoteDesktopBaseToLogonBase,
    [switch]$Interactive
)

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

# --- Import modules ---
$ModuleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
Import-Module (Join-Path $ModuleRoot "Constants.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force
Import-Module (Join-Path $ModuleRoot "TranscriptTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "PathTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RuntimeContext.psm1") -Force
Import-Module (Join-Path $ModuleRoot "StateTools.psm1") -Force

$RuntimeContext = New-RepoRuntimeContext -RepoName "BackgroundModifier" -RuntimeRoot $RuntimeRoot -LogRoot $LogRoot -StateFilePath $StateFilePath
$LogRoot = $RuntimeContext.LogRoot
$StateFile = $RuntimeContext.StateFilePath
$AssetsRoot = $RuntimeContext.AssetsRoot

# --- Transcript handling ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Setter_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setter (v8.0.0) ==="

if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$MutationScriptName = "BackgroundSetter.ps1"

function Write-MutationLog {
    param(
        [string]$Operation,
        [string]$Path,
        [string]$Target,
        [string]$Outcome = "OK"
    )

    Write-ContentMutationLog -Operation $Operation -Path $Path -Target $Target -ScriptName $MutationScriptName -Outcome $Outcome
}

function Test-IsWindows11 {
    try {
        $build = [int](Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber")
        return ($build -ge 22000)
    }
    catch {
        return $false
    }
}

function Get-CurrentDesktopWallpaperPath {
    $wallpaperPath = ""

    try {
        $wallpaperPath = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -ErrorAction SilentlyContinue)
    }
    catch {
        $wallpaperPath = ""
    }

    if ($wallpaperPath -and (Test-Path $wallpaperPath)) {
        return $wallpaperPath
    }

    $transcoded = Join-Path $env:APPDATA "Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path $transcoded) {
        return $transcoded
    }

    return $null
}

function Get-FileHashOrNull {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    }
    catch {
        return $null
    }
}

function Test-FileContentEqual {
    param(
        [string]$PathA,
        [string]$PathB
    )

    $hashA = Get-FileHashOrNull -Path $PathA
    $hashB = Get-FileHashOrNull -Path $PathB

    if (-not $hashA -or -not $hashB) {
        return $false
    }

    return ($hashA -eq $hashB)
}

function Get-ImageState {
    param(
        [string]$DesktopImage,
        [string]$DesktopBase,
        [string]$DesktopRendered,
        [string]$LogonImage,
        [string]$LogonBase,
        [string]$LogonRendered
    )

    $desktopMatchesRendered = Test-FileContentEqual -PathA $DesktopImage -PathB $DesktopRendered
    $desktopMatchesBase = Test-FileContentEqual -PathA $DesktopImage -PathB $DesktopBase
    $logonMatchesRendered = Test-FileContentEqual -PathA $LogonImage -PathB $LogonRendered
    $logonMatchesBase = Test-FileContentEqual -PathA $LogonImage -PathB $LogonBase

    return [pscustomobject]@{
        DesktopImageExists = (Test-Path $DesktopImage)
        DesktopBaseExists = (Test-Path $DesktopBase)
        DesktopRenderedExists = (Test-Path $DesktopRendered)
        LogonImageExists = (Test-Path $LogonImage)
        LogonBaseExists = (Test-Path $LogonBase)
        LogonRenderedExists = (Test-Path $LogonRendered)
        DesktopMatchesRendered = $desktopMatchesRendered
        DesktopMatchesBase = $desktopMatchesBase
        LogonMatchesRendered = $logonMatchesRendered
        LogonMatchesBase = $logonMatchesBase
        UserChangedDesktop = ((Test-Path $DesktopImage) -and (Test-Path $DesktopRendered) -and -not $desktopMatchesRendered)
        UserChangedLogon = ((Test-Path $LogonImage) -and (Test-Path $LogonRendered) -and -not $logonMatchesRendered)
    }
}

function Restore-BaseFromCurrentImage {
    param(
        [string]$BasePath,
        [string]$CurrentImagePath,
        [string]$Label
    )

    if (Test-Path $BasePath) {
        return $true
    }

    if (-not (Test-Path $CurrentImagePath)) {
        return $false
    }

    try {
        Copy-Item -Path $CurrentImagePath -Destination $BasePath -Force
        Write-MutationLog -Operation "CopyItem" -Path $CurrentImagePath -Target $BasePath
        Write-Host "[OK] Restored $Label base from current image -> $BasePath"
        return $true
    }
    catch {
        Write-Host "[X] Failed restoring $Label base from current image: $($_.Exception.Message)"
        return $false
    }
}

function Set-DesktopWallpaper {
    param(
        [string]$ImagePath
    )

    if (-not (Test-Path $ImagePath)) {
        throw "Desktop image missing: $ImagePath"
    }

    $desktopReg = "HKCU:\Control Panel\Desktop"
    Set-ItemProperty -Path $desktopReg -Name Wallpaper -Value $ImagePath -Force

    $signature = @"
using System;
using System.Runtime.InteropServices;
public static class NativeWallpaper {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

    if (-not ("NativeWallpaper" -as [type])) {
        Add-Type -TypeDefinition $signature | Out-Null
    }

    $SPI_SETDESKWALLPAPER = 20
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDCHANGE = 0x02

    $result = [NativeWallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $ImagePath, ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE))
    if (-not $result) {
        throw "SystemParametersInfo failed to refresh desktop wallpaper."
    }
}

function Set-LockScreenImage {
    param(
        [string]$ImagePath
    )

    if (-not (Test-Path $ImagePath)) {
        throw "Lock screen image missing: $ImagePath"
    }

    $personalizationPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    if (-not (Test-Path $personalizationPolicy)) {
        New-Item -Path $personalizationPolicy -Force | Out-Null
    }

    Set-ItemProperty -Path $personalizationPolicy -Name LockScreenImage -Value $ImagePath -Type String

    # Keep sign-in background enabled where this policy is honored.
    $systemPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $systemPolicy)) {
        New-Item -Path $systemPolicy -Force | Out-Null
    }
    Set-ItemProperty -Path $systemPolicy -Name DisableLogonBackgroundImage -Value 0 -Type DWord
}

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

function Test-IsInteractiveSession {
    try {
        return [Environment]::UserInteractive
    }
    catch {
        return $true
    }
}

function Restart-ScriptElevated {
    param(
        [string[]]$ForwardArgs
    )

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $pwsh = if ($pwshCmd) { $pwshCmd.Source } else { $null }
    if (-not $pwsh) {
        $pwsh = "powershell.exe"
    }

    $argumentList = @(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$PSCommandPath`""
    ) + $ForwardArgs

    Start-Process -FilePath $pwsh -Verb RunAs -ArgumentList $argumentList | Out-Null
    Write-Host "[INFO] Relaunching elevated to complete lock/sign-in apply."
}

function Test-ScheduledTasksPresent {
    $renderer = Get-ScheduledTask -TaskName "BackgroundModifier-Renderer" -ErrorAction SilentlyContinue
    $setter   = Get-ScheduledTask -TaskName "BackgroundModifier-Setter"   -ErrorAction SilentlyContinue

    return [pscustomobject]@{
        RendererPresent = ($null -ne $renderer)
        SetterPresent   = ($null -ne $setter)
        BothPresent     = ($null -ne $renderer -and $null -ne $setter)
    }
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

function Get-RuntimeState {
    param(
        [string]$StateFilePath
    )

    return Read-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath
}

function Save-RuntimeState {
    param(
        [string]$StateFilePath,
        [object]$StateObject
    )

    return (Write-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath -StateObject $StateObject -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    })
}

function Get-PendingLogonSourceFromState {
    param(
        [string]$StateFilePath
    )

    return Get-PendingLogonSource -Context $RuntimeContext -StateFilePath $StateFilePath
}

function Set-PendingLogonSourceInState {
    param(
        [string]$StateFilePath,
        [string]$SourcePath,
        [string]$Reason = "LockScreenApplyRequiresElevation"
    )

    return (Set-PendingLogonSource -Context $RuntimeContext -StateFilePath $StateFilePath -SourcePath $SourcePath -Reason $Reason -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    })
}

function Clear-PendingLogonSourceInState {
    param(
        [string]$StateFilePath
    )

    return (Clear-PendingLogonSource -Context $RuntimeContext -StateFilePath $StateFilePath -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    })
}

function Mark-InteractiveElevationRelaunchRequested {
    param(
        [string]$StateFilePath
    )

    return (Mark-InteractiveElevationRelaunch -Context $RuntimeContext -StateFilePath $StateFilePath -ProcessId $PID -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    })
}

function Clear-InteractiveElevationRelaunchRequested {
    param(
        [string]$StateFilePath
    )

    return (Clear-InteractiveElevationRelaunch -Context $RuntimeContext -StateFilePath $StateFilePath -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    })
}

function Test-InteractiveElevationRelaunchRecentlyRequested {
    param(
        [string]$StateFilePath,
        [int]$WindowSeconds = 20
    )

    return (StateTools\Test-InteractiveElevationRelaunchRecentlyRequested -Context $RuntimeContext -StateFilePath $StateFilePath -WindowSeconds $WindowSeconds)
}

function Update-Phase2State {
    param(
        [string]$StateFilePath,
        [string]$Status,
        [string]$CurrentPhase = "Phase2",
        [string]$BlockedReason = $null
    )

    Update-PhaseState -Context $RuntimeContext -StateFilePath $StateFilePath -PhaseKey "phase2" -Status $Status -CurrentPhase $CurrentPhase -BlockedReason $BlockedReason -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    }
}

function Get-Phase1ReadinessFromState {
    param(
        [string]$StateFilePath
    )

    return Get-PhaseReadiness -Context $RuntimeContext -StateFilePath $StateFilePath -PhaseKey "phase1" -UnknownIsReady $true
}

if (-not (Test-IsWindows11)) {
    Write-Host "[X] Unsupported OS. This solution supports Windows 11 only."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Paths ---
$DesktopImage    = Join-Path $AssetsRoot "Desktop.jpg"
$DesktopBase     = Join-Path $AssetsRoot "DesktopBase.jpg"
$DesktopRendered = Join-Path $AssetsRoot "desktop_rendered.jpg"
$LogonImage      = Join-Path $AssetsRoot "Logon.jpg"
$LogonBase       = Join-Path $AssetsRoot "LogonBase.jpg"
$LogonRendered   = Join-Path $AssetsRoot "logon_rendered.jpg"
$StateFile       = $RuntimeContext.StateFilePath

$ImageState = Get-ImageState -DesktopImage $DesktopImage -DesktopBase $DesktopBase -DesktopRendered $DesktopRendered -LogonImage $LogonImage -LogonBase $LogonBase -LogonRendered $LogonRendered

# --- Scheduled task presence check ---
$TaskState = Test-ScheduledTasksPresent
if (-not $TaskState.BothPresent) {
    Write-Host "[WARN] One or more scheduled tasks are not registered:"
    if (-not $TaskState.RendererPresent) { Write-Host "[WARN]   Missing: BackgroundModifier-Renderer" }
    if (-not $TaskState.SetterPresent)   { Write-Host "[WARN]   Missing: BackgroundModifier-Setter" }
    Write-Host "[INFO] Automatic post-logon render and apply are not active."
    Write-Host "[INFO] Run Installer.ps1 to restore automation, or run renderer and setter manually."
    Write-Host "[INFO] For lock/sign-in apply, elevation will still be required."
} elseif ($TraceMode) {
    Write-Host "[OK] Scheduled tasks present (BackgroundModifier-Renderer, BackgroundModifier-Setter)"
}

Write-Host "--- Image state ---"
Write-Host "Desktop: UserChanged=$($ImageState.UserChangedDesktop) MatchesRendered=$($ImageState.DesktopMatchesRendered) MatchesBase=$($ImageState.DesktopMatchesBase)"
Write-Host "Logon: UserChanged=$($ImageState.UserChangedLogon) MatchesRendered=$($ImageState.LogonMatchesRendered) MatchesBase=$($ImageState.LogonMatchesBase)"

$DoApplyDesktop = $ApplyDesktop.IsPresent
$DoApplyLockScreen = $ApplyLockScreen.IsPresent
$DoCapture = $CaptureDesktopAsBase.IsPresent
$DoPromote = $PromoteDesktopBaseToLogonBase.IsPresent

$SessionIsInteractive = Test-IsInteractiveSession
$HasExplicitActionRequest = (
    $ApplyDesktop.IsPresent -or
    $ApplyLockScreen.IsPresent -or
    $CaptureDesktopAsBase.IsPresent -or
    $PromoteDesktopBaseToLogonBase.IsPresent -or
    $Interactive
)
$IsNonInteractiveAutorun = (-not $SessionIsInteractive) -and (-not $HasExplicitActionRequest)

if (-not $ApplyDesktop.IsPresent -and -not $ApplyLockScreen.IsPresent) {
    # Keep backward-compatible behavior for existing automation.
    $DoApplyDesktop = $true
    $DoApplyLockScreen = $true
}

if ($Interactive) {
    Write-Host "--- Interactive action selection ---"
    $DoCapture = ((Read-Host "Capture current desktop wallpaper as DesktopBase.jpg? (y/N)") -match '^(y|yes)$')
    $DoPromote = ((Read-Host "Promote DesktopBase.jpg to LogonBase.jpg? (y/N)") -match '^(y|yes)$')
    $DoApplyDesktop = ((Read-Host "Apply Desktop.jpg to desktop now? (y/N)") -match '^(y|yes)$')
    $DoApplyLockScreen = ((Read-Host "Apply Logon.jpg as Windows lock/sign-in image policy? (y/N)") -match '^(y|yes)$')
}

# --- Detect pending logon change from a prior non-elevated run ---
$PendingLogonSource = $null
try {
    $stored = Get-PendingLogonSourceFromState -StateFilePath $StateFile
    if ($stored -and (Test-Path $stored)) {
        $PendingLogonSource = $stored
        Write-Host "[INFO] Pending logon change detected from prior run -> $PendingLogonSource"
    }
    elseif ($stored) {
        Write-Host "[WARN] Pending logon state references a missing image: '$stored'"
        Write-Host "[WARN] Pending logon change has been discarded."
        [void](Clear-PendingLogonSourceInState -StateFilePath $StateFile)
    }
}
catch {
    Write-Host "[WARN] Failed loading pending logon state from ${StateFile}: $($_.Exception.Message)"
}

# --- Compute PendingLogonSource from current session if desktop changed and logon apply is intended ---
if (-not $PendingLogonSource -and $ImageState.UserChangedDesktop -and $DoApplyLockScreen) {
    $PendingLogonSource = if ($DoApplyDesktop) { $DesktopRendered } else { $DesktopImage }
    Write-Host "[INFO] Desktop changed since last render. Logon update pending -> $PendingLogonSource"
}

if ($DoCapture) {
    Write-Host "--- Capture desktop as DesktopBase ---"
    $wallpaper = Get-CurrentDesktopWallpaperPath
    if (-not $wallpaper) {
        Write-Host "[X] Could not locate current desktop wallpaper to capture."
        Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "CaptureWallpaperNotFound"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    try {
        Copy-Item -Path $wallpaper -Destination $DesktopImage -Force
        Write-MutationLog -Operation "CopyItem" -Path $wallpaper -Target $DesktopImage
        Copy-Item -Path $wallpaper -Destination $DesktopBase -Force
        Write-MutationLog -Operation "CopyItem" -Path $wallpaper -Target $DesktopBase
        Write-Host "[OK] Updated Desktop image snapshot -> $DesktopImage"
        Write-Host "[OK] Captured DesktopBase -> $DesktopBase"
    }
    catch {
        Write-Host "[X] Failed capturing desktop wallpaper: $($_.Exception.Message)"
        Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "CaptureDesktopFailed"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if ($DoPromote) {
    Write-Host "--- Promote DesktopBase to LogonBase ---"
    $desktopBaseReady = Restore-BaseFromCurrentImage -BasePath $DesktopBase -CurrentImagePath $DesktopImage -Label "desktop"
    if (-not $desktopBaseReady) {
        Write-Host "[X] Missing DesktopBase for promotion and no usable Desktop image snapshot -> $DesktopBase"
        Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "PromoteDesktopBaseMissing"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    try {
        Copy-Item -Path $DesktopBase -Destination $LogonBase -Force
        Write-MutationLog -Operation "CopyItem" -Path $DesktopBase -Target $LogonBase
        Copy-Item -Path $DesktopBase -Destination $LogonImage -Force
        Write-MutationLog -Operation "CopyItem" -Path $DesktopBase -Target $LogonImage
        Write-Host "[OK] Promoted LogonBase -> $LogonBase"
        Write-Host "[OK] Updated Logon image snapshot -> $LogonImage"
    }
    catch {
        Write-Host "[X] Failed promoting DesktopBase to LogonBase: $($_.Exception.Message)"
        Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "PromoteDesktopBaseFailed"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if (-not $DoApplyDesktop -and -not $DoApplyLockScreen) {
    Write-Host "--- Summary ---"
    Write-Host "[OK] No apply targets selected."
    Update-Phase2State -StateFilePath $StateFile -Status "completed" -CurrentPhase "Phase2" -BlockedReason "NoApplyTargetsSelected"
    if ($TraceMode) {
        Stop-Transcript | Out-Null
        Write-Host "Log written to: $TranscriptPath"
    }
    exit 0
}

$phase1Readiness = Get-Phase1ReadinessFromState -StateFilePath $StateFile
if ($phase1Readiness.Known -and -not $phase1Readiness.IsReady) {
    Write-Host "[X] Phase order guard: phase 1 is not ready (phase1Status='$($phase1Readiness.Status)')."
    Write-Host "[INFO] Run phase 1/orchestrator flow before running phase 2 apply operations."
    Update-Phase2State -StateFilePath $StateFile -Status "blocked" -CurrentPhase "Blocked" -BlockedReason "Phase1NotReady"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($IsNonInteractiveAutorun) {
    Write-Host "[INFO] Non-interactive autorun mode detected."
    Write-Host "[INFO] Running simple phase 2 path with error handling only."
}

Update-Phase2State -StateFilePath $StateFile -Status "running" -CurrentPhase "Phase2" -BlockedReason $null

$LockSignInDeferred = $false

Write-Host "--- File check ---"

if ($DoApplyLockScreen -and -not (Test-Path $LogonRendered)) {
    Write-Host "[X] Missing generated logon image -> $LogonRendered"
    Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "LogonRenderedMissing"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($DoApplyDesktop -and -not (Test-Path $DesktopRendered)) {
    Write-Host "[X] Missing generated desktop image -> $DesktopRendered"
    Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "DesktopRenderedMissing"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Generated images present"

# --- Apply desktop background first ---
if ($DoApplyDesktop) {
    Write-Host "--- Applying desktop background ---"

    try {
        $managedDesktopTarget = "$env:USERPROFILE\Pictures\Background.jpg"
        $managedDesktopDirectory = Split-Path $managedDesktopTarget -Parent
        if (-not (Test-Path $managedDesktopDirectory)) {
            New-Item -ItemType Directory -Path $managedDesktopDirectory -Force | Out-Null
            Write-Host "[OK] Created desktop target directory -> $managedDesktopDirectory"
        }
        Copy-Item -Path $DesktopRendered -Destination $managedDesktopTarget -Force
        Set-DesktopWallpaper -ImagePath $managedDesktopTarget
        Copy-Item -Path $DesktopRendered -Destination $DesktopImage -Force
        Write-MutationLog -Operation "CopyItem" -Path $DesktopRendered -Target $DesktopImage
        Write-Host "[OK] Desktop background applied -> $managedDesktopTarget"
        Write-Host "[OK] Updated Desktop image snapshot -> $DesktopImage"
    }
    catch {
        Write-Host "[X] Failed to apply desktop background: $($_.Exception.Message)"
        Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "ApplyDesktopFailed"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

# --- Apply lock/sign-in background ---
if ($DoApplyLockScreen) {
    Write-Host "--- Applying lock/sign-in image policy ---"

    $isElevated = Test-IsElevated
    $isInteractive = $SessionIsInteractive

    if ($isElevated) {
        [void](Clear-InteractiveElevationRelaunchRequested -StateFilePath $StateFile)
    }

    if (-not $isElevated) {
        Write-Host "[X] Lock/sign-in policy update requires elevation (Administrator)."
        if (-not $isInteractive) {
            Write-Host "[WARN] Non-interactive context cannot complete UAC elevation prompt."
            Write-Host "[INFO] Persisting pending state and exiting with error for later interactive recovery."
            if ($PendingLogonSource) {
                if (Set-PendingLogonSourceInState -StateFilePath $StateFile -SourcePath $PendingLogonSource) {
                    Write-Host "[INFO] Pending logon source saved -> $StateFile (transient.pendingLogon.sourcePath)"
                }
                else {
                    Write-Host "[WARN] Failed saving pending logon source to state file -> $StateFile"
                }
            }
            Update-Phase2State -StateFilePath $StateFile -Status "blocked" -CurrentPhase "Blocked" -BlockedReason "LockScreenElevationRequiredNonInteractive"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }

        if ($isInteractive) {
            Write-Host "[INFO] You are in a post-logon interactive session without elevation."
            Write-Host "[INFO] Re-run elevated after logon, or run in pre-logon/system context."
        }
        if ($PendingLogonSource) {
            if (Set-PendingLogonSourceInState -StateFilePath $StateFile -SourcePath $PendingLogonSource) {
                Write-Host "[INFO] Pending logon source saved -> $StateFile (transient.pendingLogon.sourcePath)"
            }
            else {
                Write-Host "[WARN] Failed saving pending logon source to state file -> $StateFile"
            }
            Write-Host "[INFO] Elevated re-run will apply: $PendingLogonSource"
        }

        if (Test-InteractiveElevationRelaunchRecentlyRequested -StateFilePath $StateFile -WindowSeconds 20) {
            Write-Host "[WARN] Interactive elevation relaunch already requested recently; suppressing duplicate relaunch."
            Update-Phase2State -StateFilePath $StateFile -Status "blocked" -CurrentPhase "Blocked" -BlockedReason "LockScreenElevationRelaunchSuppressedDuplicate"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 0
        }

        [void](Mark-InteractiveElevationRelaunchRequested -StateFilePath $StateFile)
        Update-Phase2State -StateFilePath $StateFile -Status "blocked" -CurrentPhase "Blocked" -BlockedReason "LockScreenElevationRequiredInteractiveRelaunch"
        Restart-ScriptElevated -ForwardArgs @(
            if ($TraceMode) { "-TraceMode" }
            if ($DoApplyDesktop) { "-ApplyDesktop" }
            if ($DoApplyLockScreen) { "-ApplyLockScreen" }
            if ($DoCapture) { "-CaptureDesktopAsBase" }
            if ($DoPromote) { "-PromoteDesktopBaseToLogonBase" }
            if ($Interactive) { "-Interactive" }
        )
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 0
    }

    if ($DoApplyLockScreen -and $isInteractive) {
        Write-Host "[INFO] Running in post-logon interactive session (elevated)."
        Write-Host "[INFO] Lock/sign-in changes may not be visible until sign-out/lock/restart."
    }
    elseif ($DoApplyLockScreen) {
        Write-Host "[INFO] Running in non-interactive context."
    }

    # If a pending logon source exists (desktop changed, stored from prior non-elevated run),
    # promote it to logon_rendered.jpg so the elevated apply uses the intended image.
    if ($DoApplyLockScreen -and $PendingLogonSource -and (Test-Path $PendingLogonSource)) {
        Write-Host "[INFO] Applying pending logon source -> $PendingLogonSource"
        Copy-Item -Path $PendingLogonSource -Destination $LogonRendered -Force
        Write-MutationLog -Operation "CopyItem" -Path $PendingLogonSource -Target $LogonRendered
        Copy-Item -Path $PendingLogonSource -Destination $LogonBase -Force
        Write-MutationLog -Operation "CopyItem" -Path $PendingLogonSource -Target $LogonBase
    }

    if ($DoApplyLockScreen) {
        try {
            Set-LockScreenImage -ImagePath $LogonRendered
            Copy-Item -Path $LogonRendered -Destination $LogonImage -Force
            Write-MutationLog -Operation "CopyItem" -Path $LogonRendered -Target $LogonImage
            if (-not (Clear-PendingLogonSourceInState -StateFilePath $StateFile)) {
                Write-Host "[WARN] Failed clearing transient.pendingLogon from state file -> $StateFile"
            }
            Write-Host "[OK] Lock/sign-in policy updated -> $LogonRendered"
            Write-Host "[OK] Updated Logon image snapshot -> $LogonImage"
        }
        catch {
            Write-Host "[X] Failed to apply lock/sign-in image: $($_.Exception.Message)"
            Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "ApplyLockScreenFailed"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
    }
}

# --- Summary ---
Write-Host "--- Summary ---"
$ImageState = Get-ImageState -DesktopImage $DesktopImage -DesktopBase $DesktopBase -DesktopRendered $DesktopRendered -LogonImage $LogonImage -LogonBase $LogonBase -LogonRendered $LogonRendered
Write-Host "Desktop: UserChanged=$($ImageState.UserChangedDesktop) MatchesRendered=$($ImageState.DesktopMatchesRendered) MatchesBase=$($ImageState.DesktopMatchesBase)"
Write-Host "Logon: UserChanged=$($ImageState.UserChangedLogon) MatchesRendered=$($ImageState.LogonMatchesRendered) MatchesBase=$($ImageState.LogonMatchesBase)"
Update-Phase2State -StateFilePath $StateFile -Status "completed" -CurrentPhase "Phase2" -BlockedReason $null
Write-Host "[OK] Backgrounds applied successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

