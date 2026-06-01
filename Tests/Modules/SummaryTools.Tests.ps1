$modulePath = Join-Path $PSScriptRoot "..\..\Modules\SummaryTools.psm1"
Import-Module $modulePath -Force

Describe "SummaryTools" {
    It "exports Show-Summary" {
        Get-Command Show-Summary -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "does not throw when message is provided" {
        { Show-Summary -Message "unit-summary" } | Should Not Throw
    }

    It "does not throw when message is empty" {
        { Show-Summary -Message "" } | Should Not Throw
    }
}
