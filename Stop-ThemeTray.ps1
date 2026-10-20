#Requires -Version 5.1
<#
.SYNOPSIS
    关闭右下角的主题托盘图标（ThemeTray.ps1）。

.DESCRIPTION
    优先按 ThemeTray.ps1 启动时写下的 PID 文件精确结束进程，并用启动时间校验，
    避免 PID 被系统复用后误杀无关的 powershell。
    PID 文件缺失或失效时，退回按命令行匹配 ThemeTray.ps1 查找。

.EXAMPLE
    .\Stop-ThemeTray.ps1
#>
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$pidFile = Join-Path -Path $PSScriptRoot -ChildPath 'ThemeTray.pid'
$stopped = @()

function Test-IsTrayProcess {
    param([int]$ProcessId, [long]$StartTicks)

    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $proc) { return $false }
    if ($proc.ProcessName -ne 'powershell') { return $false }
    if ($StartTicks -gt 0) {
        try {
            if ($proc.StartTime.Ticks -ne $StartTicks) { return $false }
        }
        catch {
            return $false
        }
    }
    return $true
}

# 首选：按 PID 文件精确关闭
if (Test-Path -LiteralPath $pidFile) {
    $raw = ''
    try {
        $raw = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    }
    catch {
        $raw = ''
    }

    $parts = $raw -split '\|'
    $recordedId = 0
    if ($parts.Count -ge 1) { [void][int]::TryParse($parts[0], [ref]$recordedId) }
    $recordedTicks = 0L
    if ($parts.Count -ge 2) { [void][long]::TryParse($parts[1], [ref]$recordedTicks) }

    if ($recordedId -gt 0 -and (Test-IsTrayProcess -ProcessId $recordedId -StartTicks $recordedTicks)) {
        Stop-Process -Id $recordedId -Force
        $stopped += $recordedId
    }

    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

# 兜底：PID 文件丢了（比如旧版本启动的实例），按命令行找
if ($stopped.Count -eq 0) {
    try {
        # 注意匹配 '*\ThemeTray.ps1*'：写成 '*ThemeTray.ps1*' 会把 Stop-ThemeTray.ps1 自己也匹配上，
        # 于是这个停止脚本会把自己杀掉（表现为没有任何输出、退出码 -1）。
        $candidates = Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*\ThemeTray.ps1*' }

        foreach ($candidate in $candidates) {
            try {
                Stop-Process -Id $candidate.ProcessId -Force -ErrorAction Stop
                $stopped += $candidate.ProcessId
            }
            catch {
                # 单个进程关不掉不影响其他
            }
        }
    }
    catch {
        # WMI 不可用时不报错，交给下面的提示
    }
}

if (-not $Quiet) {
    if ($stopped.Count -gt 0) {
        Write-Output ('已退出主题托盘图标，PID: ' + ($stopped -join ', '))
    }
    else {
        Write-Output '没有发现正在运行的主题托盘进程（可能已经关掉了）。'
    }
}
