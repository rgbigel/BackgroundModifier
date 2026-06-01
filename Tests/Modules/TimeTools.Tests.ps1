$modulePath = Join-Path $PSScriptRoot "..\..\Modules\TimeTools.psm1"
Import-Module $modulePath -Force

Describe "TimeTools" {
    It "returns run timestamp in yyyyMMdd_HHmmss format" {
        $stamp = Get-RunTimestamp
        $stamp | Should Match "^\d{8}_\d{6}$"
    }

    It "returns run id prefixed with RUN_" {
        $runId = Get-RunId
        $runId | Should Match "^RUN_\d{8}_\d{6}$"
    }

    It "returns short date in yyyy-MM-dd format" {
        $shortDate = Get-ShortDate
        $shortDate | Should Match "^\d{4}-\d{2}-\d{2}$"
    }

    It "measures scriptblock execution" {
        $result = Measure-Block -Action { Start-Sleep -Milliseconds 20 }
        $result | Should Not BeNullOrEmpty
        $result.Milliseconds -ge 0 | Should Be $true
        $result.Seconds -ge 0 | Should Be $true
    }
}
