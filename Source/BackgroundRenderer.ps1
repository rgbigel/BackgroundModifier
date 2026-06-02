# =================================================================================================
#  Module:      BackgroundRenderer.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (background rendering)
# =================================================================================================

param(
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
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ConfigTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "RenderTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "BootTools.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

$LogRoot     = $Global:LogRoot
$AssetsRoot  = $Global:AssetsRoot
$RenderRoot  = $Global:RenderRoot

if ($TraceMode) {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $TranscriptPath = Join-Path $LogRoot "Renderer_$timestamp.log"
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}

Write-Host "=== BackgroundModifier BackgroundRenderer.ps1 (v6.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$DesktopBase = Join-Path $AssetsRoot "DesktopBase.jpg"
$LogonBase   = Join-Path $AssetsRoot "LogonBase.jpg"

$OutputLogon   = Join-Path $RenderRoot "Logon.jpg"
$OutputDesktop = Join-Path $RenderRoot "Desktop.jpg"

function Get-AssetAccentColor {
    param([string]$ImagePath)

    Add-Type -AssemblyName System.Drawing

    $fallback = @{ R = 255; G = 153; B = 51 }
    if (-not (Test-Path -LiteralPath $ImagePath)) {
        return $fallback
    }

    $img = $null
    $bmp = $null
    try {
        $img = [System.Drawing.Image]::FromFile($ImagePath)
        $bmp = New-Object System.Drawing.Bitmap $img

        $xStart = [Math]::Max(0, [int]([Math]::Floor($bmp.Width * 0.70)))
        $xEnd = [Math]::Max(0, [int]([Math]::Floor($bmp.Width * 0.98)))
        $yStart = [Math]::Max(0, [int]([Math]::Floor($bmp.Height * 0.70)))
        $yEnd = [Math]::Max(0, [int]([Math]::Floor($bmp.Height * 0.98)))
        $step = 6

        $sumR = 0.0
        $sumG = 0.0
        $sumB = 0.0
        $sumW = 0.0

        for ($y = $yStart; $y -lt $yEnd; $y += $step) {
            for ($x = $xStart; $x -lt $xEnd; $x += $step) {
                $c = $bmp.GetPixel($x, $y)
                $h = $c.GetHue()
                $s = $c.GetSaturation()
                $v = $c.GetBrightness()

                if ($h -ge 15 -and $h -le 55 -and $s -ge 0.20 -and $v -ge 0.18) {
                    $w = [Math]::Max(0.01, ($s * $v))
                    $sumR += $c.R * $w
                    $sumG += $c.G * $w
                    $sumB += $c.B * $w
                    $sumW += $w
                }
            }
        }

        if ($sumW -gt 0.0) {
            return @{
                R = [int][Math]::Round($sumR / $sumW)
                G = [int][Math]::Round($sumG / $sumW)
                B = [int][Math]::Round($sumB / $sumW)
            }
        }

        return $fallback
    }
    catch {
        return $fallback
    }
    finally {
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

Write-Host "--- Asset check ---"

$AssetsRootFull = [System.IO.Path]::GetFullPath($AssetsRoot).TrimEnd('\\')
$SystemRootFull = [System.IO.Path]::GetFullPath($Global:SystemRoot).TrimEnd('\\')
$RenderRootFull = [System.IO.Path]::GetFullPath($RenderRoot).TrimEnd('\\')
$DesktopBaseFull = [System.IO.Path]::GetFullPath($DesktopBase)
$LogonBaseFull = [System.IO.Path]::GetFullPath($LogonBase)

if (-not $DesktopBaseFull.StartsWith($AssetsRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[X] Desktop base source is not under assets root: $DesktopBaseFull"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not $LogonBaseFull.StartsWith($AssetsRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[X] Logon base source is not under assets root: $LogonBaseFull"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($DesktopBaseFull.StartsWith($SystemRootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $DesktopBaseFull.StartsWith($RenderRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[X] Desktop base source must not be under system/rendered roots: $DesktopBaseFull"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if ($LogonBaseFull.StartsWith($SystemRootFull, [System.StringComparison]::OrdinalIgnoreCase) -or $LogonBaseFull.StartsWith($RenderRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "[X] Logon base source must not be under system/rendered roots: $LogonBaseFull"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-Path $DesktopBase)) {
    Write-Host "[X] Missing DesktopBase -> $DesktopBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

if (-not (Test-Path $LogonBase)) {
    Write-Host "[X] Missing LogonBase -> $LogonBase"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "[OK] Base assets present"
Write-Host "[OK] Base source Desktop -> $DesktopBaseFull"
Write-Host "[OK] Base source Logon   -> $LogonBaseFull"

Write-Host "--- Rendering images ---"

try {
    if (-not (Test-Path -LiteralPath $RenderRoot)) {
        New-Item -Path $RenderRoot -ItemType Directory -Force | Out-Null
    }

    $stateFile = Join-Path $Global:SystemRoot "State.json"
    $osValue = [System.Environment]::OSVersion.VersionString
    $buildValue = ""
    $hostValue = $env:COMPUTERNAME
    $userValue = $env:USERNAME
    $logonValue = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $bootValue = ""
    $espDiskValue = ""
    $espPartValue = ""
    $espLabelValue = ""
    $espDriveValue = ""
    $espBootLoaderValue = ""
    $espEfiValue = ""
    $tableFormat = @{}
    $state = $null

    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Load-Config -Path $stateFile
            if ($state -and $state.OS -and $state.OS.Caption) {
                $osValue = [string]$state.OS.Caption
            }
            if ($state -and $state.OS -and $state.OS.BuildNumber) {
                $buildValue = [string]$state.OS.BuildNumber
            }
            if ($state -and $state.System -and $state.System.ComputerName) {
                $hostValue = [string]$state.System.ComputerName
            }
            if ($state -and $state.UserInfo -and $state.UserInfo.UserName) {
                $userValue = [string]$state.UserInfo.UserName
            }
            if ($state -and $state.Meta -and $state.Meta.LastRunInfo) {
                $logonValue = [string]$state.Meta.LastRunInfo
            }
            if ($state -and $state.OS -and $state.OS.LastBootUpTime) {
                $bootSource = [string]$state.OS.LastBootUpTime
                if ($bootSource -match '\/Date\((\d+)\)\/') {
                    $bootValue = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Matches[1]).LocalDateTime.ToString('yyyyMMdd_HHmmss')
                }
                elseif ($bootSource -match '^\d{14}') {
                    $bootValue = [DateTime]::ParseExact($bootSource.Substring(0,14), 'yyyyMMddHHmmss', [System.Globalization.CultureInfo]::InvariantCulture).ToString('yyyyMMdd_HHmmss')
                }
                else {
                    try {
                        $bootValue = ([DateTime]$bootSource).ToString('yyyyMMdd_HHmmss')
                    }
                    catch {
                        $bootValue = $bootSource
                    }
                }
            }
            if ($state -and $state.ESP -and $state.ESP.Active) {
                if ($state.ESP.Active.DiskNumber -ne $null) { $espDiskValue = [string]$state.ESP.Active.DiskNumber }
                if ($state.ESP.Active.PartitionNumber -ne $null) { $espPartValue = [string]$state.ESP.Active.PartitionNumber }
                if ($state.ESP.Active.VolumeLabel -ne $null) { $espLabelValue = [string]$state.ESP.Active.VolumeLabel }
                if ($state.ESP.Active.DriveLetter -ne $null) { $espDriveValue = [string]$state.ESP.Active.DriveLetter }
                if ($state.ESP.Active.BootLoaderPath -ne $null) { $espBootLoaderValue = [string]$state.ESP.Active.BootLoaderPath }
            }
            if ($state -and $state.Meta -and $state.Meta.RenderTableFormat) {
                if ($state.Meta.RenderTableFormat.KeyWidth -ne $null) {
                    $tableFormat["KeyWidth"] = [int]$state.Meta.RenderTableFormat.KeyWidth
                }
                if ($state.Meta.RenderTableFormat.ValueWidth -ne $null) {
                    $tableFormat["ValueWidth"] = [int]$state.Meta.RenderTableFormat.ValueWidth
                }
            }
        }
        catch {
            Write-Host "[WARN] State.json unreadable, using live environment fields."
        }
    }

    try {
        $cv = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        if ($cv.CurrentBuildNumber) {
            if ($cv.UBR -ne $null) {
                $buildValue = ("{0}.{1}" -f [string]$cv.CurrentBuildNumber, [string]$cv.UBR)
            }
            else {
                $buildValue = [string]$cv.CurrentBuildNumber
            }
        }
    }
    catch {
        if ([string]::IsNullOrWhiteSpace($buildValue)) {
            $buildValue = [string][System.Environment]::OSVersion.Version.Build
        }
    }

    $osValue = $osValue -replace '^Microsoft\s+', 'MS '
    $osValue = $osValue -replace 'Windows\s+11', 'W11'

    $espId = ""
    if (-not [string]::IsNullOrWhiteSpace($espDiskValue) -and -not [string]::IsNullOrWhiteSpace($espPartValue)) {
        $espId = ("D{0}P{1}" -f $espDiskValue, $espPartValue)
    }

    if (-not [string]::IsNullOrWhiteSpace($espId) -and -not [string]::IsNullOrWhiteSpace($espLabelValue)) {
        $espEfiValue = ("{0} ({1})" -f $espId, $espLabelValue)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($espId)) {
        $espEfiValue = $espId
    }
    else {
        $espEfiValue = $espLabelValue
    }

    if ([string]::IsNullOrWhiteSpace($espBootLoaderValue)) {
        try {
            $espBootLoaderValue = [string](Get-BootLoaderPathFromCurrentBcd)
        }
        catch {
            $espBootLoaderValue = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($espBootLoaderValue)) {
        $defaultBootLoaderPath = "\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
        if (-not [string]::IsNullOrWhiteSpace($espDriveValue)) {
            $espBootLoaderValue = ("{0}:{1}" -f $espDriveValue, $defaultBootLoaderPath)
        }
        elseif (-not [string]::IsNullOrWhiteSpace($espId)) {
            $espBootLoaderValue = ("ESP {0}{1}" -f $espId, $defaultBootLoaderPath)
        }
        else {
            $espBootLoaderValue = $defaultBootLoaderPath
        }
    }

    $tableRows = @(
        [ordered]@{ Key = "OS"; Value = $osValue },
        [ordered]@{ Key = "Build"; Value = $buildValue },
        [ordered]@{ Key = "Host"; Value = $hostValue },
        [ordered]@{ Key = "User"; Value = $userValue },
        [ordered]@{ Key = "Boot"; Value = $bootValue },
        [ordered]@{ Key = "Logon"; Value = $logonValue },
        [ordered]@{ Key = "ESP/EFI"; Value = $espEfiValue },
        [ordered]@{ Key = "Boot Ldr"; Value = $espBootLoaderValue }
    )

    if (-not [string]::IsNullOrWhiteSpace($espDriveValue)) {
        $tableRows += [ordered]@{ Key = "ESP Drv"; Value = $espDriveValue }
    }

    $logonUserValue = if ([string]::IsNullOrWhiteSpace($userValue)) { "(last)" } else { "(last) $userValue" }
    $logonTableRows = @(
        $tableRows | ForEach-Object {
            if ([string]$_.Key -eq "User") {
                [ordered]@{ Key = "User"; Value = $logonUserValue }
            }
            else {
                $_
            }
        }
    )

    $renderTitleLogon = "BackgroundModifier V6.0.0 Logon"
    $renderTitleDesktop = "BackgroundModifier V6.0.0"
    $accentColor = Get-AssetAccentColor -ImagePath $DesktopBase

    $targetKeyWidth = ($logonTableRows | ForEach-Object { [string]$_.Key } | Measure-Object -Maximum Length).Maximum
    if (-not $targetKeyWidth) { $targetKeyWidth = 5 }

    $titleTargetChars = [Math]::Max($renderTitleLogon.Length, $renderTitleDesktop.Length)
    $osTargetChars = $targetKeyWidth + 3 + ([string]$osValue).Length
    $targetTotalChars = [Math]::Max($titleTargetChars, $osTargetChars)
    $targetValueWidth = [Math]::Max(5, ($targetTotalChars - $targetKeyWidth - 3))

    $tableFormat["KeyWidth"] = [int]$targetKeyWidth
    $tableFormat["ValueWidth"] = [int]$targetValueWidth

    $resolvedFormat = Render-TextOverlay -BaseImage $LogonBase -OutputPath $OutputLogon -Title $renderTitleLogon -TableRows $logonTableRows -TableFormat $tableFormat -TextColor $accentColor
    Render-TextOverlay -BaseImage $DesktopBase -OutputPath $OutputDesktop -Title $renderTitleDesktop -TableRows $tableRows -TableFormat @{
        KeyWidth = $resolvedFormat.KeyWidth
        ValueWidth = $resolvedFormat.ValueWidth
    } -TextColor $accentColor | Out-Null

    if ($state -and $resolvedFormat) {
        if (-not ($state.PSObject.Properties.Name -contains "Meta")) {
            $state | Add-Member -NotePropertyName Meta -NotePropertyValue ([PSCustomObject]@{})
        }

        $state.Meta | Add-Member -Force -NotePropertyName RenderTableFormat -NotePropertyValue ([PSCustomObject]@{
            KeyWidth = [int]$resolvedFormat.KeyWidth
            ValueWidth = [int]$resolvedFormat.ValueWidth
            UpdatedAt = (Get-Date).ToString("s")
        })

        Save-Config -Path $stateFile -Config $state
    }
}
catch {
    Write-Host "[X] Rendering failed: $($_.Exception.Message)"
    if ($TraceMode) { Stop-Transcript | Out-Null }
    exit 1
}

Write-Host "--- Summary ---"
Write-Host "[OK] Rendering completed successfully."

if ($TraceMode) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}


