$repoRoot = Join-Path $PSScriptRoot "..\.."
$installRoot = Join-Path $repoRoot "Install"

Describe "Cleanup script execution" {
    It "runs cleanup tools when module path exists" {
        $scriptPath = Join-Path $installRoot "Cleanup.ps1"

        Mock Test-Path {
            if ($LiteralPath -match "Modules$") { return $true }
            if ($LiteralPath -match "CleanupTools\.psm1$") { return $true }
            return $false
        }
        Mock Test-HelpRequested { $false }
        Mock Import-Module {}
        Mock Clear-RenderFolder {}
        Mock Remove-OldLogs {}
        Mock Remove-TestLinks {}

        { & $scriptPath } | Should Not Throw

        Assert-MockCalled Import-Module -Exactly 2 -Scope It
        Assert-MockCalled Clear-RenderFolder -Exactly 1 -Scope It
        Assert-MockCalled Remove-OldLogs -Exactly 1 -Scope It
        Assert-MockCalled Remove-TestLinks -Exactly 0 -Scope It
    }

    It "removes test links only when trace mode is enabled" {
        $scriptPath = Join-Path $installRoot "Cleanup.ps1"

        Mock Test-Path {
            if ($LiteralPath -match "Modules$") { return $true }
            if ($LiteralPath -match "CleanupTools\.psm1$") { return $true }
            if ($LiteralPath -match "D:\\OneDrive\\cmd") { return $true }
            return $false
        }
        Mock Test-HelpRequested { $false }
        Mock Import-Module {}
        Mock Clear-RenderFolder {}
        Mock Remove-OldLogs {}
        Mock Remove-TestLinks {}

        { & $scriptPath -t } | Should Not Throw

        Assert-MockCalled Remove-TestLinks -Exactly 1 -Scope It
    }

    It "uses full log removal when -f is supplied" {
        $scriptPath = Join-Path $installRoot "Cleanup.ps1"

        Mock Test-Path {
            if ($LiteralPath -match "Modules$") { return $true }
            if ($LiteralPath -match "CleanupTools\.psm1$") { return $true }
            return $false
        }
        Mock Test-HelpRequested { $false }
        Mock Import-Module {}
        Mock Clear-RenderFolder {}
        Mock Remove-OldLogs {}
        Mock Remove-TestLinks {}

        { & $scriptPath -f } | Should Not Throw

        Assert-MockCalled Remove-OldLogs -Exactly 1 -Scope It -ParameterFilter { $Full -eq $true }
    }

    It "returns exit code 1 when module root is missing" {
        $tempRepo = Join-Path $env:TEMP ("BM_CleanupRepo_" + [guid]::NewGuid().ToString("N"))
        $tempInstall = Join-Path $tempRepo "Install"
        $cleanupCopy = Join-Path $tempInstall "Cleanup.ps1"
        $sourceCleanup = Join-Path $installRoot "Cleanup.ps1"

        try {
            New-Item -ItemType Directory -Path $tempInstall -Force | Out-Null
            Copy-Item -Path $sourceCleanup -Destination $cleanupCopy -Force

            & powershell -NoProfile -ExecutionPolicy Bypass -File $cleanupCopy
            $LASTEXITCODE | Should Be 1
        }
        finally {
            if (Test-Path -LiteralPath $tempRepo) {
                Remove-Item -LiteralPath $tempRepo -Recurse -Force
            }
        }
    }

    It "returns exit code 1 when CleanupTools module is missing" {
        $tempRepo = Join-Path $env:TEMP ("BM_CleanupRepo_" + [guid]::NewGuid().ToString("N"))
        $tempInstall = Join-Path $tempRepo "Install"
        $tempModules = Join-Path $tempRepo "Modules"
        $cleanupCopy = Join-Path $tempInstall "Cleanup.ps1"
        $sourceCleanup = Join-Path $installRoot "Cleanup.ps1"

        try {
            New-Item -ItemType Directory -Path $tempInstall -Force | Out-Null
            New-Item -ItemType Directory -Path $tempModules -Force | Out-Null
            Copy-Item -Path $sourceCleanup -Destination $cleanupCopy -Force

            & powershell -NoProfile -ExecutionPolicy Bypass -File $cleanupCopy
            $LASTEXITCODE | Should Be 1
        }
        finally {
            if (Test-Path -LiteralPath $tempRepo) {
                Remove-Item -LiteralPath $tempRepo -Recurse -Force
            }
        }
    }
}
