@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Open-WorkFolders.ps1" %*
if errorlevel 1 (
    echo.
    echo Opening work folders failed. See the message above.
    pause
    exit /b 1
)
