# Re-run after downloading or moving this folder to refresh the shortcut paths.
$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot 'Start-ThemeTray.vbs'
$icon = Join-Path $PSScriptRoot 'theme-toggle.ico'
foreach ($requiredFile in @($launcher, $icon)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required file is missing: $requiredFile"
    }
}
$shortcutPath = Join-Path $PSScriptRoot 'Start-ThemeTray.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$shortcut.Arguments = '"' + $launcher + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = $icon + ',0'
$shortcut.Description = 'Start the theme tray switcher'
$shortcut.WindowStyle = 1
$shortcut.Save()
Write-Host "Shortcut created: $shortcutPath"
