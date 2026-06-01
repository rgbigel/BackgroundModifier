$modulePath = Join-Path $PSScriptRoot "..\..\Modules\InstallerTools.psm1"
Import-Module $modulePath -Force

Describe "InstallerTools" {
    It "exports expected functions" {
        Get-Command Test-Admin -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Require-Admin -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Copy-Safe -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "copies file safely using Copy-Safe" {
        $root = Join-Path $env:TEMP ("BM_InstallerTools_" + [guid]::NewGuid().ToString("N"))
        $src = Join-Path $root "src.txt"
        $dst = Join-Path $root "dst.txt"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $src -Value "copy-test" -Encoding UTF8

            Copy-Safe -Source $src -Destination $dst

            Test-Path -LiteralPath $dst | Should Be $true
            (Get-Content -Path $dst -Raw) | Should Match "copy-test"
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "returns boolean from Test-Admin" {
        $value = Test-Admin
        ($value -is [bool]) | Should Be $true
    }
}
