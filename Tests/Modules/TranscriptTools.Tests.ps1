$modulePath = Join-Path $PSScriptRoot "..\..\Modules\TranscriptTools.psm1"
Import-Module $modulePath -Force

Describe "TranscriptTools" {
    It "exports expected functions" {
        Get-Command Get-TranscriptPath -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Start-ToolTranscript -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Stop-ToolTranscript -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "returns transcript path with expected timestamp format" {
        $tempRoot = Join-Path $env:TEMP ("BM_Test_" + [guid]::NewGuid().ToString("N"))
        try {
            $path = Get-TranscriptPath -LogRoot $tempRoot -Prefix "Unit"
            $path | Should Match "Unit_\d{8}_\d{6}\.log$"
            (Split-Path -Parent $path) | Should Match "transcripts$"
            Test-Path -LiteralPath (Split-Path -Parent $path) | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
