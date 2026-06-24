[CmdletBinding()]
param(
    [Alias("t")]
    [switch]$TraceMode,
    [Alias("h","?")]
    [switch]$HelpMode,
    [string]$RuntimeRoot = $Global:RuntimeRoot,
    [string]$StateFilePath,
    [string]$LogRoot
)

<#
    Script: BackgroundSetter.ps1
    Version: 9.0.0
    Author: Rolf Bercht
    Purpose: Phase 2 - Detect system info changes, render if needed, apply backgrounds to desktop and logon screens.

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

# Import Constants so defaults can bind to $Global:* variables
$ConstantsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\Constants.psm1"
Import-Module $ConstantsPath -Force

if ($HelpMode) {
    Get-Help $PSCommandPath -Full
    exit 0
}

$ScriptVersion = "9.0.0"

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
Import-Module (Join-Path $ModuleRoot "ImageTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SystemInfoTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "FileTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ImageStateTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RuntimeStateTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RenderTools.psm1") -Force

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

Write-Host "=== BackgroundModifier Setter (v9.0.0) ==="

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

function Render-BackgroundImagesIfNeeded {
    param(
        [string]$DesktopBase,
        [string]$LogonBase,
        [string]$DesktopRendered,
        [string]$LogonRendered,
        [PSCustomObject]$SystemInfo,
        [int]$MaxValueChars = 50
    )

    <#
    .SYNOPSIS
        Renders desktop and logon images from systemInfo if needed.
    .DESCRIPTION
        Checks if rendered images exist and are valid. If not, generates them
        with system info text overlay. Bright orange text (255,140,0) for readability.
    #>

    try {
        $tableRows = @(
            [pscustomobject]@{ Key = "Host";      Value = $SystemInfo.hostname }
            [pscustomobject]@{ Key = "User";      Value = $SystemInfo.username }
            [pscustomobject]@{ Key = "OS";        Value = "Windows 11 $($SystemInfo.osVersion) (Build $($SystemInfo.buildNumber))" }
            [pscustomobject]@{ Key = "IP";        Value = if ($SystemInfo.ipAddresses) { $SystemInfo.ipAddresses } else { "(none)" } }
            [pscustomobject]@{ Key = "EFI";       Value = $SystemInfo.efiLabel }
            [pscustomobject]@{ Key = "BCD";       Value = $SystemInfo.bcdDefault }
            [pscustomobject]@{ Key = "VolumeInv"; Value = $SystemInfo.volumeInventory }
            [pscustomobject]@{ Key = "Rendered";  Value = (Get-Date).ToString("yyyy-MM-dd HH:mm") }
        )

        $overlayTitle = "BackgroundModifier - Ver 9.0.0"
        $tableFormat = @{ MaxValueChars = $MaxValueChars }
        $overlayTextColor = @{ R = 255; G = 140; B = 0 }  # Bright orange

        Write-Host "--- Rendering backgrounds ---"

        # Render logon image
        if (-not (Test-Path $LogonRendered)) {
            Write-Host "[INFO] Rendering logon image..."
            Render-TextOverlay -BaseImage $LogonBase -OutputPath $LogonRendered -Title $overlayTitle -TableRows $tableRows -TableFormat $tableFormat -TextColor $overlayTextColor | Out-Null
            Write-MutationLog -Operation "RenderWrite" -Path $LogonRendered -Target ""
            Write-Host "[OK] Generated logon image -> $LogonRendered"
        } else {
            Write-Host "[INFO] Logon rendered image already exists"
        }

        # Render desktop image
        if (-not (Test-Path $DesktopRendered)) {
            Write-Host "[INFO] Rendering desktop image..."
            Render-TextOverlay -BaseImage $DesktopBase -OutputPath $DesktopRendered -Title $overlayTitle -TableRows $tableRows -TableFormat $tableFormat -TextColor $overlayTextColor | Out-Null
            Write-MutationLog -Operation "RenderWrite" -Path $DesktopRendered -Target ""
            Write-Host "[OK] Generated desktop image -> $DesktopRendered"
        } else {
            Write-Host "[INFO] Desktop rendered image already exists"
        }

        Write-Host "[OK] Rendering completed."
        return $true
    }
    catch {
        Write-Host "[X] Rendering failed: $($_.Exception.Message)"
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
    # Ensure the new wallpaper fills the screen instead of inheriting a prior center/fit style.
    Set-ItemProperty -Path $desktopReg -Name WallpaperStyle -Value "10" -Force
    Set-ItemProperty -Path $desktopReg -Name TileWallpaper -Value "0" -Force

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

    # Set the lock screen background image
    $personalizationPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    if (-not (Test-Path $personalizationPolicy)) {
        New-Item -Path $personalizationPolicy -Force | Out-Null
    }
    Set-ItemProperty -Path $personalizationPolicy -Name LockScreenImage -Value $ImagePath -Type String
}

function Set-LogonScreenConfiguration {
    # Configure logon screen display and blur settings.
    # Note: These settings control how the logon screen (password/PIN input) displays.
    
    $systemPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $systemPolicy)) {
        New-Item -Path $systemPolicy -Force | Out-Null
    }
    
    # Enable logon background to display the image (instead of solid accent color)
    Set-ItemProperty -Path $systemPolicy -Name DisableLogonBackgroundImage -Value 0 -Type DWord
    
    # Control blur effect on logon screen (0 = allow blur, 1 = disable blur)
    Set-ItemProperty -Path $systemPolicy -Name DisableAcrylicBackgroundOnLogon -Value 0 -Type DWord
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

    return (Set-InteractiveElevationRelaunchMarker -Context $RuntimeContext -StateFilePath $StateFilePath -ProcessId $PID -OnPersist {
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

function Test-AutomationEnabledMode {
    param(
        [string]$StateFilePath
    )

    $state = Get-RuntimeState -Context $RuntimeContext -StateFilePath $StateFilePath
    if (-not ($state.PSObject.Properties.Name -contains "automation") -or $null -eq $state.automation) {
        return $true
    }

    $automation = $state.automation
    if (-not ($automation.PSObject.Properties.Name -contains "enabledmode")) {
        return $true
    }

    return [bool]$automation.enabledmode
}

if (-not (Test-IsWindows11)) {
    Write-Host "[X] Unsupported OS. This solution supports Windows 11 only."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-AutomationEnabledMode -StateFilePath $StateFile)) {
    Write-Host "[X] Apply operations rejected because automation is disabled (automation.enabledmode=False)."
    Write-Host "[INFO] Set automation.enabledmode=True in state and run BackgroundModifier -Action Run in an interactive session."
    Update-Phase2State -StateFilePath $StateFile -Status "blocked" -CurrentPhase "Blocked" -BlockedReason "AutomationDisabledMode"
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

# Phase 2 determines render/apply targets based on conditional logic and system state, not CLI parameters.
# Image capture and promotion are Phase 1 responsibilities (deferred).
# Phase 2a (automatic) and Phase 2b (interactive) are determined by execution context.

$SessionIsInteractive = Test-IsInteractiveSession
$HasExplicitActionRequest = $false  # All action context comes from state.json in Phase 2
$IsNonInteractiveAutorun = (-not $SessionIsInteractive) -and (-not $HasExplicitActionRequest)

# Default: render and apply both desktop and logon (conditional render/apply based on state hash below)
$DoApplyDesktop = $true
$DoApplyLockScreen = $true

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
    $PendingLogonSource = if ($ImageState.LogonMatchesRendered) { $LogonRendered } else { $LogonImage }
    Write-Host "[INFO] Applying logon screen from rendered source -> $PendingLogonSource"
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

# --- Check if rendering is needed based on systemInfo hash ---
Write-Host "--- Checking system info for changes ---"
try {
    $state = Get-RuntimeState -Context $RuntimeContext -StateFilePath $StateFile
    $currentSystemInfo = $state.systemInfo

    if (-not $currentSystemInfo) {
        Write-Host "[X] System info not found in state (Phase 1 may not have completed)."
        Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "SystemInfoMissing"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    $currentHash = $currentSystemInfo.hash
    $lastRenderedHash = if ($state.PSObject.Properties.Name -contains "render" -and $state.render.PSObject.Properties.Name -contains "lastSystemInfoHash") { $state.render.lastSystemInfoHash } else { $null }

    Write-Host "[INFO] Current system info hash: $currentHash"
    Write-Host "[INFO] Last rendered hash: $(if ($lastRenderedHash) { $lastRenderedHash } else { "(none)" })"

    $renderingNeeded = ($null -eq $lastRenderedHash) -or ($lastRenderedHash -ne $currentHash)

    if ($renderingNeeded) {
        Write-Host "[INFO] System info has changed or rendered images missing - rendering required."
        $renderSuccess = Render-BackgroundImagesIfNeeded -DesktopBase $DesktopBase -LogonBase $LogonBase -DesktopRendered $DesktopRendered -LogonRendered $LogonRendered -SystemInfo $currentSystemInfo

        if ($renderSuccess) {
            # Update render state with new hash and timestamp
            if (-not ($state.PSObject.Properties.Name -contains "render")) {
                $state | Add-Member -NotePropertyName "render" -NotePropertyValue @{}
            }
            $state.render.lastSystemInfoHash = $currentHash
            $state.render.lastRenderedAtUtc = (Get-Date).ToString("yyyyMMdd_HHmmss")
            Write-RuntimeState -Context $RuntimeContext -StateFilePath $StateFile -StateObject $state
            Write-MutationLog -Operation "SetContent" -Path $StateFile -Target ""
            Write-Host "[OK] Render state updated with new hash."
        } else {
            Write-Host "[X] Rendering failed."
            Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "RenderingFailed"
            if ($TraceMode) { Stop-Transcript | Out-Null }
            exit 1
        }
    } else {
        Write-Host "[INFO] System info unchanged - using cached rendered images."
    }
}
catch {
    Write-Host "[X] Failed to process system info and rendering: $($_.Exception.Message)"
    Update-Phase2State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "SystemInfoProcessingFailed"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Phase 2a/2b Context Detection & Logon Time Gating ---
Write-Host "--- Determining Phase 2 context ---"

if ($IsNonInteractiveAutorun) {
    Write-Host "[INFO] Phase 2a: Automatic post-logon (scheduled, non-interactive, always elevated, hidden)"
    
    # Phase 2a ONLY: Set logon.logonTime once on first execution
    try {
        $state = Get-RuntimeState -Context $RuntimeContext -StateFilePath $StateFile
        if (-not ($state.PSObject.Properties.Name -contains "logon")) {
            $state | Add-Member -NotePropertyName "logon" -NotePropertyValue @{}
        }
        
        # Check if logonTime already set in this session
        if (-not ($state.logon.PSObject.Properties.Name -contains "logonTime") -or $null -eq $state.logon.logonTime) {
            $currentLogonTime = (Get-Date).ToString("yyyyMMdd_HHmmss")
            $state.logon.logonTime = $currentLogonTime
            $state.logon.logonTimeSetByPhase2a = $true
            $state.logon.username = $env:USERNAME
            $state.logon.sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
            Write-RuntimeState -Context $RuntimeContext -StateFilePath $StateFile -StateObject $state
            Write-MutationLog -Operation "SetContent" -Path $StateFile -Target ""
            Write-Host "[OK] Phase 2a: logonTime set to $currentLogonTime (first execution only)"
        } else {
            Write-Host "[OK] Phase 2a: logonTime already set in session ($($state.logon.logonTime)) - not resetting"
        }
    }
    catch {
        Write-Host "[WARN] Failed to set logonTime in state: $($_.Exception.Message)"
        # Non-fatal; continue with apply operations
    }
}
else {
    Write-Host "[INFO] Phase 2b: Interactive user-initiated (menu-driven, user context, elevation on-demand)"
    Write-Host "[INFO] Phase 2b: logonTime management skipped (exclusive to Phase 2a)"
    # Phase 2b NEVER modifies logonTime - that's Phase 2a's exclusive responsibility
}

if ($IsNonInteractiveAutorun) {
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

# --- Apply logon screen background ---
if ($DoApplyLockScreen) {
    Write-Host "--- Applying logon screen background ---"

    $isElevated = Test-IsElevated
    $isInteractive = $SessionIsInteractive

    if ($isElevated) {
        [void](Clear-InteractiveElevationRelaunchRequested -StateFilePath $StateFile)
    }

    if (-not $isElevated) {
        Write-Host "[X] Logon screen background update requires elevation (Administrator)."
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
            "-ApplyLockScreen"
            if ($DoCapture) { "-CaptureDesktopAsBase" }
            if ($DoPromote) { "-PromoteDesktopBaseToLogonBase" }
        )
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 0
    }

    if ($DoApplyLockScreen -and $isInteractive) {
        Write-Host "[INFO] Running in post-logon interactive session (elevated)."
        Write-Host "[INFO] Logon screen changes may not be visible until next login/user switch."
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
            Set-LogonScreenConfiguration
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

