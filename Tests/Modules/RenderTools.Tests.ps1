$modulePath = Join-Path $PSScriptRoot "..\..\Modules\RenderTools.psm1"
Import-Module $modulePath -Force

Describe "RenderTools" {
    It "exports expected functions" {
        Get-Command Merge-Image -ErrorAction Stop | Should Not BeNullOrEmpty
        Get-Command Render-TextOverlay -ErrorAction Stop | Should Not BeNullOrEmpty
    }

    It "renders text overlay to output file" {
        $root = Join-Path $env:TEMP ("BM_RenderTools_" + [guid]::NewGuid().ToString("N"))
        $base = Join-Path $root "base.jpg"
        $out = Join-Path $root "out.jpg"

        try {
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            Add-Type -AssemblyName System.Drawing
            $bmp = New-Object System.Drawing.Bitmap 300, 160
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $g.Clear([System.Drawing.Color]::DarkSlateBlue)
                }
                finally { $g.Dispose() }
                $bmp.Save($base, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            }
            finally { $bmp.Dispose() }

            Render-TextOverlay -BaseImage $base -OutputPath $out -Title "Unit" -Lines @("A","B")

            Test-Path -LiteralPath $out | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It "throws when base image is missing" {
        { Render-TextOverlay -BaseImage "Z:\does-not-exist.jpg" -OutputPath "$env:TEMP\x.jpg" } | Should Throw
    }
}
