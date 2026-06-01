# =================================================================================================
#  Module:      RenderTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     5.000
#  Purpose:     Shared helpers for image rendering, composition, and deterministic output handling.
#  Changelog:
#      5.000  --------  Initial module creation for Consolidated Architecture (text rendering)
# =================================================================================================

function Merge-Image {
    param(
        [string]$BaseImage,
        [string]$OverlayImage,
        [string]$OutputPath
    )

    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path $BaseImage)) {
        Write-Host "[ERROR] Base image missing: $BaseImage"
        exit 1
    }

    if (-not (Test-Path $OverlayImage)) {
        Write-Host "[ERROR] Overlay image missing: $OverlayImage"
        exit 1
    }

    $base   = [System.Drawing.Image]::FromFile($BaseImage)
    $overlay = [System.Drawing.Image]::FromFile($OverlayImage)

    $bmp = New-Object System.Drawing.Bitmap $base.Width, $base.Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)

    $gfx.DrawImage($base, 0, 0, $base.Width, $base.Height)
    $gfx.DrawImage($overlay, 0, 0, $overlay.Width, $overlay.Height)

    $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)

    $gfx.Dispose()
    $bmp.Dispose()
    $base.Dispose()
    $overlay.Dispose()

    Write-Host "[OK] Rendered -> $OutputPath"
}

function Render-TextOverlay {
    param(
        [string]$BaseImage,
        [string]$OutputPath,
        [string]$Title = "BackgroundModifier",
        [string[]]$Lines = @()
    )

    Add-Type -AssemblyName System.Drawing

    if (-not (Test-Path -LiteralPath $BaseImage)) {
        throw "Base image missing: $BaseImage"
    }

    $base = [System.Drawing.Image]::FromFile($BaseImage)
    $bmp = New-Object System.Drawing.Bitmap $base.Width, $base.Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)

    try {
        $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $gfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $gfx.DrawImage($base, 0, 0, $base.Width, $base.Height)

        $panelX = 40
        $panelY = 40
        $panelW = [Math]::Min($base.Width - 80, 1300)
        $panelH = [Math]::Min($base.Height - 80, 420)

        $panelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(140, 0, 0, 0))
        $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $titleFont = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Bold)
        $bodyFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Regular)

        try {
            $gfx.FillRectangle($panelBrush, $panelX, $panelY, $panelW, $panelH)
            $gfx.DrawString($Title, $titleFont, $textBrush, ($panelX + 24), ($panelY + 20))

            $y = $panelY + 80
            foreach ($line in $Lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $gfx.DrawString($line, $bodyFont, $textBrush, ($panelX + 24), $y)
                $y += 34
                if ($y -gt ($panelY + $panelH - 24)) { break }
            }
        }
        finally {
            $titleFont.Dispose()
            $bodyFont.Dispose()
            $panelBrush.Dispose()
            $textBrush.Dispose()
        }

        $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        Write-Host "[OK] Rendered text overlay -> $OutputPath"
    }
    finally {
        $gfx.Dispose()
        $bmp.Dispose()
        $base.Dispose()
    }
}

Export-ModuleMember -Function *
