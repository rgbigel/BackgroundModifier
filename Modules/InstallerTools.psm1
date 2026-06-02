# =================================================================================================
#  Module:      InstallerTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
$16.0.0
#  Purpose:     Shared helper functions used by installation and setup scripts.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (installation utilities)
# =================================================================================================

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-HelpRequested {
    param(
        [string[]]$Arguments
    )

    foreach ($argument in $Arguments) {
        if ([string]::IsNullOrWhiteSpace($argument)) {
            continue
        }

        switch -Regex ($argument) {
            '^(?:-|/)(?:\?|h|help)$' { return $true }
        }
    }

    return $false
}

function Show-InstallerUsage {
    param(
        [string]$Title,
        [string[]]$UsageLines
    )

    Write-Host "=== $Title ==="
    foreach ($line in $UsageLines) {
        Write-Host $line
    }
}

function Wait-ForInstallerExit {
    param(
        [switch]$Pause,
        [string]$Message = "Press Enter to exit..."
    )

    if (-not $Pause) {
        return
    }

    if (-not [Environment]::UserInteractive) {
        return
    }

    try {
        [void](Read-Host $Message)
    }
    catch {
    }
}

function Get-PowerShellHostPath {
    $candidates = @(
        (Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Get-Command powershell.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "No PowerShell host was found (pwsh.exe or powershell.exe)."
}

function Invoke-SelfElevated {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [hashtable]$NamedArguments,

        [string]$WorkingDirectory
    )

    $hostPath = Get-PowerShellHostPath
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $ScriptPath
    )

    if ($NamedArguments) {
        foreach ($entry in $NamedArguments.GetEnumerator() | Sort-Object Name) {
            $name = [string]$entry.Key
            $value = $entry.Value

            if ($value -is [bool]) {
                if ($value) {
                    $argumentList += "-$name"
                }
                continue
            }

            if ($null -eq $value) {
                continue
            }

            $argumentList += "-$name"
            $argumentList += [string]$value
        }
    }

    $startProcessArgs = @{
        FilePath = $hostPath
        Verb = 'RunAs'
        ArgumentList = $argumentList
        Wait = $true
        PassThru = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startProcessArgs.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @startProcessArgs
    return $process.ExitCode
}

function Start-ElevatedPowerShellSession {
    param(
        [string]$WorkingDirectory = (Get-Location).Path,
        [string]$Command
    )

    $hostPath = Get-PowerShellHostPath
    $argumentList = @(
        '-NoExit',
        '-ExecutionPolicy', 'Bypass'
    )

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $argumentList += '-Command'
        $argumentList += $Command
    }

    $startProcessArgs = @{
        FilePath = $hostPath
        Verb = 'RunAs'
        ArgumentList = $argumentList
    }

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startProcessArgs.WorkingDirectory = $WorkingDirectory
    }

    Start-Process @startProcessArgs | Out-Null
}

function Require-Admin {
    if (-not (Test-Admin)) {
        Write-Host "[ERROR] Administrator rights required."
        exit 1
    }
}

function Copy-Safe {
    param(
        [string]$Source,
        [string]$Destination
    )
    Copy-Item -Path $Source -Destination $Destination -Force
}
Export-ModuleMember -Function *

