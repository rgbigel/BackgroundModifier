<#
    Script: BackgroundRenderer.ps1
    Version: 8.0.0
    Author: Rolf Bercht
    Purpose: Deterministic generation of logon and desktop background output images.
#>

param(
    [switch]$DebugMode,
    [switch]$TraceMode,
    [switch]$CaptureDesktopAsBase,
    [switch]$PromoteDesktopBaseToLogonBase,
    [switch]$RenderDesktop,
    [switch]$RenderLogon,
    [switch]$SkipRender
)

$LogRoot = "C:\BackgroundMotives\logs"

$ModuleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "Modules"
$prev = $WarningPreference
$WarningPreference = "SilentlyContinue"

Import-Module (Join-Path $ModuleRoot "Constants.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Logging.psm1") -Force
Import-Module (Join-Path $ModuleRoot "TranscriptTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "PathTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RenderTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ImageTools.psm1") -Force

$WarningPreference = $prev

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Renderer_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Renderer (v8.0.0) ==="

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

function New-SolidColorJpeg {
    param(
        [string]$OutputPath,
        [int]$Width  = 1920,
        [int]$Height = 1080,
        [string]$HexColor = "#1a1a2e"
    )

    Add-Type -AssemblyName System.Drawing
    $color = [System.Drawing.ColorTranslator]::FromHtml($HexColor)
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $brush = New-Object System.Drawing.SolidBrush($color)
    $gfx.FillRectangle($brush, 0, 0, $Width, $Height)
    $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $brush.Dispose()
    $gfx.Dispose()
    $bmp.Dispose()
    Write-Host "[OK] Created solid-color base image -> $OutputPath ($HexColor ${Width}x${Height})"
}

function Get-WallpaperOrSolidColor {
    param(
        [string]$DestinationPath,
        [string]$Label
    )

    # Try registry wallpaper path first
    try {
        $regPath = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -ErrorAction SilentlyContinue)
        if ($regPath -and (Test-Path $regPath)) {
            Copy-Item -Path $regPath -Destination $DestinationPath -Force
            Write-Host "[OK] Captured $Label base from registry wallpaper -> $DestinationPath"
            return $true
        }
    }
    catch {}

    # Try TranscodedWallpaper
    $transcoded = Join-Path $env:APPDATA "Microsoft\Windows\Themes\TranscodedWallpaper"
    if (Test-Path $transcoded) {
        $len = (Get-Item $transcoded).Length
        if ($len -gt 10240) {
            Copy-Item -Path $transcoded -Destination $DestinationPath -Force
            Write-Host "[OK] Captured $Label base from TranscodedWallpaper -> $DestinationPath"
            return $true
        }
    }

    # Solid color fallback - read current background color from registry
    Write-Host "[INFO] No wallpaper image found. Using solid color fallback for $Label."
    try {
        $bgColor = (Get-ItemPropertyValue -Path "HKCU:\Control Panel\Colors" -Name "Background" -ErrorAction SilentlyContinue)
        if ($bgColor) {
            $rgb = $bgColor -split ' '
            $hex = "#" + ($rgb | ForEach-Object { "{0:X2}" -f [int]$_ }) -join ''
            New-SolidColorJpeg -OutputPath $DestinationPath -HexColor $hex
        }
        else {
            New-SolidColorJpeg -OutputPath $DestinationPath
        }
        return $true
    }
    catch {
        New-SolidColorJpeg -OutputPath $DestinationPath
        return $true
    }
}

if (-not (Test-IsWindows11)) {
    Write-Host "[X] Unsupported OS. This solution supports Windows 11 only."
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Correct asset names (JPG) ---
$DesktopImage = "C:\BackgroundMotives\assets\Desktop.jpg"
$DesktopBase = "C:\BackgroundMotives\assets\DesktopBase.jpg"
$DesktopRendered = "C:\BackgroundMotives\assets\desktop_rendered.jpg"
$LogonImage = "C:\BackgroundMotives\assets\Logon.jpg"
$LogonBase   = "C:\BackgroundMotives\assets\LogonBase.jpg"
$LogonRendered = "C:\BackgroundMotives\assets\logon_rendered.jpg"

$ImageState = Get-ImageState -DesktopImage $DesktopImage -DesktopBase $DesktopBase -DesktopRendered $DesktopRendered -LogonImage $LogonImage -LogonBase $LogonBase -LogonRendered $LogonRendered

Write-Host "--- Image state ---"
Write-Host "Desktop: UserChanged=$($ImageState.UserChangedDesktop) MatchesRendered=$($ImageState.DesktopMatchesRendered) MatchesBase=$($ImageState.DesktopMatchesBase)"
Write-Host "Logon: UserChanged=$($ImageState.UserChangedLogon) MatchesRendered=$($ImageState.LogonMatchesRendered) MatchesBase=$($ImageState.LogonMatchesBase)"

$DoRenderDesktop = $RenderDesktop.IsPresent
$DoRenderLogon = $RenderLogon.IsPresent

if ($SkipRender) {
    $DoRenderDesktop = $false
    $DoRenderLogon = $false
}
elseif (-not $RenderDesktop.IsPresent -and -not $RenderLogon.IsPresent) {
    # Keep backward-compatible behavior for existing automation.
    $DoRenderDesktop = $true
    $DoRenderLogon = $true
}

if ($CaptureDesktopAsBase) {
    Write-Host "--- Capture desktop as DesktopBase ---"
    $wallpaper = Get-CurrentDesktopWallpaperPath
    if (-not $wallpaper) {
        Write-Host "[X] Could not locate current desktop wallpaper to capture."
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }

    try {
        Copy-Item -Path $wallpaper -Destination $DesktopBase -Force
        Copy-Item -Path $wallpaper -Destination $DesktopImage -Force
        Write-Host "[OK] Captured DesktopBase -> $DesktopBase"
        Write-Host "[OK] Updated Desktop image snapshot -> $DesktopImage"
    }
    catch {
        Write-Host "[X] Failed capturing desktop wallpaper: $($_.Exception.Message)"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if ($PromoteDesktopBaseToLogonBase) {
    Write-Host "--- Promote DesktopBase to LogonBase ---"
    if (-not (Test-Path $DesktopBase)) {
        Write-Host "[X] Missing DesktopBase for promotion -> $DesktopBase"
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

if (-not $DoRenderDesktop -and -not $DoRenderLogon) {
    Write-Host "--- Summary ---"
    Write-Host "[OK] No render targets selected."
    if ($TraceMode) {
        Stop-Transcript | Out-Null
        Write-Host "Log written to: $TranscriptPath"
    }
    exit 0
}

Write-Host "--- Asset check ---"

if ($DoRenderDesktop) {
    $desktopBaseReady = Restore-BaseFromCurrentImage -BasePath $DesktopBase -CurrentImagePath $DesktopImage -Label "desktop"
    # Auto-capture: if DesktopBase missing and no snapshot exists, capture from wallpaper now
    if (-not $desktopBaseReady) {
        Write-Host "[INFO] Attempting wallpaper capture for missing DesktopBase..."
        $desktopBaseReady = Get-WallpaperOrSolidColor -DestinationPath $DesktopBase -Label "desktop"
        if ($desktopBaseReady) {
            Copy-Item -Path $DesktopBase -Destination $DesktopImage -Force
            Write-Host "[OK] Updated Desktop image snapshot -> $DesktopImage"
        }
    }
    if (-not $desktopBaseReady) {
        Write-Host "[X] Missing DesktopBase and no usable Desktop image snapshot -> $DesktopBase"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if ($DoRenderLogon) {
    $logonBaseReady = Restore-BaseFromCurrentImage -BasePath $LogonBase -CurrentImagePath $LogonImage -Label "logon"
    # LogonBase fallback: use DesktopBase when LogonBase and snapshot are both missing
    if (-not $logonBaseReady -and (Test-Path $DesktopBase)) {
        Copy-Item -Path $DesktopBase -Destination $LogonBase -Force
        Write-Host "[INFO] LogonBase missing; using DesktopBase as fallback -> $LogonBase"
        $logonBaseReady = $true
    }
    if (-not $logonBaseReady) {
        Write-Host "[X] Missing LogonBase and no usable Logon image snapshot -> $LogonBase"
        if ($TraceMode) { Stop-Transcript | Out-Null }
        exit 1
    }
}

if ($DoRenderDesktop -and -not (Test-Path $DesktopBase)) {
    Write-Host "[X] Missing DesktopBase -> $DesktopBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($DoRenderLogon -and -not (Test-Path $LogonBase)) {
    Write-Host "[X] Missing LogonBase -> $LogonBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Base assets present"

Write-Host "--- Rendering images ---"

# --- Collect system info for text overlay ---
$hostname    = $env:COMPUTERNAME
$username    = $env:USERNAME
$osVersion   = (Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DisplayVersion" -ErrorAction SilentlyContinue)
$buildNumber = (Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction SilentlyContinue)
$ipAddresses = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } | ForEach-Object { $_.IPAddress }) -join ", "
$renderTime  = (Get-Date).ToString("yyyy-MM-dd HH:mm")

$tableRows = @(
    [pscustomobject]@{ Key = "Host";      Value = $hostname }
    [pscustomobject]@{ Key = "User";      Value = $username }
    [pscustomobject]@{ Key = "OS";        Value = "Windows 11 $osVersion (Build $buildNumber)" }
    [pscustomobject]@{ Key = "IP";        Value = if ($ipAddresses) { $ipAddresses } else { "(none)" } }
    [pscustomobject]@{ Key = "Rendered";  Value = $renderTime }
)

# Bright orange text for overlay readability and visual consistency with the desktop base circle.
$overlayTextColor = @{ R = 255; G = 140; B = 0 }

try {
    if ($DoRenderLogon) {
        Render-TextOverlay -BaseImage $LogonBase -OutputPath $LogonRendered -Title "BackgroundModifier" -TableRows $tableRows -TextColor $overlayTextColor | Out-Null
        Write-Host "[OK] Generated logon image -> $LogonRendered"
    }

    if ($DoRenderDesktop) {
        Render-TextOverlay -BaseImage $DesktopBase -OutputPath $DesktopRendered -Title "BackgroundModifier" -TableRows $tableRows -TextColor $overlayTextColor | Out-Null
        Write-Host "[OK] Generated desktop image -> $DesktopRendered"
    }
}
catch {
    Write-Host "[X] Rendering failed: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "--- Summary ---"
$ImageState = Get-ImageState -DesktopImage $DesktopImage -DesktopBase $DesktopBase -DesktopRendered $DesktopRendered -LogonImage $LogonImage -LogonBase $LogonBase -LogonRendered $LogonRendered
Write-Host "Desktop: UserChanged=$($ImageState.UserChangedDesktop) MatchesRendered=$($ImageState.DesktopMatchesRendered) MatchesBase=$($ImageState.DesktopMatchesBase)"
Write-Host "Logon: UserChanged=$($ImageState.UserChangedLogon) MatchesRendered=$($ImageState.LogonMatchesRendered) MatchesBase=$($ImageState.LogonMatchesBase)"
Write-Host "[OK] Rendering completed successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

