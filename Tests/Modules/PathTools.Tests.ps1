$modulePath = Join-Path $PSScriptRoot "..\..\Modules\PathTools.psm1"
Import-Module $modulePath -Force

Describe "PathTools" {
    It "joins base and child paths" {
        $joined = Join-Safe -Base "C:\Temp" -Child "Child"
        $joined | Should Match "C:\\Temp\\Child$"
    }

    It "ensures directory exists and returns input path" {
        $testPath = Join-Path $env:TEMP ("BM_PathTest_" + [guid]::NewGuid().ToString("N"))
        try {
            $result = Ensure-Path -Path $testPath
            $result | Should Be $testPath
            Test-Path -LiteralPath $testPath | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $testPath) {
                Remove-Item -LiteralPath $testPath -Recurse -Force
            }
        }
    }
}
