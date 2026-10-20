#Requires -Version 5.1
<#
.SYNOPSIS
    在 settings.json 定义的两套主题状态之间切换（太阳 / 月亮）。

.DESCRIPTION
    每套状态各自声明系统模式与应用模式，互不干扰，例如：
        sun  = 系统深色 + 应用浅色
        moon = 系统深色 + 应用深色
    切换时把这两项一起写成该状态的值，所以「点一下换个状态」是确定性的，
    不会出现只改了一半的中间态。

.PARAMETER Preset
    next（默认，切到另一套）| sun | moon

.PARAMETER DryRun
    只打印将要写入的值，不修改注册表，用于检查配置是否正确。

.EXAMPLE
    .\Toggle-Theme.ps1
    .\Toggle-Theme.ps1 -Preset moon
    .\Toggle-Theme.ps1 -Status
    .\Toggle-Theme.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('next', 'sun', 'moon')]
    [string]$Preset = 'next',

    [string]$ConfigPath,

    [switch]$Status,

    [switch]$DryRun,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'ThemePresets.ps1')

$personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$appsValueName = 'AppsUseLightTheme'
$systemValueName = 'SystemUsesLightTheme'

function Get-ThemeValue {
    param([string]$Name, [bool]$Default = $true)

    $value = (Get-ItemProperty -Path $personalizeKey -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $value) { return $Default }
    return ([int]$value -ne 0)
}

function Get-ModeName {
    param([bool]$Light)
    if ($Light) { return '浅色' }
    return '深色'
}

function Send-ThemeChangedBroadcast {
    if (-not ('Win32.ThemeBroadcast' -as [type])) {
        Add-Type -Namespace Win32 -Name ThemeBroadcast -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(
    System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out System.UIntPtr pdwResult);
'@
    }

    $result = [System.UIntPtr]::Zero
    [void][Win32.ThemeBroadcast]::SendMessageTimeout(
        [System.IntPtr]0xFFFF, 0x001A, [System.UIntPtr]::Zero, 'ImmersiveColorSet',
        0x0002, 1000, [ref]$result)
}

function Get-ActivePresetKey {
    param($Config, [bool]$AppsLight, [bool]$SystemLight)

    if ($AppsLight -eq $Config.Sun.AppsUseLight -and $SystemLight -eq $Config.Sun.SystemUsesLight) { return 'Sun' }
    if ($AppsLight -eq $Config.Moon.AppsUseLight -and $SystemLight -eq $Config.Moon.SystemUsesLight) { return 'Moon' }
    return $null
}

if (-not $DryRun) {
    [void](Save-DefaultPresetFile -Path $ConfigPath)
}

$config = Get-PresetConfig -Path $ConfigPath
$appsLight = Get-ThemeValue -Name $appsValueName
$systemLight = Get-ThemeValue -Name $systemValueName
$activeKey = Get-ActivePresetKey -Config $config -AppsLight $appsLight -SystemLight $systemLight

if ($Status) {
    Write-Output ('当前状态: 系统 ' + (Get-ModeName -Light $systemLight) + ' / 应用 ' + (Get-ModeName -Light $appsLight))
    if ($activeKey) {
        Write-Output ('命中预设: ' + $config[$activeKey].Name + ' (' + $activeKey.ToLowerInvariant() + ')')
    }
    else {
        Write-Output '命中预设: 无（当前值与两套预设都不一致）'
    }

    foreach ($key in @('Sun', 'Moon')) {
        $p = $config[$key]
        Write-Output ('  预设 ' + $p.Name + ' (' + $key.ToLowerInvariant() + '): 系统 ' + (Get-ModeName -Light $p.SystemUsesLight) + ' / 应用 ' + (Get-ModeName -Light $p.AppsUseLight))
    }

    $stateText = '已加载'
    if (-not $config.Loaded) { $stateText = '不存在，使用内置默认值' }
    Write-Output ('设置文件: ' + $config.Path + '（' + $stateText + '）')
    if ($config.Warning) { Write-Output ('警告: ' + $config.Warning) }
    return
}

# 决定这次要套用哪一套
$targetKey = $null
switch ($Preset) {
    'sun' { $targetKey = 'Sun' }
    'moon' { $targetKey = 'Moon' }
    default {
        if ($activeKey -eq 'Sun') { $targetKey = 'Moon' }
        else { $targetKey = 'Sun' }
    }
}

$target = $config[$targetKey]
$appsDword = 0
if ($target.AppsUseLight) { $appsDword = 1 }
$systemDword = 0
if ($target.SystemUsesLight) { $systemDword = 1 }

$summary = '系统 ' + (Get-ModeName -Light $target.SystemUsesLight) + ' / 应用 ' + (Get-ModeName -Light $target.AppsUseLight)

if ($DryRun) {
    Write-Output ('将套用预设: ' + $target.Name + ' (' + $targetKey.ToLowerInvariant() + ') -> ' + $summary)
    Write-Output ('  AppsUseLightTheme   = ' + $appsDword)
    Write-Output ('  SystemUsesLightTheme = ' + $systemDword)
    Write-Output '（DryRun：未写入注册表）'
    return
}

if (-not (Test-Path -Path $personalizeKey)) {
    New-Item -Path $personalizeKey -Force | Out-Null
}

New-ItemProperty -Path $personalizeKey -Name $appsValueName -Value $appsDword -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $personalizeKey -Name $systemValueName -Value $systemDword -PropertyType DWord -Force | Out-Null
Send-ThemeChangedBroadcast

if (-not $Quiet) {
    Write-Output ('已切换到: ' + $target.Name + '  (' + $summary + ')')
}
