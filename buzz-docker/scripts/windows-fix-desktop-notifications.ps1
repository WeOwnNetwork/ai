#Requires -Version 5.1
<#
.SYNOPSIS
  Standard Windows fix for Buzz Desktop DM / @mention toasts.

.DESCRIPTION
  Installs a silent launcher so every Start Menu / Desktop / Startup Buzz
  shortcut opens the real app with the Windows false-denial workaround
  (block/buzz#2445). Does NOT fire test toasts.

  Run once per Windows machine (no admin required):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-fix-desktop-notifications.ps1

  Then always open Buzz from Start Menu or the Desktop shortcut.
#>
param(
    [switch]$Launch
)
$ErrorActionPreference = 'Stop'

$RepoScriptDir = $PSScriptRoot
$BuzzDir = Join-Path $env:LOCALAPPDATA 'Buzz'
$BuzzExe = Join-Path $BuzzDir 'buzz-desktop.exe'
$InstallPy = Join-Path $BuzzDir 'weown-buzz-notif-fix.py'
$InstallPs1 = Join-Path $BuzzDir 'weown-buzz-notif-fix.ps1'
$InstallCmd = Join-Path $BuzzDir 'weown-buzz-notif-fix.cmd'
$LogFile = Join-Path $BuzzDir 'weown-buzz-notif-fix.log'
$OldWatchdogPid = Join-Path $BuzzDir 'notif-watchdog.pid'

function Log([string]$Msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

if (-not (Test-Path $BuzzExe)) {
    throw "Buzz Desktop not found at $BuzzExe. Install Buzz first."
}

New-Item -ItemType Directory -Force -Path $BuzzDir | Out-Null

$srcPy = Join-Path $RepoScriptDir 'windows-fix-desktop-notifications.py'
if (Test-Path $srcPy) {
    Copy-Item $srcPy $InstallPy -Force
} elseif (Test-Path $InstallPy) {
    Log 'Using already-installed Python repair script.'
} else {
    throw "Missing $srcPy. Run this from the repo copy under buzz-docker/scripts/."
}

if (-not $Launch -or $PSCommandPath -ne $InstallPs1) {
    Copy-Item $PSCommandPath $InstallPs1 -Force
}

if (-not (Test-Path $InstallCmd)) {
    @(
        '@echo off'
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\Buzz\weown-buzz-notif-fix.ps1" -Launch'
    ) | Set-Content -Path $InstallCmd -Encoding ASCII
}

$toastKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\xyz.block.buzz.app'
New-Item -Path $toastKey -Force | Out-Null
New-ItemProperty -Path $toastKey -Name Enabled -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $toastKey -Name ShowInActionCenter -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name ToastEnabled -Value 1 -PropertyType DWord -Force | Out-Null

if (-not $Launch) {
    @(
        '@echo off'
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\Buzz\weown-buzz-notif-fix.ps1" -Launch'
    ) | Set-Content -Path $InstallCmd -Encoding ASCII

    $w = New-Object -ComObject WScript.Shell
    $icon = "$BuzzExe,0"
    $shortcutPaths = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Buzz.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\Buzz.lnk'),
        (Join-Path $env:USERPROFILE 'Desktop\Buzz.lnk')
    )
    $legacyFix = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Buzz (fix notifications).lnk'
    if (Test-Path $legacyFix) { Remove-Item $legacyFix -Force }

    foreach ($p in $shortcutPaths) {
        $dir = Split-Path $p
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $s = $w.CreateShortcut($p)
        $s.TargetPath = $InstallCmd
        $s.WorkingDirectory = $BuzzDir
        $s.WindowStyle = 7
        $s.Description = 'Buzz Desktop (WeOwn Windows notification fix)'
        $s.IconLocation = $icon
        $s.Save()
        Log "Shortcut -> $p"
    }
}

# Stop the old CDP toast-spamming watchdog
if (Test-Path $OldWatchdogPid) {
    $old = Get-Content $OldWatchdogPid -ErrorAction SilentlyContinue
    if ($old) { Stop-Process -Id ([int]$old) -Force -ErrorAction SilentlyContinue }
    Remove-Item $OldWatchdogPid -Force -ErrorAction SilentlyContinue
}
Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'notif-repair\.py|weown-buzz-notif-fix\.py' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-Process buzz-desktop -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1

$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222 --remote-allow-origins=http://127.0.0.1:9222'
Start-Process -FilePath $BuzzExe -WorkingDirectory $BuzzDir
Log 'Buzz launched'

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python is required on PATH (python or py).' }

Log 'Applying silent interceptor (no test toasts)...'
& $py.Source $InstallPy 2>&1 | ForEach-Object { Log "$_" }

Log 'Done. Open Buzz from Start Menu / Desktop. Ask someone to DM or @mention you while Buzz is in the background.'
Log 'Settings -> Notifications -> Desktop alerts must stay ON. Do not start buzz-desktop.exe directly.'
