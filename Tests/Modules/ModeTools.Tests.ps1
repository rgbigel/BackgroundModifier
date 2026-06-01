$modulePath = Join-Path $PSScriptRoot "..\..\Modules\ModeTools.psm1"
Import-Module $modulePath -Force

Describe "ModeTools" {
    It "exports expected functions" {
        Get-Command Show-DebugState -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Show-TraceState -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "does not throw when debug state is true or false" {
        { Show-DebugState -Enabled $true } | Should Not Throw
        { Show-DebugState -Enabled $false } | Should Not Throw
    }

    It "does not throw when trace state is true or false" {
        { Show-TraceState -Enabled $true } | Should Not Throw
        { Show-TraceState -Enabled $false } | Should Not Throw
    }
}
