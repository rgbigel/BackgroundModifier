$repoRoot = Join-Path $PSScriptRoot "..\.."
$installRoot = Join-Path $repoRoot "Install"

Describe "Install script mocked execution" {
    Context "Disable.ps1" {
        It "calls Require-Admin once and disables both expected tasks when present" {
            $scriptPath = Join-Path $installRoot "Disable.ps1"

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
            Mock Disable-ScheduledTask {}

            { & $scriptPath } | Should Not Throw

            Assert-MockCalled Require-Admin -Exactly 1 -Scope It
            Assert-MockCalled Get-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Disable-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Disable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-BootIdentity" } -Exactly 1 -Scope It
            Assert-MockCalled Disable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-Autorun" } -Exactly 1 -Scope It
        }

        It "skips disable operation for missing task" {
            $scriptPath = Join-Path $installRoot "Disable.ps1"

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Get-ScheduledTask {
                if ($TaskName -eq "BackgroundModifier-BootIdentity") {
                    return [pscustomobject]@{ TaskName = $TaskName }
                }
                return $null
            }
            Mock Disable-ScheduledTask {}

            { & $scriptPath } | Should Not Throw

            Assert-MockCalled Get-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Disable-ScheduledTask -Exactly 1 -Scope It
            Assert-MockCalled Disable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-BootIdentity" } -Exactly 1 -Scope It
        }

        It "continues when disable command fails for one task" {
            $scriptPath = Join-Path $installRoot "Disable.ps1"

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
            Mock Disable-ScheduledTask {
                if ($TaskName -eq "BackgroundModifier-BootIdentity") {
                    throw "disable failed"
                }
            }

            { & $scriptPath } | Should Not Throw

            Assert-MockCalled Get-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Disable-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Disable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-Autorun" } -Exactly 1 -Scope It
        }
    }

    Context "Enable.ps1" {
        It "calls Require-Admin once and enables both expected tasks when present" {
            $scriptPath = Join-Path $installRoot "Enable.ps1"

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
            Mock Enable-ScheduledTask {}

            { & $scriptPath } | Should Not Throw

            Assert-MockCalled Require-Admin -Exactly 1 -Scope It
            Assert-MockCalled Get-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Enable-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Enable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-BootIdentity" } -Exactly 1 -Scope It
            Assert-MockCalled Enable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-Autorun" } -Exactly 1 -Scope It
        }

        It "skips enable operation for missing task" {
            $scriptPath = Join-Path $installRoot "Enable.ps1"

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Get-ScheduledTask {
                if ($TaskName -eq "BackgroundModifier-BootIdentity") {
                    return [pscustomobject]@{ TaskName = $TaskName }
                }
                return $null
            }
            Mock Enable-ScheduledTask {}

            { & $scriptPath } | Should Not Throw

            Assert-MockCalled Get-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Enable-ScheduledTask -Exactly 1 -Scope It
            Assert-MockCalled Enable-ScheduledTask -ParameterFilter { $TaskName -eq "BackgroundModifier-BootIdentity" } -Exactly 1 -Scope It
        }
    }

    Context "Uninstall.ps1" {
        It "runs teardown calls and keeps runtime data by default" {
            $scriptPath = Join-Path $installRoot "Uninstall.ps1"
            $runtimeRoot = Join-Path $env:TEMP ("BM_UninstallRuntime_" + [guid]::NewGuid().ToString("N"))
            $cmdRoot = Join-Path $env:TEMP ("BM_UninstallCmd_" + [guid]::NewGuid().ToString("N"))

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Unregister-ScheduledTask {}
            Mock Remove-NoBlur {}
            Mock Test-Path { $false }
            Mock Remove-Item {}
            Mock Get-ChildItem { @() }

            { & $scriptPath -RuntimeRoot $runtimeRoot -CmdRoot $cmdRoot } | Should Not Throw

            Assert-MockCalled Require-Admin -Exactly 1 -Scope It
            Assert-MockCalled Unregister-ScheduledTask -Exactly 2 -Scope It
            Assert-MockCalled Remove-NoBlur -Exactly 1 -Scope It
            Assert-MockCalled Remove-Item -Exactly 0 -Scope It
        }

        It "removes runtime root when RemoveRuntimeData is set and root exists" {
            $scriptPath = Join-Path $installRoot "Uninstall.ps1"
            $runtimeRoot = Join-Path $env:TEMP ("BM_UninstallRuntime_" + [guid]::NewGuid().ToString("N"))
            $cmdRoot = Join-Path $env:TEMP ("BM_UninstallCmd_" + [guid]::NewGuid().ToString("N"))

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Unregister-ScheduledTask {}
            Mock Remove-NoBlur {}
            Mock Test-Path {
                if ($LiteralPath -eq $runtimeRoot) { return $true }
                return $false
            }
            Mock Remove-Item {}
            Mock Get-ChildItem { @() }

            { & $scriptPath -RuntimeRoot $runtimeRoot -CmdRoot $cmdRoot -RemoveRuntimeData } | Should Not Throw

            Assert-MockCalled Remove-Item -Exactly 1 -Scope It
            Assert-MockCalled Remove-Item -ParameterFilter { $LiteralPath -eq $runtimeRoot -and $Recurse -and $Force } -Exactly 1 -Scope It
        }

        It "removes existing cmd entries and runtime links in default mode" {
            $scriptPath = Join-Path $installRoot "Uninstall.ps1"
            $runtimeRoot = Join-Path $env:TEMP ("BM_UninstallRuntime_" + [guid]::NewGuid().ToString("N"))
            $cmdRoot = Join-Path $env:TEMP ("BM_UninstallCmd_" + [guid]::NewGuid().ToString("N"))

            $cmdEntry1 = Join-Path $cmdRoot "BackgroundModifier-Setup.ps1"
            $cmdEntry2 = Join-Path $cmdRoot "BackgroundModifier-Verify.ps1"
            $solutionCodeRoot = Join-Path $runtimeRoot "SolutionCode"
            $runtimeLink = Join-Path $solutionCodeRoot "BootIdentity.ps1"

            Mock Import-Module {}
            Mock Set-Flags { [pscustomobject]@{ DebugMode = $false; TraceMode = $false } }
            Mock Require-Admin {}
            Mock Unregister-ScheduledTask {}
            Mock Remove-NoBlur {}
            Mock Test-Path {
                if ($LiteralPath -eq $cmdEntry1) { return $true }
                if ($LiteralPath -eq $cmdEntry2) { return $true }
                if ($LiteralPath -eq $solutionCodeRoot) { return $true }
                return $false
            }
            Mock Get-ChildItem {
                @([pscustomobject]@{ FullName = $runtimeLink })
            }
            Mock Remove-Item {}

            { & $scriptPath -RuntimeRoot $runtimeRoot -CmdRoot $cmdRoot } | Should Not Throw

            Assert-MockCalled Remove-Item -Exactly 3 -Scope It
            Assert-MockCalled Remove-Item -ParameterFilter { $LiteralPath -eq $cmdEntry1 -and $Force } -Exactly 1 -Scope It
            Assert-MockCalled Remove-Item -ParameterFilter { $LiteralPath -eq $cmdEntry2 -and $Force } -Exactly 1 -Scope It
            Assert-MockCalled Remove-Item -ParameterFilter { $LiteralPath -eq $runtimeLink -and $Force } -Exactly 1 -Scope It
        }
    }
}
