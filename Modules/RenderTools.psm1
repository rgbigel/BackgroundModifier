# =================================================================================================
#  Module:      RenderTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     8.0.0
#  Purpose:     Shared helpers for image rendering, composition, and deterministic output handling.
#
#  Caller Contract (Module-Caller State Update Responsibility):
#    This module renders images but does NOT modify state.json. Caller is responsible for:
#    - Capture returned image paths and metadata
#    - Update state.json with: render.lastRenderedAtUtc, render.lastSystemInfoHash (if changed)
#    - Update render tracking: renderedByPhase, renderedBySource, renderedBySourceVersion
#    - Write state atomically; failure breaks Phase 2 conditional logic
#    - This module does NOT touch state.json; caller owns state consistency
#
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

        # Calculate font size based on image WIDTH only (reference: 1920)
        $referenceWidth = 1920.0
        $referenceBaseFontSize = 14.2
        
        # Use width scaling factor, capped at 1.5x to avoid massive fonts for 4K/ultra-wide
        $widthScale = $base.Width / $referenceWidth
        $widthScale = [Math]::Min(1.5, $widthScale)  # Cap scaling at 1.5x max
        $avgScale = $widthScale  # For padding/margin calculations, use width scale
        $scaledFontSize = [Math]::Max(8.0, $referenceBaseFontSize * $widthScale)

        $maxPanelWidth = [int][Math]::Floor($base.Width * 0.45)
        $maxPanelWidth = [Math]::Min($maxPanelWidth, 680)
        $maxPanelWidth = [Math]::Max($maxPanelWidth, 360)

        $panelW = [Math]::Min($base.Width - 80, $maxPanelWidth)
        $panelX = $base.Width - $panelW - 40
        $panelY = 200
        $panelH = [Math]::Min($base.Height - 96, 880)

        $panelBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 20, 20, 20))
        $resolvedTextColor = [System.Drawing.Color]::FromArgb(255, 240, 200)
        if ($TextColor.ContainsKey("R") -and $TextColor.ContainsKey("G") -and $TextColor.ContainsKey("B")) {
            $resolvedTextColor = [System.Drawing.Color]::FromArgb(
                [Math]::Max(0, [Math]::Min(255, [int]$TextColor["R"])),
                [Math]::Max(0, [Math]::Min(255, [int]$TextColor["G"])),
                [Math]::Max(0, [Math]::Min(255, [int]$TextColor["B"]))
            )
        }
        $textBrush = New-Object System.Drawing.SolidBrush ($resolvedTextColor)
        $titleFont = New-Object System.Drawing.Font("Segoe UI", $scaledFontSize, [System.Drawing.FontStyle]::Bold)
        $bodyFont = New-Object System.Drawing.Font("Consolas", $scaledFontSize, [System.Drawing.FontStyle]::Regular)

        try {
            $renderLines = @()
            $resolvedKeyWidth = 0
            $resolvedValueWidth = 0
            $maxValueChars = 50

            if ($TableRows -and $TableRows.Count -gt 0) {
                $resolvedKeyWidth = ($TableRows | ForEach-Object { [string]$_.Key } | Measure-Object -Maximum Length).Maximum
                $resolvedValueWidth = ($TableRows | ForEach-Object { [string]$_.Value } | Measure-Object -Maximum Length).Maximum

                if ($TableFormat.ContainsKey("KeyWidth")) {
                    $resolvedKeyWidth = [Math]::Max($resolvedKeyWidth, [int]$TableFormat["KeyWidth"])
                }
                if ($TableFormat.ContainsKey("ValueWidth")) {
                    $resolvedValueWidth = [Math]::Max($resolvedValueWidth, [int]$TableFormat["ValueWidth"])
                }
                if ($TableFormat.ContainsKey("MaxValueChars")) {
                    $maxValueChars = [int]$TableFormat["MaxValueChars"]
                }

                $resolvedKeyWidth = [Math]::Max($resolvedKeyWidth, 5)
                $resolvedValueWidth = [Math]::Max($resolvedValueWidth, 5)
                
                # Calculate actual max characters per line based on measured text width
                # Use a test string of average characters (m is typically widest)
                $testChars = "MMMM"
                $testWidth = [double]$gfx.MeasureString($testChars, $bodyFont).Width
                $charWidth = $testWidth / 4
                $availableWidth = [double]($panelW - 24 - 24 - 8)  # Panel width minus left padding, right padding, separator
                $maxValueChars = [Math]::Max(16, [int]([Math]::Floor($availableWidth / $charWidth)))

                $renderLines += (("Field").PadRight($resolvedKeyWidth) + " | " + ("Value").PadRight($resolvedValueWidth))
                $renderLines += (("-" * $resolvedKeyWidth) + "-+-" + ("-" * $resolvedValueWidth))

                foreach ($row in $TableRows) {
                    $rowKey = [string]$row.Key
                    $rowValue = [string]$row.Value
                    if ([string]::IsNullOrEmpty($rowValue)) {
                        $rowValue = ""
                    }

                    if ($rowValue.Length -le $maxValueChars) {
                        $keyPart = $rowKey.PadRight($resolvedKeyWidth)
                        $valuePart = if ($rowValue.Length -lt $resolvedValueWidth) { $rowValue.PadRight($resolvedValueWidth) } else { $rowValue }
                        $renderLines += ($keyPart + " | " + $valuePart)
                    }
                    else {
                        $remaining = $rowValue
                        $isFirstChunk = $true

                        while ($remaining.Length -gt 0) {
                            # Start with calculated max chars, measure actual rendered width
                            $fitLen = [Math]::Min($remaining.Length, $maxValueChars)
                            $availableForValue = [double]($panelW - 24 - 24 - ([double]$gfx.MeasureString(($rowKey.PadRight($resolvedKeyWidth) + " | "), $bodyFont).Width))
                            
                            $candidate = $remaining.Substring(0, $fitLen)
                            $measuredWidth = [double]$gfx.MeasureString($candidate, $bodyFont).Width
                            
                            # Shrink to fit if measured width exceeds available space
                            while ($fitLen -gt 1 -and $measuredWidth -gt $availableForValue) {
                                $fitLen--
                                $candidate = $remaining.Substring(0, $fitLen)
                                $measuredWidth = [double]$gfx.MeasureString($candidate, $bodyFont).Width
                            }
                            
                            # Try to break at natural boundaries (comma, slash, space)
                            if ($fitLen -lt $remaining.Length) {
                                $splitPosComma = $candidate.LastIndexOf(',')
                                if ($splitPosComma -ge 1) {
                                    $fitLen = $splitPosComma + 1
                                }
                                else {
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
                            }

                            if ($fitLen -lt 1) { $fitLen = 1 }

                            $chunk = $remaining.Substring(0, $fitLen).Trim()
                            $displayKey = if ($isFirstChunk) { $rowKey } else { "" }
                            $keyPart = $displayKey.PadRight($resolvedKeyWidth)
                            $renderLines += ($keyPart + " | " + $chunk)

                            $remaining = $remaining.Substring($fitLen).TrimStart(' ', ',')
                            $isFirstChunk = $false
                        }
                    }
                }
            }
            else {
                $renderLines = $Lines
            }

            $leftPadding = [int][Math]::Ceiling(24 * $avgScale)
            $rightPadding = [int][Math]::Ceiling(38 * $avgScale)
            $contentWidth = [double]$gfx.MeasureString($Title, $titleFont).Width
            foreach ($line in $renderLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $lineWidth = [double]$gfx.MeasureString([string]$line, $bodyFont).Width
                if ($lineWidth -gt $contentWidth) {
                    $contentWidth = $lineWidth
                }
            }

            $desiredPanelW = [int][Math]::Ceiling($contentWidth + $leftPadding + $rightPadding)
            $panelW = [Math]::Max(320, [Math]::Min($maxPanelWidth, $desiredPanelW))
            $panelX = $base.Width - $panelW - 40

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

            $titleTopPadding = [int][Math]::Ceiling(20 * $avgScale)
            $textStartOffset = [int][Math]::Ceiling(86 * $avgScale)
            $bottomReserve = [int][Math]::Ceiling(28 * $avgScale)
            $desiredPanelH = $textStartOffset + ($expandedLines.Count * $lineHeight) + $bottomReserve
            $minPanelH = 180
            $maxPanelH = [Math]::Max($minPanelH, $base.Height - $panelY - 32)
            $panelH = [Math]::Min($maxPanelH, [Math]::Max($minPanelH, $desiredPanelH))

            $gfx.FillRectangle($panelBrush, $panelX, $panelY, $panelW, $panelH)
            $gfx.DrawString($Title, $titleFont, $textBrush, ($panelX + $leftPadding), ($panelY + $titleTopPadding))

            $y = $panelY + $textStartOffset
            $textLeftPadding = [int][Math]::Ceiling(24 * $avgScale)
            $textBottomMargin = [int][Math]::Ceiling(24 * $avgScale)
            
            foreach ($line in $expandedLines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                $gfx.DrawString([string]$line, $bodyFont, $textBrush, ($panelX + $textLeftPadding), $y)
                $y += $lineHeight
                if ($y -gt ($panelY + $panelH - $textBottomMargin)) { break }
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


