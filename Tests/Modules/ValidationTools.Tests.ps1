$modulePath = Join-Path $PSScriptRoot "..\..\Modules\ValidationTools.psm1"
Import-Module $modulePath -Force

Describe "ValidationTools" {
    It "exports expected functions" {
        Get-Command Test-PathRequired -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Test-StringRequired -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Test-NumberRange -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "validates required path" {
        $root = Join-Path $env:TEMP ("BM_ValidationTools_" + [guid]::NewGuid().ToString("N"))
        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            (Test-PathRequired -Path $root) | Should Be $true
            (Test-PathRequired -Path (Join-Path $root "missing")) | Should Be $false
            (Test-PathRequired -Path "") | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "validates required string" {
        (Test-StringRequired -Value "abc" -Name "Name") | Should Be $true
        (Test-StringRequired -Value "" -Name "Name") | Should Be $false
    }

    It "validates number range" {
        (Test-NumberRange -Value 5 -Min 1 -Max 10 -Name "N") | Should Be $true
        (Test-NumberRange -Value 99 -Min 1 -Max 10 -Name "N") | Should Be $false
    }
}
