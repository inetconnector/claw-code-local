#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "assets"
}

function New-RoundedRectPath {
    param(
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2

    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Scale-Value {
    param(
        [int]$Base,
        [double]$Factor
    )

    return [single](([double]$Base) * $Factor)
}

function New-IconBitmap {
    param([int]$Size)

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $gradient = $null
    $path = $null
    $glowBrush = $null
    $chatPath = $null
    $chatBrush = $null
    $clawShadowPen = $null
    $clawPen = $null
    $accentBrush = $null
    $outlinePen = $null

    try {
        $backgroundRect = New-Object System.Drawing.RectangleF(0, 0, $Size, $Size)
        $gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $backgroundRect,
            [System.Drawing.Color]::FromArgb(255, 17, 24, 39),
            [System.Drawing.Color]::FromArgb(255, 41, 84, 160),
            45
        )
        $x08 = Scale-Value -Base $Size -Factor 0.08
        $y08 = Scale-Value -Base $Size -Factor 0.08
        $w84 = Scale-Value -Base $Size -Factor 0.84
        $h84 = Scale-Value -Base $Size -Factor 0.84
        $r18 = Scale-Value -Base $Size -Factor 0.18
        $path = New-RoundedRectPath -X $x08 -Y $y08 -Width $w84 -Height $h84 -Radius $r18
        $graphics.FillPath($gradient, $path)

        $glowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 97, 168, 255))
        $graphics.FillEllipse($glowBrush, (Scale-Value -Base $Size -Factor 0.48), (Scale-Value -Base $Size -Factor 0.10), (Scale-Value -Base $Size -Factor 0.28), (Scale-Value -Base $Size -Factor 0.28))

        $chatPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $chatPath.AddArc((Scale-Value -Base $Size -Factor 0.19), (Scale-Value -Base $Size -Factor 0.22), (Scale-Value -Base $Size -Factor 0.50), (Scale-Value -Base $Size -Factor 0.50), 180, 90)
        $chatPath.AddArc((Scale-Value -Base $Size -Factor 0.48), (Scale-Value -Base $Size -Factor 0.22), (Scale-Value -Base $Size -Factor 0.24), (Scale-Value -Base $Size -Factor 0.24), 270, 90)
        $chatPath.AddArc((Scale-Value -Base $Size -Factor 0.48), (Scale-Value -Base $Size -Factor 0.44), (Scale-Value -Base $Size -Factor 0.24), (Scale-Value -Base $Size -Factor 0.24), 0, 80)
        $chatPath.AddLine((Scale-Value -Base $Size -Factor 0.58), (Scale-Value -Base $Size -Factor 0.67), (Scale-Value -Base $Size -Factor 0.56), (Scale-Value -Base $Size -Factor 0.79))
        $chatPath.AddLine((Scale-Value -Base $Size -Factor 0.56), (Scale-Value -Base $Size -Factor 0.79), (Scale-Value -Base $Size -Factor 0.46), (Scale-Value -Base $Size -Factor 0.69))
        $chatPath.AddArc((Scale-Value -Base $Size -Factor 0.20), (Scale-Value -Base $Size -Factor 0.42), (Scale-Value -Base $Size -Factor 0.26), (Scale-Value -Base $Size -Factor 0.26), 90, 90)
        $chatPath.CloseFigure()

        $chatBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.RectangleF((Scale-Value -Base $Size -Factor 0.18), (Scale-Value -Base $Size -Factor 0.20), (Scale-Value -Base $Size -Factor 0.56), (Scale-Value -Base $Size -Factor 0.60))),
            [System.Drawing.Color]::FromArgb(255, 244, 247, 255),
            [System.Drawing.Color]::FromArgb(255, 212, 227, 255),
            90
        )
        $graphics.FillPath($chatBrush, $chatPath)

        $shadowColor = [System.Drawing.Color]::FromArgb(50, 7, 10, 17)
        $clawShadowPen = New-Object System.Drawing.Pen($shadowColor, [Math]::Max(6, (Scale-Value -Base $Size -Factor 0.045)))
        $clawShadowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $clawShadowPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

        $graphics.DrawBezier($clawShadowPen, (Scale-Value -Base $Size -Factor 0.35), (Scale-Value -Base $Size -Factor 0.62), (Scale-Value -Base $Size -Factor 0.41), (Scale-Value -Base $Size -Factor 0.40), (Scale-Value -Base $Size -Factor 0.48), (Scale-Value -Base $Size -Factor 0.31), (Scale-Value -Base $Size -Factor 0.59), (Scale-Value -Base $Size -Factor 0.24))
        $graphics.DrawBezier($clawShadowPen, (Scale-Value -Base $Size -Factor 0.43), (Scale-Value -Base $Size -Factor 0.67), (Scale-Value -Base $Size -Factor 0.49), (Scale-Value -Base $Size -Factor 0.46), (Scale-Value -Base $Size -Factor 0.58), (Scale-Value -Base $Size -Factor 0.35), (Scale-Value -Base $Size -Factor 0.67), (Scale-Value -Base $Size -Factor 0.30))
        $graphics.DrawBezier($clawShadowPen, (Scale-Value -Base $Size -Factor 0.51), (Scale-Value -Base $Size -Factor 0.70), (Scale-Value -Base $Size -Factor 0.56), (Scale-Value -Base $Size -Factor 0.52), (Scale-Value -Base $Size -Factor 0.65), (Scale-Value -Base $Size -Factor 0.41), (Scale-Value -Base $Size -Factor 0.73), (Scale-Value -Base $Size -Factor 0.38))

        $clawPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 24, 34, 56), [Math]::Max(6, (Scale-Value -Base $Size -Factor 0.038)))
        $clawPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $clawPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

        $graphics.DrawBezier($clawPen, (Scale-Value -Base $Size -Factor 0.34), (Scale-Value -Base $Size -Factor 0.60), (Scale-Value -Base $Size -Factor 0.40), (Scale-Value -Base $Size -Factor 0.39), (Scale-Value -Base $Size -Factor 0.47), (Scale-Value -Base $Size -Factor 0.29), (Scale-Value -Base $Size -Factor 0.58), (Scale-Value -Base $Size -Factor 0.22))
        $graphics.DrawBezier($clawPen, (Scale-Value -Base $Size -Factor 0.42), (Scale-Value -Base $Size -Factor 0.65), (Scale-Value -Base $Size -Factor 0.48), (Scale-Value -Base $Size -Factor 0.44), (Scale-Value -Base $Size -Factor 0.56), (Scale-Value -Base $Size -Factor 0.33), (Scale-Value -Base $Size -Factor 0.66), (Scale-Value -Base $Size -Factor 0.28))
        $graphics.DrawBezier($clawPen, (Scale-Value -Base $Size -Factor 0.50), (Scale-Value -Base $Size -Factor 0.68), (Scale-Value -Base $Size -Factor 0.55), (Scale-Value -Base $Size -Factor 0.50), (Scale-Value -Base $Size -Factor 0.64), (Scale-Value -Base $Size -Factor 0.39), (Scale-Value -Base $Size -Factor 0.72), (Scale-Value -Base $Size -Factor 0.36))

        $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 97, 168, 255))
        $graphics.FillEllipse($accentBrush, (Scale-Value -Base $Size -Factor 0.25), (Scale-Value -Base $Size -Factor 0.30), (Scale-Value -Base $Size -Factor 0.10), (Scale-Value -Base $Size -Factor 0.10))

        $outlinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 255, 255, 255), [Math]::Max(2, (Scale-Value -Base $Size -Factor 0.008)))
        $graphics.DrawPath($outlinePen, $path)
    } finally {
        if ($outlinePen) { $outlinePen.Dispose() }
        if ($accentBrush) { $accentBrush.Dispose() }
        if ($clawPen) { $clawPen.Dispose() }
        if ($clawShadowPen) { $clawShadowPen.Dispose() }
        if ($chatBrush) { $chatBrush.Dispose() }
        if ($chatPath) { $chatPath.Dispose() }
        if ($glowBrush) { $glowBrush.Dispose() }
        if ($path) { $path.Dispose() }
        if ($gradient) { $gradient.Dispose() }
        $graphics.Dispose()
    }

    return $bitmap
}

function Save-PngToBytes {
    param([System.Drawing.Bitmap]$Bitmap)

    $stream = New-Object System.IO.MemoryStream
    try {
        $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    } finally {
        $stream.Dispose()
    }
}

function Write-IconFile {
    param(
        [byte[][]]$PngImages,
        [int[]]$Sizes,
        [string]$OutputPath
    )

    $fileStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $writer = New-Object System.IO.BinaryWriter($fileStream)

    try {
        $count = $PngImages.Length
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$count)

        $offset = 6 + (16 * $count)

        for ($i = 0; $i -lt $count; $i++) {
            $size = $Sizes[$i]
            $png = $PngImages[$i]

            $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
            $writer.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$png.Length)
            $writer.Write([UInt32]$offset)

            $offset += $png.Length
        }

        foreach ($png in $PngImages) {
            $writer.Write($png)
        }
    } finally {
        $writer.Dispose()
        $fileStream.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$pngPath = Join-Path $OutputDirectory "ClawStudio.png"
$icoPath = Join-Path $OutputDirectory "ClawStudio.ico"
$sizes = @(256, 128, 64, 48, 32, 16)
$pngImages = New-Object 'System.Collections.Generic.List[byte[]]'

$master = New-IconBitmap -Size 1024
try {
    $master.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

    foreach ($size in $sizes) {
        $scaled = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($scaled)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        try {
            $graphics.DrawImage($master, 0, 0, $size, $size)
        } finally {
            $graphics.Dispose()
        }

        try {
            $pngImages.Add((Save-PngToBytes -Bitmap $scaled)) | Out-Null
        } finally {
            $scaled.Dispose()
        }
    }

    Write-IconFile -PngImages $pngImages.ToArray() -Sizes $sizes -OutputPath $icoPath
    Write-Host "Generated icon files:"
    Write-Host " - $pngPath"
    Write-Host " - $icoPath"
} finally {
    $master.Dispose()
}
