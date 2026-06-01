# =================================================================================================
#  Module:      BackgroundRenderer.ps1
#  Path:        .\Source
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (background rendering)
# =================================================================================================

param(
    [switch]$t,
    [switch]$d
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
Import-Module (Join-Path $ModuleRoot "RenderTools.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t -D:$d
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

Write-Host "=== BackgroundModifier Renderer (v1.001) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$DesktopBase = Join-Path $AssetsRoot "DesktopBase.jpg"
$LogonBase   = Join-Path $AssetsRoot "LogonBase.jpg"

$OutputLogon   = Join-Path $RenderRoot "Logon.jpg"
$OutputDesktop = Join-Path $RenderRoot "Desktop.jpg"

Write-Host "--- Asset check ---"

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

Write-Host "--- Rendering images ---"

try {
    if (-not (Test-Path -LiteralPath $RenderRoot)) {
        New-Item -Path $RenderRoot -ItemType Directory -Force | Out-Null
    }

    $stateFile = Join-Path $Global:SystemRoot "State.json"
    $osText = "OS: $([System.Environment]::OSVersion.VersionString)"
    $hostText = "Host: $env:COMPUTERNAME"
    $userText = "User: $env:USERNAME"
    $stampText = "Run: $((Get-Date).ToString('yyyyMMdd_HHmmss'))"

    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            if ($state -and $state.OS -and $state.OS.Caption) {
                $osText = "OS: $($state.OS.Caption)"
            }
            if ($state -and $state.System -and $state.System.ComputerName) {
                $hostText = "Host: $($state.System.ComputerName)"
            }
            if ($state -and $state.UserInfo -and $state.UserInfo.UserName) {
                $userText = "User: $($state.UserInfo.UserName)"
            }
            if ($state -and $state.Meta -and $state.Meta.LastRunInfo) {
                $stampText = "Run: $($state.Meta.LastRunInfo)"
            }
        }
        catch {
            Write-Host "[WARN] State.json unreadable, using live environment fields."
        }
    }

    $lines = @(
        $osText,
        $hostText,
        $userText,
        $stampText
    )

    Render-TextOverlay -BaseImage $LogonBase -OutputPath $OutputLogon -Title "BackgroundModifier Logon" -Lines $lines
    Render-TextOverlay -BaseImage $DesktopBase -OutputPath $OutputDesktop -Title "BackgroundModifier Desktop" -Lines $lines
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
