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
}
