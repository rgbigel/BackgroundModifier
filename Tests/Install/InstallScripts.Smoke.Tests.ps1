$repoRoot = Join-Path $PSScriptRoot "..\.."
$installRoot = Join-Path $repoRoot "Install"

Describe "Install script smoke tests" {
    $installScripts = @(
        "Setup.ps1",
        "BackgroundInstallationVerifier.ps1",
        "Cleanup.ps1",
        "Disable.ps1",
        "Enable.ps1",
        "Uninstall.ps1"
    )

    It "all install scripts parse without syntax errors" {
        foreach ($name in $installScripts) {
            $path = Join-Path $installRoot $name
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
            $errors.Count | Should Be 0
        }
    }

    It "Setup defines IncludeTestLinks parameter" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should Match '\[switch\]\$IncludeTestLinks'
    }

    It "Verifier defines IncludeTestLinks parameter" {
        $path = Join-Path $installRoot "BackgroundInstallationVerifier.ps1"
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should Match '\[switch\]\$IncludeTestLinks'
    }

    It "Uninstall contains runtime-root safety guard" {
        $path = Join-Path $installRoot "Uninstall.ps1"
        $text = Get-Content -LiteralPath $path -Raw
        $text | Should Match "Refusing uninstall: runtime root resolves inside repository path"
    }

    It "BackgroundInstallationVerifier succeeds on isolated temp runtime and cmd roots" {
        $runtimeRoot = Join-Path $env:TEMP ("BM_VerifierRuntime_" + [guid]::NewGuid().ToString("N"))
        $cmdRoot = Join-Path $env:TEMP ("BM_VerifierCmd_" + [guid]::NewGuid().ToString("N"))

        $folders = @(
            (Join-Path $runtimeRoot "logs"),
            (Join-Path $runtimeRoot "assets"),
            (Join-Path $runtimeRoot "rendered"),
            (Join-Path $runtimeRoot "system"),
            $cmdRoot
        )

        $cmdEntries = @(
            "BackgroundModifier-Setup.ps1",
            "BackgroundModifier-Verify.ps1",
            "BackgroundModifier-Cleanup.ps1",
            "BackgroundModifier-Disable.ps1",
            "BackgroundModifier-Enable.ps1",
            "BackgroundModifier-Uninstall.ps1"
        )

        try {
            foreach ($folder in $folders) {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
            }

            Set-Content -Path (Join-Path $runtimeRoot "assets\DesktopBase.jpg") -Value "x" -Encoding UTF8
            Set-Content -Path (Join-Path $runtimeRoot "assets\LogonBase.jpg") -Value "x" -Encoding UTF8

            foreach ($entry in $cmdEntries) {
                Set-Content -Path (Join-Path $cmdRoot $entry) -Value "x" -Encoding UTF8
            }

            $verifier = Join-Path $installRoot "BackgroundInstallationVerifier.ps1"
            { & $verifier -CmdRoot $cmdRoot -RuntimeRoot $runtimeRoot } | Should Not Throw
        }
        finally {
            if (Test-Path -LiteralPath $runtimeRoot) {
                Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
            }
            if (Test-Path -LiteralPath $cmdRoot) {
                Remove-Item -LiteralPath $cmdRoot -Recurse -Force
            }
        }
    }
}
