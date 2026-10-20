#Requires -Version 5.1
<#
.SYNOPSIS
    生成快捷方式用的主题图标：右上到左下的斜线分割，左上太阳、右下月亮。

.DESCRIPTION
    画一张圆角方形图标，被一条「右上 -> 左下」的对角线分成两半：
        左上三角 = 米色底 + 琥珀色太阳（8 道光芒）
        右下三角 = 深藏青底 + 米色月牙
    分割线用「深色发丝线 + 白色细线」，在浅色和深色两侧都能看清。

    输出多尺寸 ICO（16/20/24/32/40/48/64/128/256），每档都先按 4 倍分辨率
    渲染再降采样，小尺寸边缘不会发毛。帧格式为 DIB（BMP）而非 PNG——
    System.Drawing.Icon 与不少老工具无法解析 PNG 帧。

.PARAMETER OutputPath
    ico 输出路径，默认同目录的 theme-toggle.ico

.PARAMETER Preview
    额外输出一张 ico-preview.png，方便肉眼确认各尺寸效果

.EXAMPLE
    .\New-ShortcutIcon.ps1
    .\New-ShortcutIcon.ps1 -Preview
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# 注意：PowerShell 5.1 里 $PSScriptRoot 在 param 默认值中取不到，只能在函数体里拼
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $PSScriptRoot -ChildPath 'theme-toggle.ico'
}

# 复用主题图标脚本里的 DIB 帧编码与 ICO 封装
. (Join-Path -Path $PSScriptRoot -ChildPath 'New-ThemeIcon.ps1')

# 配色：米色 / 藏青 / 琥珀 / 月牙米白
$creamColor = [System.Drawing.Color]::FromArgb(255, 247, 236, 208)
$navyColor = [System.Drawing.Color]::FromArgb(255, 29, 35, 61)
$amberColor = [System.Drawing.Color]::FromArgb(255, 222, 136, 44)
$moonColor = [System.Drawing.Color]::FromArgb(255, 242, 234, 210)

function New-ThemeShortcutBitmap {
    param([int]$Size)

    $scale = 4
    $s = [single]($Size * $scale)

    $canvas = New-Object System.Drawing.Bitmap(($Size * $scale), ($Size * $scale), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($canvas)

    $cream = New-Object System.Drawing.SolidBrush($creamColor)
    $navy = New-Object System.Drawing.SolidBrush($navyColor)
    $amber = New-Object System.Drawing.SolidBrush($amberColor)
    $moon = New-Object System.Drawing.SolidBrush($moonColor)
    $ulPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $lrPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $clip = New-Object System.Drawing.Drawing2D.GraphicsPath

    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.Clear([System.Drawing.Color]::Transparent)

        # 圆角方形裁剪，看起来才像一个应用图标
        $r = $s * 0.15
        $clip.AddArc(0, 0, ($r * 2), ($r * 2), 180, 90)
        $clip.AddArc(($s - $r * 2), 0, ($r * 2), ($r * 2), 270, 90)
        $clip.AddArc(($s - $r * 2), ($s - $r * 2), ($r * 2), ($r * 2), 0, 90)
        $clip.AddArc(0, ($s - $r * 2), ($r * 2), ($r * 2), 90, 90)
        $clip.CloseFigure()
        $g.SetClip($clip)

        # 两个三角形：左上 / 右下
        $ulPath.AddPolygon(@(
                (New-Object System.Drawing.PointF(0, 0)),
                (New-Object System.Drawing.PointF($s, 0)),
                (New-Object System.Drawing.PointF(0, $s))))
        $lrPath.AddPolygon(@(
                (New-Object System.Drawing.PointF($s, 0)),
                (New-Object System.Drawing.PointF($s, $s)),
                (New-Object System.Drawing.PointF(0, $s))))

        $g.FillPath($cream, $ulPath)
        $g.FillPath($navy, $lrPath)

        # 分割线：先深色发丝线（在米色侧可见），再白色细线（在藏青侧可见）
        $hair = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 0, 0, 0), [single]($s * 0.026))
        $g.DrawLine($hair, $s, 0, 0, $s)
        $hair.Dispose()

        $line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(232, 255, 255, 255), [single]($s * 0.014))
        $g.DrawLine($line, $s, 0, 0, $s)
        $line.Dispose()

        # 太阳（左上三角的重心附近）
        $cx = $s * 0.315
        $cy = $s * 0.315
        $rad = $s * 0.125
        $g.FillEllipse($amber, ($cx - $rad), ($cy - $rad), ($rad * 2), ($rad * 2))

        $ray = New-Object System.Drawing.Pen($amberColor, [single]($s * 0.034))
        $ray.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $ray.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        for ($i = 0; $i -lt 8; $i++) {
            $angle = [math]::PI * 2 * $i / 8
            $x1 = $cx + [math]::Cos($angle) * ($rad * 1.42)
            $y1 = $cy + [math]::Sin($angle) * ($rad * 1.42)
            $x2 = $cx + [math]::Cos($angle) * ($rad * 1.92)
            $y2 = $cy + [math]::Sin($angle) * ($rad * 1.92)
            $g.DrawLine($ray, [single]$x1, [single]$y1, [single]$x2, [single]$y2)
        }
        $ray.Dispose()

        # 月亮（右下三角的重心附近）：用同色圆切出月牙
        $mx = $s * 0.675
        $my = $s * 0.675
        $mr = $s * 0.180
        $g.FillEllipse($moon, ($mx - $mr), ($my - $mr), ($mr * 2), ($mr * 2))

        $cutX = $mx + $mr * 0.52
        $cutY = $my - $mr * 0.52
        $g.FillEllipse($navy, ($cutX - $mr * 1.04), ($cutY - $mr * 1.04), ($mr * 2.08), ($mr * 2.08))
    }
    finally {
        $g.Dispose()
        $cream.Dispose()
        $navy.Dispose()
        $amber.Dispose()
        $moon.Dispose()
        $ulPath.Dispose()
        $lrPath.Dispose()
        $clip.Dispose()
    }

    $result = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $scaler = [System.Drawing.Graphics]::FromImage($result)
    try {
        $scaler.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $scaler.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $scaler.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $scaler.DrawImage($canvas, 0, 0, $Size, $Size)
    }
    finally {
        $scaler.Dispose()
        $canvas.Dispose()
    }

    return $result
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$frames = New-Object System.Collections.ArrayList

foreach ($size in $sizes) {
    $bitmap = New-ThemeShortcutBitmap -Size $size
    try {
        [void]$frames.Add((New-IconDibFrame -Bitmap $bitmap))
    }
    finally {
        $bitmap.Dispose()
    }
}

$icoBytes = New-IcoBytes -Frames $frames.ToArray() -Sizes $sizes
[System.IO.File]::WriteAllBytes($OutputPath, $icoBytes)

Write-Output ('已生成: ' + $OutputPath)
Write-Output ('尺寸: ' + ($sizes -join ' / ') + '，' + [math]::Round($icoBytes.Length / 1KB, 1) + ' KB')

if ($Preview) {
    $previewPath = Join-Path -Path $PSScriptRoot -ChildPath 'ico-preview.png'
    $sheet = New-Object System.Drawing.Bitmap(560, 340)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(255, 58, 58, 62))
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        $big = New-ThemeShortcutBitmap -Size 128
        $g.DrawImage($big, 16, 16, 256, 256)
        $big.Dispose()

        $font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 210, 210, 210))
        $g.DrawString('256 / 128', $font, $brush, 16, 280)

        $x = 296
        foreach ($size in @(48, 32, 24, 16)) {
            $img = New-ThemeShortcutBitmap -Size $size
            $g.DrawImage($img, $x, 20, $size, $size)
            $img.Dispose()
            $g.DrawString([string]$size, $font, $brush, $x, 20 + $size + 6)
            $x += 56
        }
        $font.Dispose()
        $brush.Dispose()
    }
    finally {
        $g.Dispose()
    }

    $sheet.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $sheet.Dispose()
    Write-Output ('预览: ' + $previewPath)
}
