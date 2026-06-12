<#
    Script: BackgroundSetter.ps1
    Version: 7.0.0
    Author: Rolf Bercht
    Purpose: Deterministic application of generated background output images to logon and desktop.
#>

param(
    [switch]$DebugMode,
    [switch]$TraceMode,
    [switch]$ApplyDesktop,
    [switch]$ApplyLockScreen,
    [switch]$CaptureDesktopAsBase,
    [switch]$PromoteDesktopBaseToLogonBase,
    [switch]$Interactive
)

# --- Absolute log root ---
$LogRoot = "C:\BackgroundMotives\logs"

# --- Import modules ---
$ModuleRoot = Join-Path $PSScriptRoot "Modules"
Import-Module (Join-Path $ModuleRoot "Constants.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force
Import-Module (Join-Path $ModuleRoot "TranscriptTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "PathTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force

# --- Transcript handling ---
if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Setter_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Setter (v7.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

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

if (-not (Test-IsWindows11)) {
    Write-Host "[X] Unsupported OS. This solution supports Windows 11 only."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Paths ---
$DesktopImage    = "C:\BackgroundMotives\assets\Desktop.jpg"
$DesktopBase     = "C:\BackgroundMotives\assets\DesktopBase.jpg"
$DesktopRendered = "C:\BackgroundMotives\assets\desktop_rendered.jpg"
$LogonImage      = "C:\BackgroundMotives\assets\Logon.jpg"
$LogonBase       = "C:\BackgroundMotives\assets\LogonBase.jpg"
$LogonRendered   = "C:\BackgroundMotives\assets\logon_rendered.jpg"
$PendingLogonStateFile = "C:\BackgroundMotives\assets\pending_logon_source.txt"

$ImageState = Get-ImageState -DesktopImage $DesktopImage -DesktopBase $DesktopBase -DesktopRendered $DesktopRendered -LogonImage $LogonImage -LogonBase $LogonBase -LogonRendered $LogonRendered

Write-Host "--- Image state ---"
Write-Host "Desktop: UserChanged=$($ImageState.UserChangedDesktop) MatchesRendered=$($ImageState.DesktopMatchesRendered) MatchesBase=$($ImageState.DesktopMatchesBase)"
Write-Host "Logon: UserChanged=$($ImageState.UserChangedLogon) MatchesRendered=$($ImageState.LogonMatchesRendered) MatchesBase=$($ImageState.LogonMatchesBase)"

# --- Detect pending logon change from a prior non-elevated run ---
$PendingLogonSource = $null
if (Test-Path $PendingLogonStateFile) {
    $stored = (Get-Content $PendingLogonStateFile -Raw).Trim()
    if ($stored -and (Test-Path $stored)) {
        $PendingLogonSource = $stored
        Write-Host "[INFO] Pending logon change detected from prior run -> $PendingLogonSource"
    } else {
        Write-Host "[WARN] Pending logon state file references a missing image: '$stored'"
        Write-Host "[WARN] Pending logon change has been discarded."
        Remove-Item $PendingLogonStateFile -Force
    }
}

# --- Compute PendingLogonSource from current session if desktop changed and logon apply is intended ---
if (-not $PendingLogonSource -and $ImageState.UserChangedDesktop -and ($DoApplyLockScreen -or $ApplyLockScreen.IsPresent)) {
    $PendingLogonSource = $DesktopImage
    Write-Host "[INFO] Desktop changed since last render. Logon update pending -> $PendingLogonSource"
}

$DoApplyDesktop = $ApplyDesktop.IsPresent
$DoApplyLockScreen = $ApplyLockScreen.IsPresent
$DoCapture = $CaptureDesktopAsBase.IsPresent
$DoPromote = $PromoteDesktopBaseToLogonBase.IsPresent

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

if ($DoCapture) {
    Write-Host "--- Capture desktop as DesktopBase ---"
    $wallpaper = Get-CurrentDesktopWallpaperPath
    if (-not $wallpaper) {
        Write-Host "[X] Could not locate current desktop wallpaper to capture."
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    try {
        Copy-Item -Path $wallpaper -Destination $DesktopImage -Force
        Copy-Item -Path $wallpaper -Destination $DesktopBase -Force
        Write-Host "[OK] Updated Desktop image snapshot -> $DesktopImage"
        Write-Host "[OK] Captured DesktopBase -> $DesktopBase"
    }
    catch {
        Write-Host "[X] Failed capturing desktop wallpaper: $($_.Exception.Message)"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if ($DoPromote) {
    Write-Host "--- Promote DesktopBase to LogonBase ---"
    $desktopBaseReady = Restore-BaseFromCurrentImage -BasePath $DesktopBase -CurrentImagePath $DesktopImage -Label "desktop"
    if (-not $desktopBaseReady) {
        Write-Host "[X] Missing DesktopBase for promotion and no usable Desktop image snapshot -> $DesktopBase"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    try {
        Copy-Item -Path $DesktopBase -Destination $LogonBase -Force
        Copy-Item -Path $DesktopBase -Destination $LogonImage -Force
        Write-Host "[OK] Promoted LogonBase -> $LogonBase"
        Write-Host "[OK] Updated Logon image snapshot -> $LogonImage"
    }
    catch {
        Write-Host "[X] Failed promoting DesktopBase to LogonBase: $($_.Exception.Message)"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if (-not $DoApplyDesktop -and -not $DoApplyLockScreen) {
    Write-Host "--- Summary ---"
    Write-Host "[OK] No apply targets selected."
    if ($TraceMode) {
        Stop-Transcript | Out-Null
        Write-Host "Log written to: $TranscriptPath"
    }
    exit 0
}

Write-Host "--- File check ---"

if ($DoApplyLockScreen -and -not (Test-Path $LogonRendered)) {
    Write-Host "[X] Missing generated logon image -> $LogonRendered"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($DoApplyDesktop -and -not (Test-Path $DesktopRendered)) {
    Write-Host "[X] Missing generated desktop image -> $DesktopRendered"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Generated images present"

# --- Apply logon background ---
if ($DoApplyLockScreen) {
    Write-Host "--- Applying lock/sign-in image policy ---"

    $isElevated = Test-IsElevated
    $isInteractive = Test-IsInteractiveSession

    if (-not $isElevated) {
        Write-Host "[X] Lock/sign-in policy update requires elevation (Administrator)."
        if ($isInteractive) {
            Write-Host "[INFO] You are in a post-logon interactive session without elevation."
            Write-Host "[INFO] Re-run elevated after logon, or run in pre-logon/system context."
        }
        if ($PendingLogonSource) {
            Set-Content -Path $PendingLogonStateFile -Value $PendingLogonSource -Force
            Write-Host "[INFO] Pending logon source saved -> $PendingLogonStateFile"
            Write-Host "[INFO] Elevated re-run will apply: $PendingLogonSource"
        }
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    if ($isInteractive) {
        Write-Host "[INFO] Running in post-logon interactive session (elevated)."
        Write-Host "[INFO] Lock/sign-in changes may not be visible until sign-out/lock/restart."
    }
    else {
        Write-Host "[INFO] Running in non-interactive pre-logon/system context."
    }

    # If a pending logon source exists (desktop changed, stored from prior non-elevated run),
    # promote it to logon_rendered.jpg so the elevated apply uses the intended image.
    if ($PendingLogonSource -and (Test-Path $PendingLogonSource)) {
        Write-Host "[INFO] Applying pending logon source -> $PendingLogonSource"
        Copy-Item -Path $PendingLogonSource -Destination $LogonRendered -Force
        Copy-Item -Path $PendingLogonSource -Destination $LogonBase -Force
    }

    try {
        Set-LockScreenImage -ImagePath $LogonRendered
        Copy-Item -Path $LogonRendered -Destination $LogonImage -Force
        if (Test-Path $PendingLogonStateFile) { Remove-Item $PendingLogonStateFile -Force }
        Write-Host "[OK] Lock/sign-in policy updated -> $LogonRendered"
        Write-Host "[OK] Updated Logon image snapshot -> $LogonImage"
    }
    catch {
        Write-Host "[X] Failed to apply lock/sign-in image: $($_.Exception.Message)"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

# --- Apply desktop background ---
if ($DoApplyDesktop) {
    Write-Host "--- Applying desktop background ---"

    try {
        $managedDesktopTarget = "$env:USERPROFILE\Pictures\Background.jpg"
        Copy-Item -Path $DesktopRendered -Destination $managedDesktopTarget -Force
        Set-DesktopWallpaper -ImagePath $managedDesktopTarget
        Copy-Item -Path $DesktopRendered -Destination $DesktopImage -Force
        Write-Host "[OK] Desktop background applied -> $managedDesktopTarget"
        Write-Host "[OK] Updated Desktop image snapshot -> $DesktopImage"
    }
    catch {
        Write-Host "[X] Failed to apply desktop background: $($_.Exception.Message)"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

# --- Summary ---
Write-Host "--- Summary ---"
$ImageState = Get-ImageState -DesktopImage $DesktopImage -DesktopBase $DesktopBase -DesktopRendered $DesktopRendered -LogonImage $LogonImage -LogonBase $LogonBase -LogonRendered $LogonRendered
Write-Host "Desktop: UserChanged=$($ImageState.UserChangedDesktop) MatchesRendered=$($ImageState.DesktopMatchesRendered) MatchesBase=$($ImageState.DesktopMatchesBase)"
Write-Host "Logon: UserChanged=$($ImageState.UserChangedLogon) MatchesRendered=$($ImageState.LogonMatchesRendered) MatchesBase=$($ImageState.LogonMatchesBase)"
Write-Host "[OK] Backgrounds applied successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

