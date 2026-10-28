# 工作文件夹启动器

每天到公司后，双击 `Open-WorkFolders.cmd`。

脚本新建一个 File Explorer 窗口，按 `folders.txt` 中的顺序打开六个标签页。已有窗口和标签页保留。每次运行都会新建一个窗口，不会自动合并到上次的窗口。

## 文件与使用

- `Open-WorkFolders.cmd`：双击启动入口，调用系统自带 Windows PowerShell。
- `Open-WorkFolders.ps1`：实现脚本，包括路径检查、开窗、创建标签页和结果核对。
- `folders.txt`：文件夹列表，每行一个绝对路径。可以增删、调整顺序；空行和以 `#` 开头的行会忽略。

这几个文件应放在同一文件夹。可以整体移动到你喜欢的位置，并给 `Open-WorkFolders.cmd` 创建桌面快捷方式。快捷方式的“起始位置”不影响读取配置。

正常双击运行即可，不需要管理员权限，也不需要安装第三方软件。启动时会短暂显示命令窗口；成功后自动退出，失败时显示原因并等待按键。

运行约几秒钟，期间请暂时不要切换窗口或操作键盘鼠标。脚本需要把新建的 Explorer 窗口置于前台，以发送 `Ctrl+T` 创建标签页，然后通过 Windows Shell 接口设置路径；不使用剪贴板。最后一个标签页 `scripts` 会保持选中。

## 检查与故障

只检查路径，不打开窗口：

```powershell
.\Open-WorkFolders.cmd -CheckOnly
```

电脑较慢时，可以延长每一步的最长等待时间，例如 40 秒：

```powershell
.\Open-WorkFolders.cmd -TimeoutSeconds 40
```

- 要求支持 Explorer 标签页的 Windows 11（build 22621 或更新；较早的 22621 仍需安装标签页更新），并且 `Ctrl+T` 可用。
- 所有文件夹必须存在；缺失时在开窗前报错。
- 桌面需要解锁。启动期间丢失焦点、标签页创建失败或导航超时会停止并报错；已打开的部分窗口会保留，便于检查。再次运行会另开一个窗口。
- 同时启动的第二个实例会被阻止。
- 不修改文件夹内容、注册表、系统执行策略或开机启动配置。入口的 `-ExecutionPolicy Bypass` 仅作用于本次 PowerShell 进程；公司强制策略仍可能阻止执行。

## 本机验证

2026-10-28，已在本机 Windows build 26300.9711、Explorer 10.0.26100.8875、系统自带 Windows PowerShell 5.1 下执行双击入口对应的启动命令，验证：

- 配置中的六个路径均存在。
- 成功新建一个窗口，其六个标签页共享同一个窗口句柄。
- 六个标签页路径和顺序与配置一致。
- 原有 Explorer 窗口及其标签页保留。

标签页快捷键依据：[Microsoft Support — Keyboard shortcuts in Windows](https://support.microsoft.com/en-gb/accessibility/windows/keyboard-shortcuts-in-windows)。
