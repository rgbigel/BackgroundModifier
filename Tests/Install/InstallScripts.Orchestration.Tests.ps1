$repoRoot = Join-Path $PSScriptRoot "..\.."
$installRoot = Join-Path $repoRoot "Install"

Describe "Install script orchestration contracts" {
    It "Setup invokes verifier with explicit roots and t-only mode contract" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '& \$verifierScript -t:\$t -CmdRoot \$CmdRoot -RuntimeRoot \$RuntimeRoot'
    }

    It "Setup defines expected operational cmd links" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $expected = @(
            'BackgroundModifier_Install.cmd',
            'BackgroundModifier.cmd'
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

    It "AdminShell runs as menu-driven elevated action router" {
        $path = Join-Path $installRoot "AdminShell.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match 'InstallerTools\.psm1'
        $text | Should Match 'if \(-not \(Test-Admin\)\)'
        $text | Should Match 'Invoke-SelfElevated'
        $text | Should Match 'BackgroundModifier Action Menu'
        $text | Should Match 'Select action'
        $text | Should Match 'BackgroundModifier AdminShell\.ps1'
        $text | Should Match 'BootIdentity\.ps1'
        $text | Should Match 'BackgroundRenderer\.ps1'
        $text | Should Match 'BackgroundSetter\.ps1'
        $text | Should Match 'BackgroundApply\.ps1'
        $text | Should Match '"B"\s*=\s*@\{\s*Name\s*=\s*"BootIdentity"'
        $text | Should Match '"R"\s*=\s*@\{\s*Name\s*=\s*"Renderer"'
        $text | Should Match '"A"\s*=\s*@\{\s*Name\s*=\s*"Setter"'
        $text | Should Match '"L"\s*=\s*@\{\s*Name\s*=\s*"Apply"'
        $text | Should Match '\$showApplyAction\s*=\s*\$false'
        $text | Should Match 'Apply is hidden until Setter reports a problem'
        $text | Should Match 'Setter completed\. Running Apply automatically'
    }

    It "Setup keeps test-mode behavior without creating dedicated cmd test links" {
        $path = Join-Path $installRoot "Setup.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\[switch\]\$t'
        $text | Should Match 'BackgroundModifier\.cmd'
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
        $path = Join-Path $installRoot "Verifyer.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $text | Should Match '\bGet-ScheduledTask\b'
        $text | Should Match 'BackgroundModifier_Install\.cmd'
        $text | Should Match 'BackgroundModifier\.cmd'
        $text | Should Match 'BackgroundModifier-BootIdentity'
        $text | Should Match 'BackgroundModifier-Autorun'
    }

    It "Help text is available on non-elevating scripts" {
        $scripts = @(
            'Verifyer.ps1',
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
        $verifierText = Get-Content -LiteralPath (Join-Path $installRoot 'Verifyer.ps1') -Raw
        $uninstallText = Get-Content -LiteralPath (Join-Path $installRoot 'Uninstall.ps1') -Raw

        $setupText | Should Match '\[Alias\(\x27c\x27\)\]'
        $setupText | Should Match '\[Alias\(\x27r\x27\)\]'
        $setupText | Should Match '\$CmdRoot'
        $setupText | Should Match '\$RuntimeRoot'

        $verifierText | Should Match '\[Alias\(\x27c\x27\)\]'
        $verifierText | Should Match '\[Alias\(\x27r\x27\)\]'
        $verifierText | Should Match '\$CmdRoot'
        $verifierText | Should Match '\$RuntimeRoot'

        $uninstallText | Should Match '\[Alias\(\x27c\x27\)\]'
        $uninstallText | Should Match '\[Alias\(\x27r\x27\)\]'
        $uninstallText | Should Match '\$CmdRoot'
        $uninstallText | Should Match '\$RuntimeRoot'
    }

    It "Install scripts expose t as the only mode switch" {
        $setupText = Get-Content -LiteralPath (Join-Path $installRoot 'Setup.ps1') -Raw
        $verifierText = Get-Content -LiteralPath (Join-Path $installRoot 'Verifyer.ps1') -Raw
        $adminShellText = Get-Content -LiteralPath (Join-Path $installRoot 'AdminShell.ps1') -Raw

        $setupText | Should Match '\[switch\]\$t'
        $verifierText | Should Match '\[switch\]\$t'
        $adminShellText | Should Match '\[switch\]\$t'

        $setupText | Should Not Match '\[switch\]\$d'
        $verifierText | Should Not Match '\[switch\]\$d'
        $setupText | Should Not Match 'IncludeTestLinks'
        $verifierText | Should Not Match 'IncludeTestLinks'
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

    It "Uninstall cmd cleanup list includes only current operational entry points" {
        $path = Join-Path $installRoot "Uninstall.ps1"
        $text = Get-Content -LiteralPath $path -Raw

        $expected = @(
            'BackgroundModifier_Install.cmd',
            'BackgroundModifier.cmd'
        )

        foreach ($entry in $expected) {
            $pattern = [regex]::Escape($entry)
            $text | Should Match $pattern
        }
    }
}
