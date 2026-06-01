$modulePath = Join-Path $PSScriptRoot "..\..\Modules\Validation.psm1"
Import-Module $modulePath -Force

Describe "Validation" {
    It "exports expected functions" {
        Get-Command Test-FileExists -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Test-FolderExists -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Require-File -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Require-Folder -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "detects file and folder existence" {
        $root = Join-Path $env:TEMP ("BM_Validation_" + [guid]::NewGuid().ToString("N"))
        $file = Join-Path $root "x.txt"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $file -Value "x" -Encoding UTF8

            (Test-FileExists -Path $file) | Should Be $true
            (Test-FolderExists -Path $root) | Should Be $true
            (Test-FileExists -Path (Join-Path $root "missing.txt")) | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "passes Require-File and Require-Folder for existing paths" {
        $root = Join-Path $env:TEMP ("BM_ValidationReq_" + [guid]::NewGuid().ToString("N"))
        $file = Join-Path $root "ok.txt"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $file -Value "ok" -Encoding UTF8

            { Require-File -Path $file } | Should Not Throw
            { Require-Folder -Path $root } | Should Not Throw
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
