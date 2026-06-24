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
    Script: BackgroundRenderer.ps1
    Version: 9.0.0
    Author: Rolf Bercht
    Purpose: Phase 1 - Collect system metadata and store to state.json for change detection.

.SYNOPSIS
    Generates deterministic desktop and logon rendered background images.

.DESCRIPTION
    Validates prerequisites, resolves base images, collects system metadata,
    and renders overlay text onto desktop/logon outputs.

.PARAMETER TraceMode
    Enables transcript logging for renderer execution.
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
Import-Module (Join-Path $ModuleRoot "RuntimeContext.psm1") -Force
Import-Module (Join-Path $ModuleRoot "StateTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RenderTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ImageTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SystemInfoTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "FileTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ImageStateTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RuntimeStateTools.psm1") -Force

$WarningPreference = $prev

$RuntimeContext = New-RepoRuntimeContext -RepoName "BackgroundModifier" -RuntimeRoot $RuntimeRoot -LogRoot $LogRoot -StateFilePath $StateFilePath
$LogRoot = $RuntimeContext.LogRoot
$StateFile = $RuntimeContext.StateFilePath
$AssetsRoot = $RuntimeContext.AssetsRoot

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $TranscriptPath = Join-Path $LogRoot "Renderer_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier Renderer (v$ScriptVersion) ==="

if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$MutationScriptName = "BackgroundRenderer.ps1"

function Write-MutationLog {
    param(
        [string]$Operation,
        [string]$Path,
        [string]$Target,
        [string]$Outcome = "OK"
    )

    Write-ContentMutationLog -Operation $Operation -Path $Path -Target $Target -ScriptName $MutationScriptName -Outcome $Outcome
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
    Write-MutationLog -Operation "SaveImage" -Path $OutputPath -Target ""
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
            Write-MutationLog -Operation "CopyItem" -Path $regPath -Target $DestinationPath
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
            Write-MutationLog -Operation "CopyItem" -Path $transcoded -Target $DestinationPath
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

function Update-Phase1State {
    param(
        [string]$StateFilePath,
        [string]$Status,
        [string]$CurrentPhase = "Phase1",
        [string]$BlockedReason = $null
    )

    Update-PhaseState -Context $RuntimeContext -StateFilePath $StateFilePath -PhaseKey "phase1" -Status $Status -CurrentPhase $CurrentPhase -BlockedReason $BlockedReason -OnPersist {
        param($persistedPath)
        Write-MutationLog -Operation "SetContent" -Path $persistedPath -Target ""
    }
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
    Update-Phase1State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "UnsupportedOS"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-AutomationEnabledMode -StateFilePath $StateFile)) {
    Write-Host "[X] Rendering rejected because automation is disabled (automation.enabledmode=False)."
    Write-Host "[INFO] Set automation.enabledmode=True in state and run BackgroundModifier -Action Run in an interactive session."
    Update-Phase1State -StateFilePath $StateFile -Status "blocked" -CurrentPhase "Blocked" -BlockedReason "AutomationDisabledMode"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# --- Correct asset names (JPG) ---
$DesktopImage = Join-Path $AssetsRoot "Desktop.jpg"
$DesktopBase = Join-Path $AssetsRoot "DesktopBase.jpg"
$DesktopRendered = Join-Path $AssetsRoot "desktop_rendered.jpg"
$LogonImage = Join-Path $AssetsRoot "Logon.jpg"
$LogonBase   = Join-Path $AssetsRoot "LogonBase.jpg"
$LogonRendered = Join-Path $AssetsRoot "logon_rendered.jpg"

Update-Phase1State -StateFilePath $StateFile -Status "running" -CurrentPhase "Phase1" -BlockedReason $null

# Phase 1 is collection-only. Image asset management and rendering are Phase 2 responsibilities.
# No image manipulation in Phase 1.

Write-Host "--- Collecting system information ---"

# --- Collect system info for text overlay ---
$hostname    = $env:COMPUTERNAME
$username    = $env:USERNAME
$osVersion   = (Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DisplayVersion" -ErrorAction SilentlyContinue)
$buildNumber = (Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "CurrentBuildNumber" -ErrorAction SilentlyContinue)

# Collect last boot time (for reboot detection across sessions)
try {
    $lastBootTimeObj = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop | Select-Object -ExpandProperty LastBootUpTime
    $lastBootTime = $lastBootTimeObj.ToString("yyyyMMdd_HHmmss")
} catch {
    Write-Host "[X] Failed to collect last boot time: $($_.Exception.Message)"
    Update-Phase1State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "LastBootTimeUnavailable"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

# Collect IP addresses with LAN/WLAN detection (1 LAN, 1 WLAN only)
$lanAddresses = @()
$wlanAddresses = @()
Get-NetIPConfiguration -ErrorAction SilentlyContinue |
    Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
    ForEach-Object {
        $ip = $_.IPv4Address.IPAddress
        $adapter = $_.NetAdapter
        $adapterName = $adapter.Name
        $description = $adapter.InterfaceDescription
        
        # Skip APIPA addresses
        if ($ip -match '^169\.254\.') {
            if ($TraceMode) { Write-Host "[SKIP] $adapterName - APIPA address $ip" }
            return
        }
        
        # Skip VLAN, Bluetooth, and VPN/Tunnel adapters
        if ($description -match '(vlan|virtual.*lan|bluetooth|bnep|tun|tap|vpn|tunnel|openvpn)') {
            if ($TraceMode) {
                $reason = if ($description -match 'vlan|virtual') { "VLAN" }
                          elseif ($description -match 'bluetooth|bnep') { "Bluetooth" }
                          else { "VPN/Tunnel" }
                Write-Host "[SKIP] $adapterName - $reason adapter ($description)"
            }
            return
        }
        
        # Detect LAN vs WLAN based on adapter type
        if ($description -match '(wireless|wi-fi|wifi|wlan)') {
            if ($wlanAddresses.Count -lt 1) {
                if ($TraceMode) { Write-Host "[ACCEPT] $adapterName - WLAN at $ip" }
                $wlanAddresses += $ip
            } else {
                if ($TraceMode) { Write-Host "[SKIP] $adapterName - WLAN slot filled (additional WLAN $ip)" }
            }
        } else {
            if ($lanAddresses.Count -lt 1) {
                if ($TraceMode) { Write-Host "[ACCEPT] $adapterName - LAN at $ip" }
                $lanAddresses += $ip
            } else {
                if ($TraceMode) { Write-Host "[SKIP] $adapterName - LAN slot filled (additional LAN $ip)" }
            }
        }
    }

$ipInfo = @()
if ($lanAddresses.Count -gt 0) { $ipInfo += "$($lanAddresses[0]) (LAN)" }
if ($wlanAddresses.Count -gt 0) { $ipInfo += "$($wlanAddresses[0]) (WLAN)" }
$ipAddresses = if ($ipInfo.Count -gt 0) { $ipInfo -join "`n" } else { "(none)" }
$renderTime  = (Get-Date).ToString("yyyy-MM-dd HH:mm")
$efiLabel    = Get-EfiVolumeLabel
$bcdDefault  = Get-DefaultBcdIdentifier

if ($bcdDefault -in @("(unavailable)", "(error)")) {
    Write-Host "[X] Failed to retrieve BCD information: $bcdDefault"
    Update-Phase1State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "BcdInfoUnavailable"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

$volInv      = Get-VolumeInventorySummary

$tableRows = @(
    [pscustomobject]@{ Key = "Host";      Value = $hostname }
    [pscustomobject]@{ Key = "User";      Value = $username }
    [pscustomobject]@{ Key = "OS";        Value = "Windows 11 $osVersion (Build $buildNumber)" }
    [pscustomobject]@{ Key = "IP";        Value = if ($ipAddresses) { $ipAddresses } else { "(none)" } }
    [pscustomobject]@{ Key = "EFI";       Value = $efiLabel }
    [pscustomobject]@{ Key = "BCD";       Value = $bcdDefault }
    [pscustomobject]@{ Key = "VolumeInv"; Value = $volInv }
    [pscustomobject]@{ Key = "Rendered";  Value = $renderTime }
)

$overlayTitle = "BackgroundModifier - Ver $ScriptVersion"
$tableFormat = @{ MaxValueChars = 50 }

# Bright orange text for overlay readability and visual consistency with the desktop base circle.
# --- Compute systemInfo hash for change detection (no rendering in Phase 1) ---
$systemInfo = @{
    hostname = $hostname
    username = $username
    osVersion = $osVersion
    buildNumber = $buildNumber
    lastBootTime = $lastBootTime
    ipAddresses = $ipAddresses
    efiLabel = $efiLabel
    bcdDefault = $bcdDefault
    volumeInventory = $volInv
}

try {
    $systemInfoHash = Compute-SystemInfoHash -SystemInfo $systemInfo
    Write-Host "[OK] System info hash computed: $systemInfoHash"
}
catch {
    Write-Host "[X] Failed to compute system info hash: $($_.Exception.Message)"
    Update-Phase1State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "ComputeHashFailed"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "--- Summary ---"
Write-Host "Hostname: $hostname"
Write-Host "Username: $username"
Write-Host "OS Version: $osVersion (Build $buildNumber)"
Write-Host "Last Boot Time: $lastBootTime"
Write-Host "IP Addresses: $ipAddresses"
Write-Host "EFI Label: $efiLabel"
Write-Host "BCD Default: $bcdDefault"
Write-Host "Volume Inventory: $volInv"
Write-Host "System Info Hash: $systemInfoHash"

# --- Update state with systemInfo for Phase 2 ---
try {
    $state = Get-RuntimeState -Context $RuntimeContext -StateFilePath $StateFile
    
    # Add or update systemInfo property (state is now mutable via psobject.Copy())
    $state | Add-Member -MemberType NoteProperty -Name "systemInfo" -Value @{
        hostname = $hostname
        username = $username
        osVersion = $osVersion
        buildNumber = $buildNumber
        lastBootTime = $lastBootTime
        ipAddresses = $ipAddresses
        efiLabel = $efiLabel
        bcdDefault = $bcdDefault
        volumeInventory = $volInv
        hash = $systemInfoHash
        collectedAtUtc = (Get-Date).ToString("yyyyMMdd_HHmmss")
        collectionSource = "Phase1Renderer"
        collectionSourceVersion = $ScriptVersion
    } -Force
    
    Set-RuntimeState -StateFilePath $StateFile -State $state
    Write-MutationLog -Operation "SetContent" -Path $StateFile -Target ""
    Write-Host "[OK] System info stored in state.json"
}
catch {
    Write-Host "[X] Failed to write system info to state: $($_.Exception.Message)"
    Update-Phase1State -StateFilePath $StateFile -Status "failed" -CurrentPhase "Blocked" -BlockedReason "StateWriteFailed"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Update-Phase1State -StateFilePath $StateFile -Status "ready" -CurrentPhase "Phase1" -BlockedReason $null
Write-Host "[OK] Phase 1 collection completed successfully. Rendering deferred to Phase 2."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

