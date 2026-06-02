$modulePath = Join-Path $PSScriptRoot "..\..\Modules\SetFlagsTool.psm1"
Import-Module $modulePath -Force

Describe "SetFlagsTool" {
    It "exports Set-Flags" {
        Get-Command Set-Flags -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "returns normal mode by default" {
        $result = Set-Flags
        $result.Mode | Should Be "normal"
        $result.TraceMode | Should Be $false
        $result.DebugMode | Should Be $false
        $result.VerboseMode | Should Be $false
    }

    It "returns trace mode and implies debug when -T is set" {
        $result = Set-Flags -T
        $result.Mode | Should Be "trace"
        $result.TraceMode | Should Be $true
        $result.DebugMode | Should Be $true
    }

    It "sets verbose mode when -V is set" {
        $result = Set-Flags -V
        $result.VerboseMode | Should Be $true
    }
}
