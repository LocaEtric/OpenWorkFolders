#Requires -Version 5.1
<#
Open the configured folders as tabs in one new File Explorer window.
Requires Windows 11 with Explorer tabs. Run in a normal interactive desktop
session, without administrator privileges. No clipboard or registry changes.
#>
[CmdletBinding()]
param(
    [string]$FolderList,
    [ValidateRange(5, 120)]
    [int]$TimeoutSeconds = 20,
    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mutex = $null
$lockTaken = $false

function Get-ExplorerTabs {
    # Explorer registers each tab separately, sharing the top-level HWND.
    foreach ($window in $script:shell.Windows()) {
        try {
            if ([IO.Path]::GetFileName($window.FullName) -ine 'explorer.exe') {
                continue
            }
            $pointer = [Runtime.InteropServices.Marshal]::GetIUnknownForObject($window)
            try { $key = $pointer.ToInt64() }
            finally { [void][Runtime.InteropServices.Marshal]::Release($pointer) }
            [pscustomobject]@{
                Handle = [long]$window.HWND
                Key = $key
                Browser = $window
            }
        }
        catch {
            # A tab may close while Shell.Windows is being enumerated.
            Write-Verbose $_.Exception.Message
        }
    }
}

function Wait-ExplorerCondition {
    param([scriptblock]$Probe, [string]$FailureMessage)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $result = & $Probe
        if ($null -ne $result) { return $result }
        Start-Sleep -Milliseconds 150
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw $FailureMessage
}

function Test-TabPath {
    param($Tab, [string]$ExpectedPath)
    try {
        $uri = [uri]$Tab.Browser.LocationURL
        return ($uri.IsFile -and
            $uri.LocalPath.TrimEnd('\') -ieq $ExpectedPath.TrimEnd('\'))
    }
    catch { return $false }
}

try {
    if ([string]::IsNullOrWhiteSpace($FolderList)) {
        $FolderList = Join-Path $PSScriptRoot 'folders.txt'
    }
    $build = [int](Get-ItemProperty -LiteralPath `
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    if ($build -lt 22621) {
        throw 'Windows 11 with File Explorer tabs is required (build 22621 or later).'
    }
    $folders = @(Get-Content -LiteralPath $FolderList -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($folders.Count -eq 0) { throw "No folders configured in $FolderList" }
    $missing = @($folders | Where-Object {
        -not [IO.Path]::IsPathRooted($_) -or
        -not (Test-Path -LiteralPath $_ -PathType Container)
    })
    if ($missing.Count -gt 0) {
        throw ("Folders must exist and use absolute paths:`n" + ($missing -join "`n"))
    }
    $folders = @($folders | ForEach-Object {
        (Get-Item -LiteralPath $_ -Force).FullName
    })
    if ($CheckOnly) {
        Write-Output "Validated $($folders.Count) folders (no windows opened):"
        $folders | Write-Output
        exit 0
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw 'Please use Open-WorkFolders.cmd (PowerShell must run with -STA).'
    }

    $mutex = New-Object Threading.Mutex($false, 'Local\Danisi.WorkFolderTabs')
    try { $lockTaken = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $lockTaken = $true }
    if (-not $lockTaken) { throw 'Another copy of this launcher is still running.' }

    Add-Type -AssemblyName System.Windows.Forms
    if (-not ('WorkFolders.NativeWindow' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace WorkFolders {
    public static class NativeWindow {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool ShowWindowAsync(IntPtr window, int command);
    }
}
'@
    }
    $script:shell = New-Object -ComObject Shell.Application
    $existingTabs = @(Get-ExplorerTabs)
    $existingHandles = @($existingTabs | ForEach-Object { $_.Handle })
    # /n requests a new window; verify that a new HWND actually appears.
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') `
        -ArgumentList ('/n,"{0}"' -f $folders[0])
    $firstTab = Wait-ExplorerCondition -Probe {
        Get-ExplorerTabs | Where-Object {
            $_.Handle -notin $existingHandles -and (Test-TabPath $_ $folders[0])
        } | Select-Object -First 1
    } -FailureMessage 'A new Explorer window did not appear. Try again with the desktop unlocked.'
    $targetHandle = $firstTab.Handle
    Write-Output "[1/$($folders.Count)] $($folders[0])"

    for ($i = 1; $i -lt $folders.Count; $i++) {
        $tabsBefore = @(Get-ExplorerTabs | Where-Object { $_.Handle -eq $targetHandle })
        $keysBefore = @($tabsBefore | ForEach-Object { $_.Key })
        [void][WorkFolders.NativeWindow]::ShowWindowAsync([IntPtr]$targetHandle, 9)
        [void][WorkFolders.NativeWindow]::SetForegroundWindow([IntPtr]$targetHandle)
        Start-Sleep -Milliseconds 250
        if ([WorkFolders.NativeWindow]::GetForegroundWindow().ToInt64() -ne $targetHandle) {
            throw 'Explorer lost focus. Stop using the keyboard/mouse briefly, then run again.'
        }
        # Ctrl+T is sent only to the verified foreground Explorer window.
        # Navigate2 then sets the new tab's folder without typing or clipboard use.
        [Windows.Forms.SendKeys]::SendWait('^t')
        $newTab = Wait-ExplorerCondition -Probe {
            Get-ExplorerTabs | Where-Object {
                $_.Handle -eq $targetHandle -and $_.Key -notin $keysBefore
            } | Select-Object -First 1
        } -FailureMessage 'Explorer did not create a new tab. Check that Ctrl+T works in Explorer.'
        $newTab.Browser.Navigate2($folders[$i])
        $null = Wait-ExplorerCondition -Probe {
            if (Test-TabPath $newTab $folders[$i]) { $true }
        } -FailureMessage "The new tab did not reach $($folders[$i])."
        Write-Output "[$($i + 1)/$($folders.Count)] $($folders[$i])"
    }

    $finalTabs = @(Get-ExplorerTabs | Where-Object { $_.Handle -eq $targetHandle })
    if ($finalTabs.Count -ne $folders.Count) {
        throw 'The final tab count does not match the folder list. Review the new window.'
    }
    foreach ($folder in $folders) {
        if (-not @($finalTabs | Where-Object { Test-TabPath $_ $folder }).Count) {
            throw "Final verification failed for $folder"
        }
    }
    Write-Output "Done: verified $($folders.Count) tabs in one new Explorer window."
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine('Any partially opened window is left open for inspection.')
    exit 1
}
finally {
    if ($lockTaken) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
