#Requires -Version 5.1
<#
.SYNOPSIS
    生成符合 Windows 托盘风格的扁平单色图标（Segoe MDL2 Assets 字形 + 多尺寸 ICO）。

.DESCRIPTION
    不用 emoji / 拟物字符，而是直接取系统的 Segoe MDL2 Assets 图标字体：
        U+E706  Brightness（线条太阳）  -> 浅色模式
        U+E708  QuietHours（线条月牙）  -> 深色模式
    单色、无渐变、描边风格，和音量、网络这些系统托盘图标是同一套设计语言。

    输出为内存中的多尺寸 ICO（16/20/24/32/40/48），NotifyIcon 按当前 DPI 取最合适的一档。
    注意：帧格式用传统 DIB（BMP）而不是 PNG —— .NET 的 System.Drawing.Icon 无法解析
    PNG 压缩帧，会直接抛 "Argument 'picture' must be a picture that can be used as a Icon"。

    用法：dot-source 之后调用 New-TrayIcon -Glyph sun|moon [-LightTaskbar]
#>

Add-Type -AssemblyName System.Drawing

# System.Drawing.Icon 是惰性解码的，流被回收后句柄可能失效，所以挂到静态表里保活
if (-not ('ThemeIconCache' -as [type])) {
    Add-Type -TypeDefinition @'
public static class ThemeIconCache
{
    public static readonly System.Collections.Generic.List<System.IO.Stream> Streams =
        new System.Collections.Generic.List<System.IO.Stream>();
}
'@
}

function Get-SmallIconSize {
    if (-not ('Win32.IconMetrics' -as [type])) {
        Add-Type -Namespace Win32 -Name IconMetrics -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern int GetSystemMetrics(int nIndex);
'@
    }

    # SM_CXSMICON = 49，取当前 DPI 下托盘图标的实际像素尺寸
    $size = [Win32.IconMetrics]::GetSystemMetrics(49)
    if ($size -lt 16) { $size = 16 }
    return $size
}

function New-IconDibFrame {
    <#
        把一张 32 位 ARGB 位图编码成 ICO 的单帧 DIB：
        BITMAPINFOHEADER（高度写两倍，包含 XOR 位图与 AND 掩码）+ 自下而上的 BGRA 像素 + 全零掩码。
    #>
    param([System.Drawing.Bitmap]$Bitmap)

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)

    $lock = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = $lock.Stride
        $pixels = New-Object byte[] ($stride * $height)
        [System.Runtime.InteropServices.Marshal]::Copy($lock.Scan0, $pixels, 0, $pixels.Length)
    }
    finally {
        $Bitmap.UnlockBits($lock)
    }

    $rowBytes = $width * 4
    $maskRowBytes = [int]([math]::Ceiling($width / 32.0) * 4)
    $maskBytes = $maskRowBytes * $height
    $xorBytes = $rowBytes * $height

    $memory = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($memory)

    try {
        $writer.Write([Int32]40)              # biSize
        $writer.Write([Int32]$width)          # biWidth
        $writer.Write([Int32]($height * 2))   # biHeight：XOR + AND 两张图叠在一起
        $writer.Write([Int16]1)               # biPlanes
        $writer.Write([Int16]32)              # biBitCount
        $writer.Write([Int32]0)               # biCompression = BI_RGB
        $writer.Write([Int32]$xorBytes)       # biSizeImage
        $writer.Write([Int32]0)               # biXPelsPerMeter
        $writer.Write([Int32]0)               # biYPelsPerMeter
        $writer.Write([Int32]0)               # biClrUsed
        $writer.Write([Int32]0)               # biClrImportant

        # 自下而上写入，32 位图标直接靠 alpha 通道做透明，AND 掩码留全零
        for ($y = $height - 1; $y -ge 0; $y--) {
            $writer.Write($pixels, ($y * $stride), $rowBytes)
        }

        $writer.Write((New-Object byte[] $maskBytes))
        $writer.Flush()

        return , $memory.ToArray()
    }
    finally {
        $writer.Dispose()
        $memory.Dispose()
    }
}

function New-IconFrames {
    param(
        [string]$Glyph,
        [System.Drawing.Color]$Color,
        [int[]]$Sizes
    )

    $fontName = 'Segoe MDL2 Assets'
    $frames = New-Object System.Collections.ArrayList

    foreach ($size in $Sizes) {
        # 小尺寸先按 4 倍分辨率渲染再降采样，线条边缘比直接画 16px 干净得多；
        # 32px 以上本身够大，直接渲染反而更锐利。
        $work = $size
        if ($size -lt 32) { $work = $size * 4 }

        $canvas = New-Object System.Drawing.Bitmap($work, $work, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)

        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            # 灰度抗锯齿：ClearType 会产生彩色边缘，写进带 alpha 的图标会很脏
            $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias

            # 字形占画布约 92%，留出托盘图标该有的呼吸空间
            $fontSize = [single]([math]::Round($work * 0.95))
            if ($fontSize -lt 9) { $fontSize = 9 }

            $font = New-Object System.Drawing.Font($fontName, $fontSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
            $brush = New-Object System.Drawing.SolidBrush($Color)
            $format = New-Object System.Drawing.StringFormat
            $format.Alignment = [System.Drawing.StringAlignment]::Center
            $format.LineAlignment = [System.Drawing.StringAlignment]::Center
            $format.FormatFlags = [System.Drawing.StringFormatFlags]::NoClip
            $rect = New-Object System.Drawing.RectangleF(0, 0, $work, $work)

            try {
                $graphics.DrawString($Glyph, $font, $brush, $rect, $format)
            }
            finally {
                $format.Dispose()
                $brush.Dispose()
                $font.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }

        $bitmap = $canvas
        if ($work -ne $size) {
            $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $scaler = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $scaler.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $scaler.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $scaler.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $scaler.DrawImage($canvas, 0, 0, $size, $size)
            }
            finally {
                $scaler.Dispose()
            }
            $canvas.Dispose()
        }

        try {
            [void]$frames.Add((New-IconDibFrame -Bitmap $bitmap))
        }
        finally {
            $bitmap.Dispose()
        }
    }

    return , $frames.ToArray()
}

function New-IcoBytes {
    param(
        [object[]]$Frames,
        [int[]]$Sizes
    )

    $memory = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($memory)

    try {
        # ICONDIR
        $writer.Write([UInt16]0)                    # reserved
        $writer.Write([UInt16]1)                    # type: icon
        $writer.Write([UInt16]$Frames.Count)

        # ICONDIRENTRY × N，图像数据紧跟在目录之后
        $offset = 6 + 16 * $Frames.Count
        for ($i = 0; $i -lt $Frames.Count; $i++) {
            $size = $Sizes[$i]
            $dimension = 0
            if ($size -lt 256) { $dimension = $size }

            $writer.Write([byte]$dimension)         # width（256 记作 0）
            $writer.Write([byte]$dimension)         # height
            $writer.Write([byte]0)                  # 调色板颜色数
            $writer.Write([byte]0)                  # reserved
            $writer.Write([UInt16]1)                # color planes
            $writer.Write([UInt16]32)               # bits per pixel
            $writer.Write([UInt32]$Frames[$i].Length)
            $writer.Write([UInt32]$offset)
            $offset += $Frames[$i].Length
        }

        foreach ($frame in $Frames) {
            $writer.Write($frame)
        }

        $writer.Flush()
        return , $memory.ToArray()
    }
    finally {
        $writer.Dispose()
        $memory.Dispose()
    }
}

function New-TrayIcon {
    <#
        Glyph        : sun（U+E706 线条太阳）| moon（U+E708 线条月牙）
        LightTaskbar : 任务栏是浅色时用深灰描边，否则纯白。
                       颜色只看任务栏，不看当前是哪套预设 —— 否则「系统常驻深色 + 太阳图标」
                       会画出一个深灰太阳贴在深色任务栏上，基本看不见。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('sun', 'moon')]
        [string]$Glyph,

        [switch]$LightTaskbar
    )

    if ($Glyph -eq 'sun') {
        $glyphText = [string][char]0xE706
    }
    else {
        $glyphText = [string][char]0xE708
    }

    if ($LightTaskbar) {
        $color = [System.Drawing.Color]::FromArgb(255, 26, 26, 26)
    }
    else {
        $color = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
    }

    $sizes = 16, 20, 24, 32, 40, 48
    $frames = New-IconFrames -Glyph $glyphText -Color $color -Sizes $sizes
    $icoBytes = New-IcoBytes -Frames $frames -Sizes $sizes

    $stream = New-Object System.IO.MemoryStream(, $icoBytes)
    [ThemeIconCache]::Streams.Add($stream)

    $smallSize = Get-SmallIconSize
    $icon = New-Object System.Drawing.Icon($stream, $smallSize, $smallSize)
    return $icon
}
