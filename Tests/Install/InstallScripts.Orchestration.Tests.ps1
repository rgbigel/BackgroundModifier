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
