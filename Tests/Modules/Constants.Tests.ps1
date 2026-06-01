$modulePath = Join-Path $PSScriptRoot "..\..\Modules\Constants.psm1"
Import-Module $modulePath -Force

Describe "Constants" {
    It "defines expected global roots" {
        $Global:RootPath | Should Be "C:\BackgroundMotives"
        $Global:LogRoot | Should Be "C:\BackgroundMotives\logs"
        $Global:AssetsRoot | Should Be "C:\BackgroundMotives\assets"
        $Global:RenderRoot | Should Be "C:\BackgroundMotives\rendered"
        $Global:SystemRoot | Should Be "C:\BackgroundMotives\system"
    }

    It "sets RepoRoot to parent of Modules folder" {
        Test-Path -LiteralPath $Global:RepoRoot | Should Be $true
    }
}
