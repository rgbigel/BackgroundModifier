# =================================================================================================
#  Module:      RenderTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
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
        [string[]]$Lines = @(),
        [object[]]$TableRows = @(),
        [hashtable]$TableFormat = @{},
        [hashtable]$TextColor = @{}
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

        $panelW = [Math]::Min($base.Width - 80, 900)
        $panelX = $base.Width - $panelW - 40
        $panelY = 40
        $panelH = [Math]::Min($base.Height - 80, 1040)

        $panelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160, 0, 0, 0))
        $resolvedTextColor = [System.Drawing.Color]::White
        if ($TextColor.ContainsKey("R") -and $TextColor.ContainsKey("G") -and $TextColor.ContainsKey("B")) {
            $resolvedTextColor = [System.Drawing.Color]::FromArgb(
                [Math]::Max(0, [Math]::Min(255, [int]$TextColor["R"])),
                [Math]::Max(0, [Math]::Min(255, [int]$TextColor["G"])),
                [Math]::Max(0, [Math]::Min(255, [int]$TextColor["B"]))
            )
        }
        $textBrush = New-Object System.Drawing.SolidBrush ($resolvedTextColor)
        $titleFont = New-Object System.Drawing.Font("Segoe UI", 14.2, [System.Drawing.FontStyle]::Bold)
        $bodyFont = New-Object System.Drawing.Font("Consolas", 14.2, [System.Drawing.FontStyle]::Regular)

        try {
            $renderLines = @()
            $resolvedKeyWidth = 0
            $resolvedValueWidth = 0

            if ($TableRows -and $TableRows.Count -gt 0) {
                $resolvedKeyWidth = ($TableRows | ForEach-Object { [string]$_.Key } | Measure-Object -Maximum Length).Maximum
                $resolvedValueWidth = ($TableRows | ForEach-Object { [string]$_.Value } | Measure-Object -Maximum Length).Maximum

                if ($TableFormat.ContainsKey("KeyWidth")) {
                    $resolvedKeyWidth = [Math]::Max($resolvedKeyWidth, [int]$TableFormat["KeyWidth"])
                }
                if ($TableFormat.ContainsKey("ValueWidth")) {
                    $resolvedValueWidth = [Math]::Max($resolvedValueWidth, [int]$TableFormat["ValueWidth"])
                }

                $resolvedKeyWidth = [Math]::Max($resolvedKeyWidth, 5)
                $resolvedValueWidth = [Math]::Max($resolvedValueWidth, 5)

                $renderLines += (("Field").PadRight($resolvedKeyWidth) + " | " + ("Value").PadRight($resolvedValueWidth))
                $renderLines += (("-" * $resolvedKeyWidth) + "-+-" + ("-" * $resolvedValueWidth))

                foreach ($row in $TableRows) {
                    $rowKey = [string]$row.Key
                    $rowValue = [string]$row.Value
                    if ([string]::IsNullOrEmpty($rowValue)) {
                        $rowValue = ""
                    }

                    $keyPart = $rowKey.PadRight($resolvedKeyWidth)
                    $valuePart = if ($rowValue.Length -lt $resolvedValueWidth) { $rowValue.PadRight($resolvedValueWidth) } else { $rowValue }
                    $renderLines += ($keyPart + " | " + $valuePart)
                }
            }
            else {
                $renderLines = $Lines
            }

            $leftPadding = 24
            $rightPadding = 38
            $contentWidth = [double]$gfx.MeasureString($Title, $titleFont).Width
            foreach ($line in $renderLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $lineWidth = [double]$gfx.MeasureString([string]$line, $bodyFont).Width
                if ($lineWidth -gt $contentWidth) {
                    $contentWidth = $lineWidth
                }
            }

            $desiredPanelW = [int][Math]::Ceiling($contentWidth + $leftPadding + $rightPadding)
            $panelW = [Math]::Max(320, [Math]::Min($base.Width - 80, $desiredPanelW))
            $panelX = $base.Width - $panelW - 40

            $gfx.FillRectangle($panelBrush, $panelX, $panelY, $panelW, $panelH)
            $gfx.DrawString($Title, $titleFont, $textBrush, ($panelX + $leftPadding), ($panelY + 20))

            $maxWidth = $panelW - 48
            $lineHeight = [int][Math]::Ceiling($bodyFont.GetHeight($gfx) + 8)
            $expandedLines = New-Object System.Collections.Generic.List[string]

            foreach ($line in $renderLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                $current = [string]$line
                if ($gfx.MeasureString($current, $bodyFont).Width -le $maxWidth) {
                    $expandedLines.Add($current) | Out-Null
                    continue
                }

                $delimiter = " | "
                $dix = $current.IndexOf($delimiter)
                if ($dix -lt 0) {
                    $expandedLines.Add($current) | Out-Null
                    continue
                }

                $keyPrefix = $current.Substring(0, $dix + $delimiter.Length)
                $contPrefix = ("".PadRight($dix + $delimiter.Length + 6))
                $remaining = $current.Substring($dix + $delimiter.Length).TrimEnd()
                $isFirst = $true

                while ($remaining.Length -gt 0) {
                    $prefix = if ($isFirst) { $keyPrefix } else { $contPrefix }
                    $fitLen = $remaining.Length

                    while ($fitLen -gt 1 -and ($gfx.MeasureString($prefix + $remaining.Substring(0, $fitLen), $bodyFont).Width -gt $maxWidth)) {
                        $fitLen -= 1
                    }

                    if ($fitLen -lt $remaining.Length) {
                        $candidate = $remaining.Substring(0, $fitLen)
                        $splitPosSlash = $candidate.LastIndexOf('\')
                        if ($splitPosSlash -ge 1) {
                            $fitLen = $splitPosSlash
                        }
                        else {
                            $splitPosSpace = $candidate.LastIndexOf(' ')
                            if ($splitPosSpace -ge 1) {
                                $fitLen = $splitPosSpace
                            }
                        }
                    }

                    if ($fitLen -lt 1) { $fitLen = 1 }

                    $chunk = $remaining.Substring(0, $fitLen).TrimEnd()
                    $expandedLines.Add($prefix + $chunk) | Out-Null
                    $remaining = $remaining.Substring($fitLen).TrimStart()
                    $isFirst = $false
                }
            }

            $y = $panelY + 130
            foreach ($line in $expandedLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                $gfx.DrawString([string]$line, $bodyFont, $textBrush, ($panelX + 24), $y)
                $y += $lineHeight
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

        if ($TableRows -and $TableRows.Count -gt 0) {
            return [PSCustomObject]@{
                KeyWidth = $resolvedKeyWidth
                ValueWidth = $resolvedValueWidth
            }
        }

        return [PSCustomObject]@{
            KeyWidth = 0
            ValueWidth = 0
        }
    }
    finally {
        $gfx.Dispose()
        $bmp.Dispose()
        $base.Dispose()
    }
}

Export-ModuleMember -Function *


