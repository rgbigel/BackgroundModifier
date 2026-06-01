$modulePath = Join-Path $PSScriptRoot "..\..\Modules\BackgroundNoBlurReg.psm1"
Import-Module $modulePath -Force

Describe "BackgroundNoBlurReg" {
    It "exports expected functions" {
        Get-Command Set-NoBlur -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Remove-NoBlur -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "Set-NoBlur creates key when missing and sets value" {
        Mock Test-Path { return $false } -ModuleName BackgroundNoBlurReg
        Mock New-Item { return $null } -ModuleName BackgroundNoBlurReg
        Mock Set-ItemProperty { return $null } -ModuleName BackgroundNoBlurReg

        Set-NoBlur

        Assert-MockCalled Test-Path -Times 1 -ModuleName BackgroundNoBlurReg
        Assert-MockCalled New-Item -Times 1 -ModuleName BackgroundNoBlurReg
        Assert-MockCalled Set-ItemProperty -Times 1 -ModuleName BackgroundNoBlurReg
    }

    It "Remove-NoBlur removes property when key exists" {
        Mock Test-Path { return $true } -ModuleName BackgroundNoBlurReg
        Mock Remove-ItemProperty { return $null } -ModuleName BackgroundNoBlurReg

        Remove-NoBlur

        Assert-MockCalled Test-Path -Times 1 -ModuleName BackgroundNoBlurReg
        Assert-MockCalled Remove-ItemProperty -Times 1 -ModuleName BackgroundNoBlurReg
    }
}
