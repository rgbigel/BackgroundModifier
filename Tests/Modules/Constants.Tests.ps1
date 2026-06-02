$modulePath = Join-Path $PSScriptRoot "..\..\Modules\Constants.psm1"
Import-Module $modulePath -Force

Describe "Constants" {
    It "defines expected global roots" {
        $Global:RootPath | Should Be "C:\BootOpsHub"
        $Global:LogRoot | Should Be "C:\BootOpsHub\logs"
        $Global:AssetsRoot | Should Be "C:\BootOpsHub\assets"
        $Global:RenderRoot | Should Be "C:\BootOpsHub\rendered"
        $Global:SystemRoot | Should Be "C:\BootOpsHub\system"
    }

    It "sets RepoRoot to parent of Modules folder" {
        Test-Path -LiteralPath $Global:RepoRoot | Should Be $true
    }
}
