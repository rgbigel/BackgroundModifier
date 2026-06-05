$modulePath = Join-Path $PSScriptRoot "..\..\Modules\CleanupTools.psm1"
Import-Module $modulePath -Force

Describe "CleanupTools" {
    It "exports expected functions" {
        Get-Command Remove-OldLogs -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Clear-RenderFolder -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Remove-TestLinks -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "removes only old logs older than threshold" {
        $root = Join-Path $env:TEMP ("BM_CleanupTools_" + [guid]::NewGuid().ToString("N"))
        $oldLog = Join-Path $root "old.log"
        $newLog = Join-Path $root "new.log"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $oldLog -Value "old" -Encoding UTF8
            Set-Content -Path $newLog -Value "new" -Encoding UTF8

            (Get-Item -LiteralPath $oldLog).LastWriteTime = (Get-Date).AddDays(-10)
            (Get-Item -LiteralPath $newLog).LastWriteTime = (Get-Date)

            Remove-OldLogs -LogRoot $root -Days 7

            Test-Path -LiteralPath $oldLog | Should Be $false
            Test-Path -LiteralPath $newLog | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "removes all logs when full mode is requested" {
        $root = Join-Path $env:TEMP ("BM_CleanupToolsFull_" + [guid]::NewGuid().ToString("N"))
        $oldLog = Join-Path $root "old.log"
        $newLog = Join-Path $root "new.log"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $oldLog -Value "old" -Encoding UTF8
            Set-Content -Path $newLog -Value "new" -Encoding UTF8

            Remove-OldLogs -LogRoot $root -Full

            Test-Path -LiteralPath $oldLog | Should Be $false
            Test-Path -LiteralPath $newLog | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "clears files from render folder" {
        $root = Join-Path $env:TEMP ("BM_Render_" + [guid]::NewGuid().ToString("N"))
        $file1 = Join-Path $root "a.jpg"
        $file2 = Join-Path $root "b.jpg"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $file1 -Value "a" -Encoding UTF8
            Set-Content -Path $file2 -Value "b" -Encoding UTF8

            Clear-RenderFolder -RenderRoot $root

            (Get-ChildItem -LiteralPath $root -File | Measure-Object).Count | Should Be 0
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "removes test links from cmd root" {
        $root = Join-Path $env:TEMP ("BM_CmdLinks_" + [guid]::NewGuid().ToString("N"))
        $entry = Join-Path $root "BackgroundModifier-RenderTest.ps1"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Set-Content -Path $entry -Value "x" -Encoding UTF8

            Remove-TestLinks -CmdRoot $root -TestEntries @("BackgroundModifier-RenderTest.ps1")

            Test-Path -LiteralPath $entry | Should Be $false
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }
}
