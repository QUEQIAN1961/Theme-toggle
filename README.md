# Theme-toggle

**简体中文** | [English](README.en.md)

轻量的 Windows 10 / 11 主题托盘工具，一键切换自定义深浅色预设，可分别配置系统和应用主题。基于 PowerShell 与 Windows 内置组件，无需安装额外依赖。

在任务栏右下角通知区域放一个常驻图标，**点一下在两套自定义状态之间切换**（太阳 / 月亮）。
用来替代「设置 → 个性化 → 颜色 → 自定义 → 默认应用模式」这条七步路径，也把「系统模式」和「应用模式」两个独立开关一次配好。

![图标预览](preview.png)

## 快速开始

1. 在本仓库页面点击 **Code → Download ZIP** 并解压，或使用 `git clone https://github.com/QUEQIAN1961/Theme-toggle.git`。
2. 双击 `Create-Shortcut.cmd`，在当前目录生成带自定义图标的 `Start-ThemeTray.lnk`。
3. 双击 `Start-ThemeTray.lnk`（也可直接运行 `Start-ThemeTray.vbs`），在任务栏通知区域找到太阳 / 月亮图标。
4. 左键切换主题；右键打开菜单，修改 `settings.json` 后选择“重新载入 settings.json”。

需要 Windows 10 / 11、Windows PowerShell 5.1 和启用的 Windows Script Host。通常不需要管理员权限。下载后若 Windows 提示文件来自互联网，请确认来源后在 ZIP 属性中解除锁定，再解压使用。

快捷方式根据当前目录生成；移动文件夹后，请重新运行 `Create-Shortcut.cmd`。仓库不包含绑定个人电脑路径的 `.lnk` 文件。

## 两套状态由你自己定义

同目录的 `settings.json`（首次运行会自动生成）：

```json
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
```

- `sun` / `moon` 就是两套状态，名字对应太阳和月亮图标，`name` 可以随便改（会显示在菜单和悬停提示里）。
- `system` → `SystemUsesLightTheme`，任务栏 / 开始菜单 / 操作中心。
- `apps` → `AppsUseLightTheme`，设置里的「默认应用模式」。
- 取值可以写 `light` / `dark`，也可以写 `浅色` / `深色` / `亮` / `暗`，或者 `true` / `false`。
- 默认配置就是「**Windows 常驻深色，只切应用模式**」：系统始终 `dark`，太阳那套给应用浅色、月亮那套给应用深色。
  想把系统也跟着换，把某个 `system` 改成 `light` 即可。

改完 `settings.json` 后，右键图标 → **重新载入 settings.json**，不用重启托盘。

## 文件

| 文件 | 作用 |
| --- | --- |
| `settings.json` | 两套状态的定义（你要改的就是这个） |
| `ThemePresets.ps1` | 读取与校验 `settings.json`，坏 JSON 自动回退默认值 |
| `Toggle-Theme.ps1` | 按预设写注册表 + 广播 `WM_SETTINGCHANGE` |
| `ThemeTray.ps1` | 托盘图标外壳（左键切换、右键菜单） |
| `New-ThemeIcon.ps1` | 用 Segoe MDL2 字形生成多尺寸 ICO |
| `Create-Shortcut.cmd` / `Create-Shortcut.ps1` | 根据当前目录生成带图标的启动快捷方式 |
| `Start-ThemeTray.vbs` | 静默启动器，双击即可，不闪黑框 |
| `Stop-ThemeTray.ps1` / `Stop-ThemeTray.vbs` | 关闭托盘图标 |
| `theme-toggle.ico` | 快捷方式用的图标（斜线分割，左上太阳右下月亮） |
| `New-ShortcutIcon.ps1` | 重新生成上面的 ico |
| `preview.png` | 托盘图标在各尺寸、深/浅任务栏下的样子 |
| `ico-preview.png` | 快捷方式图标的效果预览 |

## 快捷方式图标

`theme-toggle.ico` 是给快捷方式准备的：右上到左下的斜线分割，左上半太阳、右下半月亮。
9 档尺寸（16/20/24/32/40/48/64/128/256），小尺寸先 4 倍渲染再降采样，边缘不糊。

做一个「一键切换」快捷方式：

1. 桌面右键 → 新建 → 快捷方式。
2. 位置填：
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "完整路径\theme-toggle\Toggle-Theme.ps1"
   ```
3. 名称随意，比如「主题切换」。
4. 右键快捷方式 → 属性 → 快捷方式 → **更改图标** → 浏览到 `theme-toggle.ico`。
5. 同一个属性页的「快捷键」里可以按 `Ctrl + Alt + D`，以后直接键盘触发。

想改配色或线条粗细，改 `New-ShortcutIcon.ps1` 顶部的四个颜色变量和线宽系数，然后重跑：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\New-ShortcutIcon.ps1 -Preview
```


## 用法

**启动**：双击 `Start-ThemeTray.vbs`，图标出现在右下角（可能被折叠进 `^` 里，拖出来固定住）。

- **左键单击**：切到另一套状态（当前命中哪套，就切到另一套）。
- **右键菜单**：
  - 切换到「浅色」/ 切换到「深色」（当前那套会打勾）
  - 重新载入 settings.json
  - 编辑 settings.json（用记事本打开）
  - 退出

**命令行**（不常驻，可配桌面快捷方式或热键）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-Theme.ps1              # 切到另一套
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-Theme.ps1 -Preset sun   # 直接指定
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-Theme.ps1 -Status      # 看当前状态
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Toggle-Theme.ps1 -DryRun      # 只打印将写入的值
```

`-DryRun` 特别适合改完 `settings.json` 之后先确认一遍数值，再实际切换。

**开机自启**：给 `Start-ThemeTray.vbs` 建快捷方式，丢进
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`。

## 怎么关掉它

1. **右键图标 → 退出**（图标可能被折叠在 `^` 面板里）。
2. **双击 `Stop-ThemeTray.vbs`**：静默关闭，不需要先找到图标。它按 `ThemeTray.pid` 精确定位进程并校验启动时间，不会误杀别的 PowerShell。
3. **任务管理器 → 详细信息 → `powershell.exe`**，结束命令行里带 `ThemeTray.ps1` 的那个。

关掉的只是入口，当前深浅色设置保持原样；再开就重新双击 `Start-ThemeTray.vbs`。

## 实现细节

- **图标**：取 `Segoe MDL2 Assets` 的线条字形（`U+E706` 太阳 / `U+E708` 月牙），单色描边，16/20/24/32/40/48 六档多尺寸 ICO，高 DPI 不糊；32px 以下先按 4 倍分辨率渲染再降采样。
- **图标颜色只看任务栏**：任务栏深色画白色，浅色画深灰。这样「系统常驻深色 + 太阳图标」不会变成深色任务栏上的深灰太阳。
- **状态判定**：当前注册表值同时匹配某套预设才算「命中」；两套都不匹配时，图标按应用模式退化显示，提示文字写「未匹配预设」。
- **防连点**：300ms 内的重复点击直接丢弃。计时用的是 `DateTime.Ticks`——`Environment.TickCount64` 在 .NET Framework 下取到 `$null`，会让判断恒真、点击全部失效。
- **异常兜底**：回调里的异常不再弹 .NET 崩溃框，而是写进 `ThemeTray.error.log`；托盘每 2 秒同步一次真实状态。

## 已知边界

- 资源管理器、任务栏、开始菜单、UWP 应用通常立刻跟随；浏览器、VS Code、终端等各自缓存主题，需要重启才生效（与手动改设置的表现一致）。
- 任务栏偶发不刷新时，重启一次 `explorer.exe` 即可。
- 「通知区域的快速操作磁贴」无法添加自定义按钮，这是系统限制，所以用托盘图标实现。

### 启动托盘的快捷方式（推荐）

双击 `Create-Shortcut.cmd`，会在当前文件夹生成 `Start-ThemeTray.lnk`，图标使用同目录的 `theme-toggle.ico`。双击这个快捷方式即可静默启动托盘；也可以把它复制到桌面。

上传 GitHub 时保留 `Create-Shortcut.cmd`、`Create-Shortcut.ps1` 和图标即可。`.lnk` 包含本机绝对路径，不建议提交；其他人下载后双击 `Create-Shortcut.cmd` 重新生成即可。移动文件夹后也请重新生成，并替换之前复制到桌面的快捷方式。
