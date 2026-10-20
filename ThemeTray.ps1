#Requires -Version 5.1
<#
.SYNOPSIS
    任务栏右下角的主题托盘开关：在 settings.json 的两套状态（太阳 / 月亮）之间切换。

.DESCRIPTION
    每套状态各自定义了「系统模式」和「应用模式」，点一下整套套用，不存在改了一半的中间态。
        太阳 -> 浅色那套（默认：系统深色 + 应用浅色）
        月亮 -> 深色那套（默认：系统深色 + 应用深色）
    图标取自 Segoe MDL2 Assets：U+E706 Brightness / U+E708 QuietHours，
    单色描边，16/20/24/32/40/48 多尺寸，高 DPI 不糊。

    左键单击 = 切到另一套；右键 = 直接指定某一套 / 重新载入配置 / 编辑配置 / 退出。

    注意：Set-Location 与 $script: 在 WinForms 回调里并不可靠，所以状态全部放在
    $global:ThemeTrayState 里，回调只调用显式声明的 global 函数。
#>
[CmdletBinding()]
param(
    # 自检：反复触发菜单回调与界面刷新，不修改主题，用于验证回调链无异常
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$toggleScript = Join-Path -Path $PSScriptRoot -ChildPath 'Toggle-Theme.ps1'
$iconScript = Join-Path -Path $PSScriptRoot -ChildPath 'New-ThemeIcon.ps1'
$presetScript = Join-Path -Path $PSScriptRoot -ChildPath 'ThemePresets.ps1'
$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'settings.json'

foreach ($required in @($toggleScript, $iconScript, $presetScript)) {
    if (-not (Test-Path -Path $required)) {
        throw "缺少依赖文件：$required"
    }
}

. $iconScript
. $presetScript

# 单实例
$mutex = New-Object System.Threading.Mutex($false, 'Local\DshThemeTrayIcon')
$acquired = $false
try {
    $acquired = $mutex.WaitOne(0, $false)
}
catch {
    $acquired = $false
}
if (-not $acquired) {
    return
}

$pidFile = Join-Path -Path $PSScriptRoot -ChildPath 'ThemeTray.pid'
try {
    $startTicks = (Get-Process -Id $PID).StartTime.Ticks
    [System.IO.File]::WriteAllText($pidFile, ("{0}|{1}" -f $PID, $startTicks))
}
catch {
    # 写不了不影响主功能
}

$global:ThemeTrayState = @{
    Icon         = $null
    Icons        = $null
    Config       = $null
    ConfigPath   = $configPath
    AppsLight    = $true
    SystemLight  = $true
    ActiveKey    = $null
    Busy         = $false
    LastAction   = [int64]0
    DryRun       = $false
    ToggleScript = $toggleScript
    LogPath      = (Join-Path -Path $PSScriptRoot -ChildPath 'ThemeTray.error.log')
    MenuSun      = $null
    MenuMoon     = $null
}

function global:Write-TrayError {
    param($Detail)

    try {
        $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Detail
        Add-Content -LiteralPath $global:ThemeTrayState.LogPath -Value $line -Encoding UTF8
    }
    catch {
        # 日志都写不了就只能放弃，不能让它再抛
    }
}

function global:Get-ThemeStates {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $appsRaw = (Get-ItemProperty -Path $key -Name 'AppsUseLightTheme' -ErrorAction SilentlyContinue).AppsUseLightTheme
    $systemRaw = (Get-ItemProperty -Path $key -Name 'SystemUsesLightTheme' -ErrorAction SilentlyContinue).SystemUsesLightTheme

    $appsLight = $true
    if ($null -ne $appsRaw) { $appsLight = ([int]$appsRaw -ne 0) }
    $systemLight = $true
    if ($null -ne $systemRaw) { $systemLight = ([int]$systemRaw -ne 0) }

    return @{ Apps = $appsLight; System = $systemLight }
}

function global:Get-ActivePresetKey {
    $state = $global:ThemeTrayState
    $config = $state.Config
    if ($null -eq $config) { return $null }

    if ($state.AppsLight -eq $config.Sun.AppsUseLight -and $state.SystemLight -eq $config.Sun.SystemUsesLight) { return 'Sun' }
    if ($state.AppsLight -eq $config.Moon.AppsUseLight -and $state.SystemLight -eq $config.Moon.SystemUsesLight) { return 'Moon' }
    return $null
}

function global:Update-TrayVisual {
    $state = $global:ThemeTrayState
    if ($null -eq $state -or $null -eq $state.Icon) { return }

    $active = Get-ActivePresetKey
    $state.ActiveKey = $active

    if ($active -eq 'Sun') { $glyphKey = 'Sun' }
    elseif ($active -eq 'Moon') { $glyphKey = 'Moon' }
    elseif ($state.AppsLight) { $glyphKey = 'Sun' }   # 不匹配任何预设时退化为按应用模式
    else { $glyphKey = 'Moon' }

    $taskbarKey = 'OnDarkTaskbar'
    if ($state.SystemLight) { $taskbarKey = 'OnLightTaskbar' }

    $state.Icon.Icon = $state.Icons[$glyphKey][$taskbarKey]

    $sysText = '深色'
    if ($state.SystemLight) { $sysText = '浅色' }
    $appText = '深色'
    if ($state.AppsLight) { $appText = '浅色' }

    if ($active) {
        $name = $state.Config[$active].Name
        $state.Icon.Text = "$name · 系统 $sysText · 应用 $appText"
    }
    else {
        $state.Icon.Text = "未匹配预设 · 系统 $sysText · 应用 $appText"
    }
}

function global:Refresh-TrayState {
    $states = Get-ThemeStates
    $global:ThemeTrayState.AppsLight = $states.Apps
    $global:ThemeTrayState.SystemLight = $states.System
    Update-TrayVisual
}

function global:Update-MenuLabels {
    $state = $global:ThemeTrayState
    if ($null -eq $state.Config) { return }

    if ($state.MenuSun) {
        $state.MenuSun.Text = '切换到「' + $state.Config.Sun.Name + '」'
        $state.MenuSun.Checked = ($state.ActiveKey -eq 'Sun')
    }
    if ($state.MenuMoon) {
        $state.MenuMoon.Text = '切换到「' + $state.Config.Moon.Name + '」'
        $state.MenuMoon.Checked = ($state.ActiveKey -eq 'Moon')
    }
}

function global:Invoke-ThemeAction {
    param(
        [ValidateSet('next', 'sun', 'moon')]
        [string]$Preset = 'next'
    )

    $state = $global:ThemeTrayState

    # 防连点：300ms 内只认一次
    # 用 DateTime.Ticks 而不是 Environment.TickCount64 —— 后者在 .NET Framework 下取到 $null，
    # 会让 `$now - $LastAction` 恒为 0，判断恒真，结果就是“点了没反应”。
    $now = [DateTime]::UtcNow.Ticks
    if (($now - $state.LastAction) -lt 3000000) { return }
    if ($state.Busy) { return }

    $state.LastAction = $now
    $state.Busy = $true

    try {
        if (-not $state.DryRun) {
            & $state.ToggleScript -Preset $Preset -Quiet | Out-Null
            Start-Sleep -Milliseconds 120
        }
        Refresh-TrayState
        Update-MenuLabels
    }
    finally {
        $state.Busy = $false
    }
}

function global:Reload-PresetConfig {
    $state = $global:ThemeTrayState
    $state.Config = Get-PresetConfig -Path $state.ConfigPath
    Refresh-TrayState
    Update-MenuLabels
}

[void](Save-DefaultPresetFile -Path $global:ThemeTrayState.ConfigPath)
$global:ThemeTrayState.Config = Get-PresetConfig -Path $global:ThemeTrayState.ConfigPath

$states = Get-ThemeStates
$global:ThemeTrayState.AppsLight = $states.Apps
$global:ThemeTrayState.SystemLight = $states.System
# 四枚图标：太阳/月亮 x 深色任务栏/浅色任务栏。描边颜色跟着任务栏走，
# 否则「系统常驻深色 + 太阳图标」会在深色任务栏上画一个几乎看不见的深灰太阳。
$global:ThemeTrayState.Icons = @{
    Sun  = @{
        OnDarkTaskbar  = (New-TrayIcon -Glyph 'sun')
        OnLightTaskbar = (New-TrayIcon -Glyph 'sun' -LightTaskbar)
    }
    Moon = @{
        OnDarkTaskbar  = (New-TrayIcon -Glyph 'moon')
        OnLightTaskbar = (New-TrayIcon -Glyph 'moon' -LightTaskbar)
    }
}

$global:ThemeTrayState.Icon = New-Object System.Windows.Forms.NotifyIcon
$global:ThemeTrayState.Icon.Visible = $true
Update-TrayVisual

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$menuSun = New-Object System.Windows.Forms.ToolStripMenuItem('切换到「浅色」')
$menuSun.add_Click({
        try { Invoke-ThemeAction -Preset 'sun' }
        catch { Write-TrayError $_ }
    })

$menuMoon = New-Object System.Windows.Forms.ToolStripMenuItem('切换到「深色」')
$menuMoon.add_Click({
        try { Invoke-ThemeAction -Preset 'moon' }
        catch { Write-TrayError $_ }
    })

$menuReload = New-Object System.Windows.Forms.ToolStripMenuItem('重新载入 settings.json')
$menuReload.add_Click({
        try { Reload-PresetConfig }
        catch { Write-TrayError $_ }
    })

$menuEdit = New-Object System.Windows.Forms.ToolStripMenuItem('编辑 settings.json')
$menuEdit.add_Click({
        try {
            Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $global:ThemeTrayState.ConfigPath + '"') | Out-Null
        }
        catch { Write-TrayError $_ }
    })

$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem('退出')
$menuExit.add_Click({
        try {
            $global:ThemeTrayState.Icon.Visible = $false
            $global:ThemeTrayState.Icon.Dispose()
            [System.Windows.Forms.Application]::ExitThread()
        }
        catch { Write-TrayError $_ }
    })

[void]$menu.Items.Add($menuSun)
[void]$menu.Items.Add($menuMoon)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($menuReload)
[void]$menu.Items.Add($menuEdit)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($menuExit)

$global:ThemeTrayState.MenuSun = $menuSun
$global:ThemeTrayState.MenuMoon = $menuMoon

# 打开菜单时刷新对勾与文字，避免配置改过之后显示的还是旧名字
$menu.add_Opening({
        try {
            Refresh-TrayState
            Update-MenuLabels
        }
        catch { Write-TrayError $_ }
    })

$global:ThemeTrayState.Icon.ContextMenuStrip = $menu
$global:ThemeTrayState.Icon.add_MouseClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        try { Invoke-ThemeAction -Preset 'next' }
        catch { Write-TrayError $_ }
    })

# 外部改了主题时同步图标与提示
$stateTimer = New-Object System.Windows.Forms.Timer
$stateTimer.Interval = 2000
$stateTimer.add_Tick({
        try {
            $current = Get-ThemeStates
            if ($current.Apps -ne $global:ThemeTrayState.AppsLight -or $current.System -ne $global:ThemeTrayState.SystemLight) {
                $global:ThemeTrayState.AppsLight = $current.Apps
                $global:ThemeTrayState.SystemLight = $current.System
                Update-TrayVisual
            }
        }
        catch { Write-TrayError $_ }
    })
$stateTimer.Start()

Update-MenuLabels

if ($SelfTest) {
    # 自检：反复触发回调，验证不再抛异常；DryRun 保证不改主题
    $global:ThemeTrayState.DryRun = $true
    $failures = 0

    for ($i = 0; $i -lt 30; $i++) {
        try {
            $global:ThemeTrayState.LastAction = [int64]0
            $menuSun.PerformClick()
            $global:ThemeTrayState.LastAction = [int64]0
            $menuMoon.PerformClick()
            $global:ThemeTrayState.LastAction = [int64]0
            Update-TrayVisual
            Update-MenuLabels
            [System.Windows.Forms.Application]::DoEvents()
        }
        catch {
            $failures++
            Write-Output ("self-test 异常: " + $_)
        }
    }

    $stateTimer.Stop()
    $global:ThemeTrayState.Icon.Visible = $false
    $global:ThemeTrayState.Icon.Dispose()
    if (Test-Path -LiteralPath $global:ThemeTrayState.LogPath) {
        Write-Output ('error log 有内容：' + (Get-Content -Raw -LiteralPath $global:ThemeTrayState.LogPath))
    }
    Write-Output ("SelfTest 完成，未捕获异常次数: $failures")
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    return
}

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    $stateTimer.Stop()
    $stateTimer.Dispose()
    try {
        $global:ThemeTrayState.Icon.Visible = $false
        $global:ThemeTrayState.Icon.Dispose()
    }
    catch { }
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    try {
        if (Test-Path -LiteralPath $pidFile) { Remove-Item -LiteralPath $pidFile -Force }
    }
    catch {
        # 清理失败无所谓
    }
}
