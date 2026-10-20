#Requires -Version 5.1
<#
.SYNOPSIS
    主题预设（两种状态）的读取与默认值。

.DESCRIPTION
    约定一个 settings.json，里面固定两套状态：sun（太阳）与 moon（月亮）。
    每套状态各自声明「系统模式」和「应用模式」要深色还是浅色，两者互不干扰：

        {
          "sun":  { "name": "浅色", "system": "dark",  "apps": "light" },
          "moon": { "name": "深色", "system": "dark",  "apps": "dark"  }
        }

    "system" 对应 SystemUsesLightTheme（任务栏、开始菜单、操作中心）
    "apps"   对应 AppsUseLightTheme（默认应用模式）

    取值可写 light / dark，也可以写 浅色 / 深色 / 亮 / 暗，或 true / false。
#>

function Get-PresetConfigPath {
    param([string]$Path)

    if ($Path) { return $Path }
    return (Join-Path -Path $PSScriptRoot -ChildPath 'settings.json')
}

function ConvertTo-ThemeBool {
    param(
        $Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    switch ($text) {
        'light' { return $true }
        'l' { return $true }
        '浅色' { return $true }
        '亮' { return $true }
        '亮色' { return $true }
        'true' { return $true }
        'dark' { return $false }
        'd' { return $false }
        '深色' { return $false }
        '暗' { return $false }
        '暗色' { return $false }
        'false' { return $false }
    }
    return $Default
}

function New-DefaultPresetConfig {
    return @{
        Sun  = @{ Name = '浅色'; AppsUseLight = $true; SystemUsesLight = $false }
        Moon = @{ Name = '深色'; AppsUseLight = $false; SystemUsesLight = $false }
    }
}

function Get-DefaultPresetJson {
    return @'
{
  "sun": {
    "name": "浅色",
    "system": "dark",
    "apps": "light"
  },
  "moon": {
    "name": "深色",
    "system": "dark",
    "apps": "dark"
  }
}
'@
}

function Get-PresetConfig {
    <#
        返回：
            @{ Path; Sun = @{Name; AppsUseLight; SystemUsesLight}; Moon = ...; Loaded; Warning }
        Loaded = $false 表示文件缺失或解析失败，此时用默认值。
    #>
    param([string]$Path)

    $configPath = Get-PresetConfigPath -Path $Path
    $defaults = New-DefaultPresetConfig
    $result = @{
        Path     = $configPath
        Sun      = $defaults.Sun
        Moon     = $defaults.Moon
        Loaded   = $false
        Warning  = $null
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        return $result
    }

    try {
        $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        $result.Warning = 'settings.json 解析失败，已使用默认预设：' + $_.Exception.Message
        return $result
    }

    foreach ($key in @('sun', 'moon')) {
        $node = $raw.$key
        $targetKey = 'Sun'
        if ($key -eq 'moon') { $targetKey = 'Moon' }

        if ($null -eq $node) { continue }

        $name = $defaults[$targetKey].Name
        if ($node.PSObject.Properties['name'] -and $node.name) { $name = [string]$node.name }

        $result[$targetKey] = @{
            Name            = $name
            AppsUseLight    = (ConvertTo-ThemeBool -Value $node.apps -Default $defaults[$targetKey].AppsUseLight)
            SystemUsesLight = (ConvertTo-ThemeBool -Value $node.system -Default $defaults[$targetKey].SystemUsesLight)
        }
    }

    $result.Loaded = $true
    return $result
}

function Save-DefaultPresetFile {
    param([string]$Path)

    $configPath = Get-PresetConfigPath -Path $Path
    if (Test-Path -LiteralPath $configPath) { return $false }

    $json = Get-DefaultPresetJson
    [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($true)))
    return $true
}
