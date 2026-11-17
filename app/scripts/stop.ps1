<#
  Stops the Office CCTV viewer completely: the watcher, the wall window and go2rtc.
  Run it, then start again with the desktop icon or by signing out and in.
#>
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$profileDir = Join-Path $dir 'browser-profile'
$me = $PID

# Watcher first, so it does not reopen the wall
try {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -like '*watch.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }

# The wall window
try {
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$profileDir*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }

# The streaming engine
Get-Process -Name go2rtc -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Office CCTV stopped.'
