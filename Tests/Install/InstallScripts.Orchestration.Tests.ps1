$repoRoot = Join-Path $PSScriptRoot "..\.."
$installRoot = Join-Path $repoRoot "Install"

Describe "Install script orchestration contracts" {
    It "Setup invokes verifier with explicit roots and IncludeTestLinks" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '& \$verifierScript -t:\$t -d:\$d -CmdRoot \$CmdRoot -RuntimeRoot \$RuntimeRoot -IncludeTestLinks:\$IncludeTestLinks'
    }

    It "Setup defines expected operational cmd links" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $expected = @(
            'BackgroundModifier-AdminShell.ps1',
            'BackgroundModifier-Setup.ps1',
            'BackgroundModifier-Verify.ps1',
            'BackgroundModifier-Cleanup.ps1',
            'BackgroundModifier-Disable.ps1',
            'BackgroundModifier-Enable.ps1',
            'BackgroundModifier-Uninstall.ps1'
        )

        foreach ($entry in $expected) {
            $pattern = [regex]::Escape($entry)
            $text | Should Match $pattern
        }
    }

    It "Setup self-elevates when started from a non-admin shell" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\bTest-Admin\b'
        $text | Should Match '\bInvoke-SelfElevated\b'
        $text | Should Match 'Setup requires elevation\. Relaunching via UAC prompt'
    }

    It "Setup help path is checked before elevation" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\bTest-HelpRequested\b'
        $text | Should Match '\bShow-InstallerUsage\b'
        $text | Should Match '\bWait-ForInstallerExit\b'
        $text | Should Match 'This script self-relaunches with UAC when elevation is required'
    }

    It "AdminShell launcher uses InstallerTools to open an elevated PowerShell session" {
        $path = Join-Path $installRoot "AdminShell.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match 'InstallerTools\.psm1'
        $text | Should Match 'Start-ElevatedPowerShellSession'
        $text | Should Match 'BackgroundModifier AdminShell\.ps1'
    }

    It "Setup defines expected test cmd links" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $expected = @(
            'BackgroundModifier-BootIdentityTest.ps1',
            'BackgroundModifier-RenderTest.ps1',
            'BackgroundModifier-ApplyTest.ps1',
            'BackgroundModifier-LogonStage.ps1'
        )

        foreach ($entry in $expected) {
            $pattern = [regex]::Escape($entry)
            $text | Should Match $pattern
        }
    }

    It "Setup provisions scheduled automation tasks through SchedulerTools" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match 'SchedulerTools\.psm1'
        $text | Should Match 'Register-BackgroundTask'
        $text | Should Match 'BackgroundModifier-BootIdentity'
        $text | Should Match 'BackgroundModifier-Autorun'
        $text | Should Match 'TriggerType Startup'
        $text | Should Match 'TriggerType LogOn'
    }

    It "Verifier checks operational scheduled tasks" {
        $path = Join-Path $installRoot "BackgroundInstallationVerifier.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\bGet-ScheduledTask\b'
        $text | Should Match 'BackgroundModifier-AdminShell\.ps1'
        $text | Should Match 'BackgroundModifier-BootIdentity'
        $text | Should Match 'BackgroundModifier-Autorun'
    }

    It "Help text is available on non-elevating scripts" {
        $scripts = @(
            'BackgroundInstallationVerifier.ps1',
            'AdminShell.ps1',
            'Cleanup.ps1'
        )

        foreach ($script in $scripts) {
            $path = Join-Path $installRoot $script
            $text = Get-Content -LiteralPath $path -Raw
            $text | Should Match '\bTest-HelpRequested\b'
            $text | Should Match '\bShow-InstallerUsage\b'
        }
    }

    It "Setup and verifier accept short-form parameter aliases" {
        $setupText = Get-Content -LiteralPath (Join-Path $installRoot 'Setup.ps1') -Raw
        $verifierText = Get-Content -LiteralPath (Join-Path $installRoot 'BackgroundInstallationVerifier.ps1') -Raw
        $uninstallText = Get-Content -LiteralPath (Join-Path $installRoot 'Uninstall.ps1') -Raw

        $setupText | Should Match '\[Alias\(\x27c\x27\)\]'
        $setupText | Should Match '\[Alias\(\x27r\x27\)\]'
        $setupText | Should Match '\[Alias\(\x27i\x27\)\]'
        $setupText | Should Match '\$CmdRoot'
        $setupText | Should Match '\$RuntimeRoot'
        $setupText | Should Match '\$IncludeTestLinks'

        $verifierText | Should Match '\[Alias\(\x27c\x27\)\]'
        $verifierText | Should Match '\[Alias\(\x27r\x27\)\]'
        $verifierText | Should Match '\[Alias\(\x27i\x27\)\]'
        $verifierText | Should Match '\$CmdRoot'
        $verifierText | Should Match '\$RuntimeRoot'
        $verifierText | Should Match '\$IncludeTestLinks'

        $uninstallText | Should Match '\[Alias\(\x27c\x27\)\]'
        $uninstallText | Should Match '\[Alias\(\x27r\x27\)\]'
        $uninstallText | Should Match '\$CmdRoot'
        $uninstallText | Should Match '\$RuntimeRoot'
    }

    It "Disable uses Require-Admin and Disable-ScheduledTask" {
        $path = Join-Path $installRoot "Disable.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\bRequire-Admin\b'
        $text | Should Match '\bDisable-ScheduledTask\b'
    }

    It "Enable uses Require-Admin and Enable-ScheduledTask" {
        $path = Join-Path $installRoot "Enable.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\bRequire-Admin\b'
        $text | Should Match '\bEnable-ScheduledTask\b'
    }

    It "Enable and Disable target expected task names" {
        $enableText = Get-Content -LiteralPath (Join-Path $installRoot "Enable.ps1") -Raw
        $disableText = Get-Content -LiteralPath (Join-Path $installRoot "Disable.ps1") -Raw

        $expectedTasks = @(
            'BackgroundModifier-BootIdentity',
            'BackgroundModifier-Autorun'
        )

        foreach ($task in $expectedTasks) {
            $pattern = [regex]::Escape($task)
            $enableText | Should Match $pattern
            $disableText | Should Match $pattern
        }
    }

    It "Uninstall includes repository safety guard and required teardown calls" {
        $path = Join-Path $installRoot "Uninstall.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match 'Refusing uninstall: runtime root resolves inside repository path'
        $text | Should Match '\bUnregister-ScheduledTask\b'
        $text | Should Match '\bRemove-NoBlur\b'
    }

    It "Uninstall cmd cleanup list includes operational and test entry points" {
        $path = Join-Path $installRoot "Uninstall.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $expected = @(
            'BackgroundModifier-Setup.ps1',
            'BackgroundModifier-Verify.ps1',
            'BackgroundModifier-Cleanup.ps1',
            'BackgroundModifier-Disable.ps1',
            'BackgroundModifier-Enable.ps1',
            'BackgroundModifier-Uninstall.ps1',
            'BackgroundModifier-BootIdentityTest.ps1',
            'BackgroundModifier-RenderTest.ps1',
            'BackgroundModifier-ApplyTest.ps1',
            'BackgroundModifier-LogonStage.ps1'
        )

        foreach ($entry in $expected) {
            $pattern = [regex]::Escape($entry)
            $text | Should Match $pattern
        }
    }
}
