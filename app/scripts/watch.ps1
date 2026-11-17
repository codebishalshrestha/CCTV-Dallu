<#
  Office CCTV Viewer - second-screen watcher.

  Runs quietly in the background. It
    1. keeps go2rtc (the streaming engine) running,
    2. waits until a second display is connected,
    3. opens the camera wall full screen on that display,
    4. closes the wall again if the second display is switched off or unplugged.

  Start it with the "Office CCTV" startup shortcut, or run:  powershell -File watch.ps1
  Use -Once to do a single check and exit (handy for testing).
#>
param(
  [string]$Dir = (Split-Path -Parent $MyInvocation.MyCommand.Path),
  [switch]$Once
)

$ErrorActionPreference = 'Continue'
$Url      = 'http://localhost:1984/index.html?wall=1'
$ProfileDir = Join-Path $Dir 'browser-profile'
$LogFile  = Join-Path $Dir 'watch.log'

function Log([string]$text) {
  try {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $text
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    if ((Get-Item $LogFile).Length -gt 200KB) { $keep = @(Get-Content $LogFile -Tail 200); Set-Content -Path $LogFile -Value $keep -Encoding UTF8 }
  } catch { }
}

# Only one watcher at a time
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\OfficeCCTVWatch', [ref]$created)
if (-not $created) { exit 0 }

# Make this process aware of real screen pixels so positions on mixed-scale displays are right
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CctvWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(int x, int y, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
}
"@
try { [void][CctvWin]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch { try { [void][CctvWin]::SetProcessDPIAware() } catch { } }
Add-Type -AssemblyName System.Windows.Forms

function Test-Port([int]$Port) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $t = $c.ConnectAsync('127.0.0.1', $Port); return ($t.Wait(500) -and $c.Connected) }
  catch { return $false } finally { $c.Close() }
}

function Ensure-Go2rtc {
  if (Test-Port 1984) { return }
  $exe = Join-Path $Dir 'go2rtc.exe'
  if (-not (Test-Path $exe)) { Log 'go2rtc.exe not found'; return }
  Log 'Starting go2rtc'
  Start-Process -FilePath $exe -ArgumentList '-config', 'go2rtc.yaml' -WorkingDirectory $Dir -WindowStyle Hidden
  for ($i = 0; $i -lt 20; $i++) { if (Test-Port 1984) { return }; Start-Sleep -Milliseconds 500 }
}

function Get-Browser {
  foreach ($c in @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
    if ($c -and (Test-Path $c)) { return $c }
  }
  return $null
}

# The first display that is not the main one (null when there is only one display)
function Get-SecondScreen {
  $others = @([System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary })
  if ($others.Count -eq 0) { return $null }
  return $others[0]
}

# Our kiosk browser(s), found by their private profile folder
function Get-KioskProcesses {
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
      Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProfileDir) })
  } catch { return @() }
}

function Stop-Kiosk {
  foreach ($p in Get-KioskProcesses) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
}

function Start-Kiosk($screen) {
  $browser = Get-Browser
  if (-not $browser) { Log 'No Chrome or Edge found'; return $null }
  $b = $screen.Bounds
  $browserArgs = @(
    '--kiosk',
    "--user-data-dir=`"$ProfileDir`"",
    '--no-first-run', '--no-default-browser-check',
    '--disable-session-crashed-bubble', '--disable-infobars',
    '--autoplay-policy=no-user-gesture-required',
    '--noerrdialogs', '--disable-translate', '--overscroll-history-navigation=0',
    '--disable-features=CalculateNativeWinOcclusion,TranslateUI',
    "--window-position=$($b.X),$($b.Y)",
    "--window-size=$($b.Width),$($b.Height)"
  )
  if ($browser -like '*msedge.exe') { $browserArgs += '--edge-kiosk-type=fullscreen' }
  $browserArgs += $Url
  Log ("Opening wall on {0} at {1},{2} {3}x{4}" -f $screen.DeviceName, $b.X, $b.Y, $b.Width, $b.Height)
  return Start-Process -FilePath $browser -ArgumentList $browserArgs -PassThru
}

# Make sure the wall window really sits on the second display and covers it
function Place-Window($proc, $screen) {
  $b = $screen.Bounds
  $target = [CctvWin]::MonitorFromPoint($b.X + [int]($b.Width / 2), $b.Y + [int]($b.Height / 2), 2)
  $hwnd = [IntPtr]::Zero
  for ($i = 0; $i -lt 40; $i++) {
    try { $proc.Refresh(); $hwnd = $proc.MainWindowHandle } catch { }
    if ($hwnd -eq [IntPtr]::Zero) {
      foreach ($k in Get-KioskProcesses) {
        try { $h = (Get-Process -Id $k.ProcessId -ErrorAction Stop).MainWindowHandle; if ($h -ne [IntPtr]::Zero) { $hwnd = $h; break } } catch { }
      }
    }
    if ($hwnd -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 500
  }
  if ($hwnd -eq [IntPtr]::Zero) { Log 'Could not find the browser window to position'; return }
  Start-Sleep -Milliseconds 1500
  $now = [CctvWin]::MonitorFromWindow($hwnd, 2)
  if ($now -ne $target) {
    Log 'Window opened on the wrong display, moving it'
    [void][CctvWin]::ShowWindow($hwnd, 9)
    [void][CctvWin]::SetWindowPos($hwnd, [IntPtr]::Zero, $b.X, $b.Y, $b.Width, $b.Height, 0x0044)
  }
}

Log 'Watcher started'
Stop-Kiosk   # clear any leftover wall from before

$proc = $null
$lastPlaced = $null
while ($true) {
  try {
    Ensure-Go2rtc
    $screen = Get-SecondScreen
    $running = @(Get-KioskProcesses)
    if ($screen) {
      if ($running.Count -eq 0) {
        $proc = Start-Kiosk $screen
        if ($proc) { Place-Window $proc $screen }
      }
    } else {
      if ($running.Count -gt 0) { Log 'Second display gone, closing the wall'; Stop-Kiosk }
    }
  } catch { Log ("Error: " + $_.Exception.Message) }
  if ($Once) { break }
  Start-Sleep -Seconds 5
}
