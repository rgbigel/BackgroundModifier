# =================================================================================================
#  Module:      Setup.ps1
#  Path:        .\Install
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      6.0.0  --------  Added cmd entry-point provisioning and verifier alignment.
#      5.000  --------  Initial module creation for Consolidated Architecture (installer)
# =================================================================================================

param(
    [switch]$t,
    [Alias('i')]
    [switch]$IncludeTestLinks,
    [Alias('c')]
    [string]$CmdRoot = "D:\OneDrive\cmd",
    [Alias('r')]
    [string]$RuntimeRoot = "C:\BootOpsHub"
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
Import-Module (Join-Path $ModuleRoot "ErrorTools.psm1") -DisableNameChecking -Force
Import-Module (Join-Path $ModuleRoot "Validation.psm1") -Force
Import-Module (Join-Path $ModuleRoot "ModeTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SummaryTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SetFlagsTool.psm1") -Force
Import-Module (Join-Path $ModuleRoot "InstallerTools.psm1") -Force
Import-Module (Join-Path $ModuleRoot "SchedulerTools.psm1") -Force

$WarningPreference = $prev

$flags = Set-Flags -T:$t
$TraceMode = $flags.TraceMode
$DebugMode = $flags.DebugMode

$TranscriptPath = $null
$TranscriptStarted = $false

Write-Host "=== BackgroundModifier Setup.ps1 (v6.0.0) ==="

if ($DebugMode) { Write-Host "Debug mode enabled" }
if ($TraceMode) { Write-Host "Trace mode enabled - transcript recording started" }

$commandLineArguments = [System.Environment]::GetCommandLineArgs()

if (Test-HelpRequested -Arguments $commandLineArguments) {
    Show-InstallerUsage -Title "BackgroundModifier Setup.ps1 help" -UsageLines @(
        "Usage: Setup.ps1 [-t] [-IncludeTestLinks] [-CmdRoot <path>] [-RuntimeRoot <path>]",
        "  -t: Trace mode (starts transcript and enables implied debug/test-link behavior).",
        "  -IncludeTestLinks (-i): Creates cmd test links and verifies them during setup.",
        "  -CmdRoot (-c): Destination folder for install/menu cmd launchers.",
        "  -RuntimeRoot (-r): Runtime root used for assets, logs, rendered output, and SolutionCode links.",
        "Use /?, /H, or -Help to show this message.",
        "This script self-relaunches with UAC when elevation is required."
    )
    exit 0
}

if (-not (Test-Admin)) {
    Write-Host "[WARN] Setup requires elevation. Relaunching via UAC prompt."
    $elevatedExitCode = Invoke-SelfElevated -ScriptPath $resolvedScriptPath -WorkingDirectory $RepoRootResolved -NamedArguments @{
        CmdRoot = $CmdRoot
        RuntimeRoot = $RuntimeRoot
        t = [bool]$t
    }
    exit $elevatedExitCode
}

try {
    Require-Admin

    if (-not $PSBoundParameters.ContainsKey('IncludeTestLinks')) {
        $IncludeTestLinks = [bool]$t
    }

    # Runtime roots are explicit install-time inputs and become active constants for the process.
    $Global:RootPath = $RuntimeRoot
    $Global:LogRoot = Join-Path $Global:RootPath "logs"
    $Global:AssetsRoot = Join-Path $Global:RootPath "assets"
    $Global:RenderRoot = Join-Path $Global:RootPath "rendered"
    $Global:SystemRoot = Join-Path $Global:RootPath "system"
    $solutionCodeRoot = Join-Path $Global:RootPath "SolutionCode"
    $runtimeSourceRoot = Join-Path $solutionCodeRoot "Source"
    $runtimeModulesRoot = Join-Path $solutionCodeRoot "Modules"
    $runtimeInstallRoot = Join-Path $solutionCodeRoot "Install"

    if ($TraceMode) {
        Ensure-Path -Path $Global:LogRoot | Out-Null
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $TranscriptPath = Join-Path $Global:LogRoot "Setup_$timestamp.log"
        Start-Transcript -Path $TranscriptPath -Force | Out-Null
        $TranscriptStarted = $true
    }

    function New-OrReplaceCmdLauncher {
        param(
            [Parameter(Mandatory = $true)]
            [string]$LauncherPath,

            [Parameter(Mandatory = $true)]
            [string]$ScriptPath,

            [string[]]$FixedArguments = @()
        )

        if (-not (Test-Path -LiteralPath $ScriptPath)) {
            throw "Launcher target script is missing: $ScriptPath"
        }

        $scriptPathEscaped = $ScriptPath.Replace('"', '""')
        $fixedArgumentText = ($FixedArguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '

        $pwshLine = '    pwsh -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%"'
        $powershellLine = '    powershell -NoProfile -ExecutionPolicy Bypass -File "%TARGET_SCRIPT%"'

        if (-not [string]::IsNullOrWhiteSpace($fixedArgumentText)) {
            $pwshLine += (' {0}' -f $fixedArgumentText)
            $powershellLine += (' {0}' -f $fixedArgumentText)
        }

        $pwshLine += ' %*'
        $powershellLine += ' %*'

        $launcherContent = @(
            '@echo off',
            'setlocal',
            ('set "TARGET_SCRIPT={0}"' -f $scriptPathEscaped),
            'where pwsh >nul 2>nul',
            'if %ERRORLEVEL% EQU 0 (',
            $pwshLine,
            ') else (',
            $powershellLine,
            ')',
            'set "EXITCODE=%ERRORLEVEL%"',
            'endlocal & exit /b %EXITCODE%'
        ) -join "`r`n"

        Set-Content -LiteralPath $LauncherPath -Value $launcherContent -Encoding Ascii -Force
        Write-Host "[OK] Created cmd launcher: $LauncherPath -> $ScriptPath"
    }

    function New-OrReplaceTestLink {
        param(
            [Parameter(Mandatory = $true)]
            [string]$LinkPath,

            [Parameter(Mandatory = $true)]
            [string]$TargetPath
        )

        if (-not (Test-Path -LiteralPath $TargetPath)) {
            throw "Test link target is missing: $TargetPath"
        }

        if (Test-Path -LiteralPath $LinkPath) {
            Remove-Item -LiteralPath $LinkPath -Force
        }

        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
        Write-Host "[OK] Created test link: $LinkPath -> $TargetPath"
    }

    function Sync-TestLinks {
        param(
            [string]$CmdRoot,
            [string]$RuntimeSourceRoot,
            [bool]$IncludeTestLinks
        )

        $testLinkMap = @(
            @{ Name = 'BackgroundModifier-BootIdentityTest.ps1'; Target = (Join-Path $RuntimeSourceRoot 'BootIdentity.ps1') },
            @{ Name = 'BackgroundModifier-RenderTest.ps1'; Target = (Join-Path $RuntimeSourceRoot 'BackgroundRenderer.ps1') },
            @{ Name = 'BackgroundModifier-ApplyTest.ps1'; Target = (Join-Path $RuntimeSourceRoot 'BackgroundSetter.ps1') },
            @{ Name = 'BackgroundModifier-LogonStage.ps1'; Target = (Join-Path $RuntimeSourceRoot 'BackgroundSetterStart.ps1') }
        )

        Ensure-Path -Path $CmdRoot | Out-Null

        if (-not $IncludeTestLinks) {
            foreach ($entry in $testLinkMap) {
                $entryPath = Join-Path $CmdRoot $entry.Name
                if (Test-Path -LiteralPath $entryPath) {
                    Remove-Item -LiteralPath $entryPath -Force
                    Write-Host "[OK] Removed test link: $entryPath"
                }
            }
            return
        }

        foreach ($entry in $testLinkMap) {
            New-OrReplaceTestLink -LinkPath (Join-Path $CmdRoot $entry.Name) -TargetPath $entry.Target
        }
    }

    function Sync-RuntimeFiles {
        param(
            [Parameter(Mandatory = $true)]
            [string]$SourceRoot,

            [Parameter(Mandatory = $true)]
            [string]$TargetRoot,

            [Parameter(Mandatory = $true)]
            [string]$Filter
        )

        $sourceFull = [System.IO.Path]::GetFullPath($SourceRoot).TrimEnd('\\')
        $targetFull = [System.IO.Path]::GetFullPath($TargetRoot).TrimEnd('\\')

        if ($sourceFull.Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "[OK] Runtime path already current (source equals target): $targetFull"
            return
        }

        Ensure-Path -Path $TargetRoot | Out-Null

        $sourceItems = @(Get-ChildItem -LiteralPath $SourceRoot -File -Filter $Filter -ErrorAction SilentlyContinue)
        $sourceNames = @{}
        foreach ($sourceItem in $sourceItems) {
            $sourceNames[$sourceItem.Name.ToLowerInvariant()] = $true
        }

        $targetItems = @(Get-ChildItem -LiteralPath $TargetRoot -File -Filter $Filter -ErrorAction SilentlyContinue)
        foreach ($targetItem in $targetItems) {
            if (-not $sourceNames.ContainsKey($targetItem.Name.ToLowerInvariant())) {
                Remove-Item -LiteralPath $targetItem.FullName -Force
                Write-Host "[OK] Removed stale runtime file: $($targetItem.FullName)"
            }
        }

        foreach ($sourceItem in $sourceItems) {
            $targetPath = Join-Path $TargetRoot $sourceItem.Name
            Copy-Safe -Source $sourceItem.FullName -Destination $targetPath
            Write-Host "[OK] Copied runtime file: $targetPath"
        }
    }

    Write-Host "--- Preparing runtime folders ---"
    Ensure-Path -Path $Global:RootPath | Out-Null
    Ensure-Path -Path $Global:LogRoot | Out-Null
    Ensure-Path -Path $Global:AssetsRoot | Out-Null
    Ensure-Path -Path $Global:RenderRoot | Out-Null
    Ensure-Path -Path $Global:SystemRoot | Out-Null
    Ensure-Path -Path $solutionCodeRoot | Out-Null
    Ensure-Path -Path $runtimeSourceRoot | Out-Null
    Ensure-Path -Path $runtimeModulesRoot | Out-Null
    Ensure-Path -Path $runtimeInstallRoot | Out-Null
    Write-Host "[OK] Runtime folder structure prepared under $($Global:RootPath)"

    $repoRoot = $RepoRootResolved
    $packageAssetsRoot = Join-Path $repoRoot "assets"
    $runtimePackageAssetsRoot = Join-Path $solutionCodeRoot "assets"
    $defaultAssetNames = @("DesktopBase.jpg", "LogonBase.jpg")

    if (Test-Path -LiteralPath $packageAssetsRoot) {
        Ensure-Path -Path $runtimePackageAssetsRoot | Out-Null
        foreach ($assetName in $defaultAssetNames) {
            $assetSource = Join-Path $packageAssetsRoot $assetName
            if (Test-Path -LiteralPath $assetSource) {
                $assetPackageTarget = Join-Path $runtimePackageAssetsRoot $assetName
                Copy-Safe -Source $assetSource -Destination $assetPackageTarget
                Write-Host "[OK] Packaged default asset: $assetPackageTarget"
            }
            else {
                Write-Host "[WARN] Package default asset not found: $assetSource"
            }
        }
    }
    else {
        Write-Host "[WARN] Package assets folder not found: $packageAssetsRoot"
    }

    Write-Host "--- Checking required assets ---"
    foreach ($assetName in $defaultAssetNames) {
        $runtimeAssetPath = Join-Path $Global:AssetsRoot $assetName
        if (-not (Test-Path -LiteralPath $runtimeAssetPath)) {
            $seeded = $false
            $candidateSources = @(
                (Join-Path $runtimePackageAssetsRoot $assetName),
                (Join-Path $packageAssetsRoot $assetName)
            )

            foreach ($candidateSource in $candidateSources) {
                if (Test-Path -LiteralPath $candidateSource) {
                    Copy-Safe -Source $candidateSource -Destination $runtimeAssetPath
                    Write-Host "[OK] Seeded missing runtime asset: $runtimeAssetPath"
                    $seeded = $true
                    break
                }
            }

            if (-not $seeded) {
                Write-Host "[WARN] Missing asset and no package default found: $runtimeAssetPath"
            }
        }
        else {
            Write-Host "[OK] Found asset: $runtimeAssetPath"
        }
    }

    Write-Host "--- Syncing runtime payload (Source/Modules/Install) ---"
    Sync-RuntimeFiles -SourceRoot (Join-Path $repoRoot "Source") -TargetRoot $runtimeSourceRoot -Filter "*.ps1"
    Sync-RuntimeFiles -SourceRoot (Join-Path $repoRoot "Modules") -TargetRoot $runtimeModulesRoot -Filter "*.psm1"

    $installPayloadNames = @(
        "Verifyer.ps1",
        "Cleanup.ps1",
        "Enable.ps1",
        "Disable.ps1",
        "Uninstall.ps1",
        "AdminShell.ps1"
    )

    $expectedRuntimeInstallNames = @{}
    foreach ($installName in $installPayloadNames) {
        $expectedRuntimeInstallNames[$installName.ToLowerInvariant()] = $true
    }

    foreach ($installName in $installPayloadNames) {
        $sourcePath = Join-Path $repoRoot (Join-Path "Install" $installName)
        $targetPath = Join-Path $runtimeInstallRoot $installName
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "Required install payload script is missing: $sourcePath"
        }
        Copy-Safe -Source $sourcePath -Destination $targetPath
        Write-Host "[OK] Copied runtime install script: $targetPath"
    }

    Write-Host "--- Cleaning redundant SolutionCode root links ---"
    $redundantSolutionEntries = @(
        "BootIdentity.ps1",
        "BackgroundRenderer.ps1",
        "BackgroundSetter.ps1",
        "BackgroundApply.ps1",
        "Verifyer.ps1"
    )

    foreach ($entryName in $redundantSolutionEntries) {
        $entryPath = Join-Path $solutionCodeRoot $entryName
        if (Test-Path -LiteralPath $entryPath) {
            Remove-Item -LiteralPath $entryPath -Force
            Write-Host "[OK] Removed redundant SolutionCode entry link: $entryPath"
        }
    }

    Write-Host "--- Creating operational entry points in cmd ---"
    Ensure-Path -Path $CmdRoot | Out-Null

    $installLauncherPath = Join-Path $CmdRoot "BackgroundModifier_Install.cmd"
    New-OrReplaceCmdLauncher -LauncherPath $installLauncherPath -ScriptPath $resolvedScriptPath

    $menuLauncherPath = Join-Path $CmdRoot "BackgroundModifier.cmd"
    New-OrReplaceCmdLauncher -LauncherPath $menuLauncherPath -ScriptPath (Join-Path $runtimeInstallRoot "AdminShell.ps1")

    Write-Host "--- Syncing test entry links ---"
    Sync-TestLinks -CmdRoot $CmdRoot -RuntimeSourceRoot $runtimeSourceRoot -IncludeTestLinks ([bool]$IncludeTestLinks)

    Write-Host "--- Registering scheduled automation tasks ---"
    $taskTraceArguments = @()
    if ($TraceMode) {
        $taskTraceArguments = @('-t')
    }

    if (-not (Register-BackgroundTask -TaskName "BackgroundModifier-BootIdentity" -ScriptPath (Join-Path $runtimeSourceRoot "BootIdentity.ps1") -ScriptArguments $taskTraceArguments -TriggerType Startup -RunAs System)) {
        throw "Failed to register BackgroundModifier-BootIdentity"
    }
    if (-not (Register-BackgroundTask -TaskName "BackgroundModifier-Autorun" -ScriptPath (Join-Path $runtimeSourceRoot "BackgroundApply.ps1") -ScriptArguments $taskTraceArguments -TriggerType LogOn -RunAs Interactive)) {
        throw "Failed to register BackgroundModifier-Autorun"
    }

    Write-Host "--- Setup verification ---"
    $verifierScript = Join-Path $runtimeInstallRoot "Verifyer.ps1"
    $verifierArgs = @('-t:' + [string]([bool]$t), '-CmdRoot', $CmdRoot, '-RuntimeRoot', $RuntimeRoot)
    if ($IncludeTestLinks) {
        $verifierArgs += '-IncludeTestLinks'
    }
    & $verifierScript @verifierArgs
    $verifierExitCode = $LASTEXITCODE
    if ($null -eq $verifierExitCode) {
        $verifierExitCode = 0
    }
    if ($verifierExitCode -ne 0) {
        throw "Verifyer failed with exit code $verifierExitCode"
    }

    Write-Host "[OK] Setup completed successfully"
}
catch {
    Write-Host "[X] Setup failed: $($_.Exception.Message)"
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    Wait-ForInstallerExit -Pause:($TraceMode -or $DebugMode) -Message "Setup failed. Press Enter to exit..."
    exit 1
}

if ($TranscriptStarted) {
    Stop-Transcript | Out-Null
    Write-Host "Log written to: $TranscriptPath"
}

Wait-ForInstallerExit -Pause:($TraceMode -or $DebugMode) -Message "Setup completed. Press Enter to exit..."


