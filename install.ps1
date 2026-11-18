<#
  Office CCTV Viewer - installer
  Windows 10/11, Windows PowerShell 5.1 or newer.

  Normally you run this by double-clicking install.bat.
  Optional parameters let you run it without questions:
    .\install.ps1 -Ip 192.168.1.100 -User admin -Password "secret" -Channels 16 -AutoStart
#>
[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'OfficeCCTV'),
  [string]$Ip,
  [string]$User = 'admin',
  [string]$Password,
  [int]$Channels = 0,
  [switch]$AutoStart,
  [switch]$NoAutoStart,
  [switch]$NoShortcut,
  [switch]$Reconfigure,
  [switch]$Window,   # show the cameras in a normal window on this PC
  [switch]$Tv        # show the cameras full screen on the second display (TV)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# go2rtc is the small open-source (MIT) program that turns the recorder's streams into something a browser can play.
$Go2rtcVersion = '1.9.15'
$Go2rtcUrl     = "https://github.com/AlexxIT/go2rtc/releases/download/v$Go2rtcVersion/go2rtc_win64.zip"
$Go2rtcSha256  = '5b448fc90f15c925406d8da0984301985e385050222c1c2bbdf0a76fe4b1e9cb'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PS   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Write-Step($text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "   OK  $text" -ForegroundColor Green }
function Write-Warn2($text){ Write-Host "   !!  $text" -ForegroundColor Yellow }

function Ask-YesNo([string]$question, [bool]$default = $false) {
  $hint = if ($default) { 'Y/n' } else { 'y/N' }
  $answer = Read-Host "$question [$hint]"
  if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
  return $answer.Trim().ToLower().StartsWith('y')
}

# Build the go2rtc.yaml text. Passwords are URL-encoded so characters like @ # / : do not break the link.
function New-Go2rtcConfig([string]$RecorderIp, [string]$UserName, [string]$Pass, [int]$ChannelCount) {
  $u = [Uri]::EscapeDataString($UserName)
  $p = [Uri]::EscapeDataString($Pass)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('# Office CCTV Viewer configuration. Created by install.ps1.')
  $lines.Add('# This file holds your recorder password. Do not share it or upload it anywhere.')
  $lines.Add('# Delete the camN lines for channels that have no camera.')
  $lines.Add('')
  $lines.Add('api:')
  $lines.Add('  listen: "127.0.0.1:1984"')
  $lines.Add('  static_dir: www')
  $lines.Add('')
  $lines.Add('# Only this computer needs these; keeping them local avoids Windows firewall prompts.')
  $lines.Add('rtsp:')
  $lines.Add('  listen: "127.0.0.1:8554"')
  $lines.Add('webrtc:')
  $lines.Add('  listen: "127.0.0.1:8555"')
  $lines.Add('')
  $lines.Add('streams:')
  for ($i = 1; $i -le $ChannelCount; $i++) {
    $base = ("rtsp://${u}:${p}@${RecorderIp}:554/cam/realmonitor?channel=$i").Replace("'", "''")
    $lines.Add("  cam${i}: '$base&subtype=1'")
  }
  $lines.Add('  # Full-quality (main) streams')
  for ($i = 1; $i -le $ChannelCount; $i++) {
    $base = ("rtsp://${u}:${p}@${RecorderIp}:554/cam/realmonitor?channel=$i").Replace("'", "''")
    $lines.Add("  cam${i}_hd: '$base&subtype=0'")
  }
  return ($lines -join "`r`n") + "`r`n"
}

# Look for Dahua devices on the local network (they listen on port 37777).
function Find-DahuaDevices {
  $found = @()
  try {
    $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if (-not $cfg) { return $found }
    $mine = $cfg.IPv4Address[0].IPAddress
    $prefix = ($mine -split '\.')[0..2] -join '.'
    $probes = @()
    foreach ($n in 1..254) {
      $addr = "$prefix.$n"
      $client = New-Object System.Net.Sockets.TcpClient
      $probes += [pscustomobject]@{ Ip = $addr; Client = $client; Task = $client.ConnectAsync($addr, 37777) }
    }
    Start-Sleep -Milliseconds 2000
    foreach ($pr in $probes) {
      if ($pr.Task.IsCompleted -and -not $pr.Task.IsFaulted -and -not $pr.Task.IsCanceled -and $pr.Client.Connected) { $found += $pr.Ip }
    }
    foreach ($pr in $probes) { try { $pr.Client.Close() } catch {} }
  } catch { }
  return $found
}

function Test-TcpPort([string]$HostName, [int]$Port, [int]$TimeoutMs = 3000) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $task = $client.ConnectAsync($HostName, $Port)
    return ($task.Wait($TimeoutMs) -and $client.Connected)
  } catch { return $false } finally { $client.Close() }
}

function Plain-FromSecure($secure) {
  $cred = New-Object System.Net.NetworkCredential('', $secure)
  return $cred.Password
}

Write-Host ''
Write-Host '  Office CCTV Viewer - installer' -ForegroundColor White
Write-Host '  -------------------------------'

try {
  # ---- 1. Check the computer --------------------------------------------------------------
  Write-Step '1/5  Checking this computer'
  if ($env:OS -ne 'Windows_NT') { throw 'This installer is for Windows.' }
  if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Windows PowerShell 5 or newer is required.' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Write-Ok "Windows with PowerShell $($PSVersionTable.PSVersion)"

  $browser = $null
  foreach ($c in @(
      "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
      "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
      "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
    if ($c -and (Test-Path $c)) { $browser = $c; break }
  }
  if ($browser) { Write-Ok "Browser found: $(Split-Path -Leaf $browser)" }
  else { Write-Warn2 'Chrome or Edge not found. Install Chrome or Edge, then run this installer again.' }

  # ---- 2. Copy the viewer ----------------------------------------------------------------
  Write-Step "2/5  Removing any previous copy, then installing to $InstallDir"
  $srcWww = Join-Path $Root 'app\www'
  $srcScripts = Join-Path $Root 'app\scripts'
  if (-not (Test-Path (Join-Path $srcWww 'index.html'))) { throw "Viewer files not found in $srcWww. Extract the whole ZIP first, then run install.bat." }

  # a) Stop everything that belongs to an older copy: the watcher, the wall window, and every go2rtc
  #    (including one started by hand from another folder, which would hold port 1984 and serve old files).
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
      Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and ($_.CommandLine.Contains('watch.ps1') -or $_.CommandLine.Contains('launch.ps1')) } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  try {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
      Where-Object { $_.CommandLine -and $_.CommandLine.Contains('OfficeCCTV') } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  $oldEngines = @(Get-Process -Name go2rtc -ErrorAction SilentlyContinue)
  if ($oldEngines.Count -gt 0) { $oldEngines | Stop-Process -Force -ErrorAction SilentlyContinue; Write-Ok "Stopped $($oldEngines.Count) running go2rtc" }
  Start-Sleep -Milliseconds 1500
  if (Test-TcpPort '127.0.0.1' 1984 1000) { Write-Warn2 'Something else is still using port 1984. Close it (or restart the PC) if the viewer does not open.' }

  # b) Remove old shortcuts
  foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
    foreach ($n in @('Office CCTV.lnk', 'CCTV.lnk')) {
      $lnk = Join-Path $folder $n
      if (Test-Path $lnk) { Remove-Item $lnk -Force -ErrorAction SilentlyContinue }
    }
  }

  # c) Delete the old install folder (old page, scripts, go2rtc, browser profile with old saved settings),
  #    keeping only the camera settings so you are not asked again
  $savedCfg = $null
  $oldCfg = Join-Path $InstallDir 'go2rtc.yaml'
  if (Test-Path $oldCfg) { $savedCfg = [IO.File]::ReadAllText($oldCfg) }
  if (Test-Path $InstallDir) {
    for ($try = 0; $try -lt 5 -and (Test-Path $InstallDir); $try++) {
      Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
      if (Test-Path $InstallDir) { Start-Sleep -Seconds 1 }
    }
    if (Test-Path $InstallDir) { throw "Could not remove the old copy in $InstallDir (a file is still in use). Restart the PC and run install.bat again." }
    Write-Ok 'Previous installation removed'
  }

  # d) Fresh copy
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  if ($savedCfg) { [IO.File]::WriteAllText($oldCfg, $savedCfg, (New-Object System.Text.UTF8Encoding($false))) }
  $dstWww = Join-Path $InstallDir 'www'
  New-Item -ItemType Directory -Force -Path $dstWww | Out-Null
  Copy-Item -Path (Join-Path $srcWww '*') -Destination $dstWww -Recurse -Force
  Copy-Item -Path (Join-Path $srcScripts '*.ps1') -Destination $InstallDir -Force
  $srcIcon = Join-Path $Root 'app\cctv.ico'
  if (Test-Path $srcIcon) { Copy-Item $srcIcon (Join-Path $InstallDir 'cctv.ico') -Force }
  Get-ChildItem $InstallDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
  Write-Ok 'Viewer page and launcher installed'

  # ---- 3. Download go2rtc ----------------------------------------------------------------
  Write-Step "3/5  Getting go2rtc $Go2rtcVersion (the streaming engine)"
  $exe = Join-Path $InstallDir 'go2rtc.exe'
  if (Test-Path $exe) {
    Write-Ok 'go2rtc already installed'
  } else {
    $zip = Join-Path ([IO.Path]::GetTempPath()) "go2rtc_$Go2rtcVersion.zip"
    Write-Host '   Downloading (about 8 MB)...'
    try { Invoke-WebRequest -Uri $Go2rtcUrl -OutFile $zip -UseBasicParsing }
    catch { throw "Could not download go2rtc. Check your internet connection, or download $Go2rtcUrl yourself, extract go2rtc.exe into $InstallDir and run this installer again." }
    $hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $Go2rtcSha256) { Remove-Item $zip -Force; throw 'The downloaded go2rtc file did not match the expected checksum, so it was not installed.' }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "go2rtc_$Go2rtcVersion"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    Copy-Item -Path (Join-Path $tmp 'go2rtc.exe') -Destination $exe -Force
    Unblock-File -Path $exe -ErrorAction SilentlyContinue
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok 'go2rtc downloaded and verified'
  }

  # ---- 4. Camera settings ----------------------------------------------------------------
  Write-Step '4/5  Camera settings'
  $cfgPath = Join-Path $InstallDir 'go2rtc.yaml'
  $bundled = Join-Path $Root 'go2rtc.yaml'
  $Prefilled = Test-Path $bundled
  if ($Prefilled -and -not $Reconfigure) {
    Copy-Item $bundled $cfgPath -Force
    Write-Ok 'Camera settings found next to the installer and applied (no questions needed)'
  } elseif ((Test-Path $cfgPath) -and -not $Reconfigure) {
    Write-Ok 'Keeping your existing camera settings (run install.bat -Reconfigure to change them)'
  } else {
    if ([string]::IsNullOrWhiteSpace($Ip)) {
      Write-Host '   Looking for Dahua recorders and cameras on your network (a few seconds)...'
      $devices = @(Find-DahuaDevices)
      if ($devices.Count -gt 0) {
        Write-Host '   Found these Dahua devices:'
        for ($i = 0; $i -lt $devices.Count; $i++) { Write-Host ("     [{0}] {1}" -f ($i + 1), $devices[$i]) }
        Write-Host '   The recorder (NVR/DVR/XVR) is the one that has all the camera channels. If unsure, pick one;'
        Write-Host '   you can run the installer again to change it.'
        $pick = Read-Host '   Type the number, or type the recorder IP address yourself'
        if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $devices.Count) { $Ip = $devices[[int]$pick - 1] }
        else { $Ip = $pick.Trim() }
      } else {
        Write-Warn2 'No Dahua devices found automatically.'
        $Ip = (Read-Host '   Recorder IP address (for example 192.168.1.100)').Trim()
      }
    }
    if ($Ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "'$Ip' is not a valid IP address (it should look like 192.168.1.100)." }

    if ($PSBoundParameters.ContainsKey('User') -eq $false) {
      $u = Read-Host '   Recorder username [admin]'
      if (-not [string]::IsNullOrWhiteSpace($u)) { $User = $u.Trim() }
    }
    if ([string]::IsNullOrEmpty($Password)) {
      $secure = Read-Host '   Recorder password (typing is hidden; you only enter it once, here)' -AsSecureString
      $Password = Plain-FromSecure $secure
    }
    if ([string]::IsNullOrEmpty($Password)) { throw 'A password is required.' }

    if ($Channels -le 0) {
      $ch = Read-Host '   How many camera channels does the recorder have? [16]'
      if ([string]::IsNullOrWhiteSpace($ch)) { $Channels = 16 }
      elseif ($ch -match '^\d+$') { $Channels = [int]$ch }
      else { throw 'Please enter a number, for example 16.' }
    }
    if ($Channels -lt 1 -or $Channels -gt 64) { throw 'Channels must be between 1 and 64.' }

    if (Test-TcpPort $Ip 554) { Write-Ok "Recorder reachable at $Ip" }
    else { Write-Warn2 "Could not reach $Ip on port 554. Check the IP and that this computer is on the same network. Continuing anyway." }

    $yaml = New-Go2rtcConfig -RecorderIp $Ip -UserName $User -Pass $Password -ChannelCount $Channels
    [IO.File]::WriteAllText($cfgPath, $yaml, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok 'Camera settings saved'
  }

  # ---- 5. Shortcuts and automatic start --------------------------------------------------
  Write-Step '5/5  How to show the cameras on this PC'
  $launchPs = Join-Path $InstallDir 'launch.ps1'
  $watchPs  = Join-Path $InstallDir 'watch.ps1'
  $icon     = Join-Path $InstallDir 'cctv.ico'
  $shell = New-Object -ComObject WScript.Shell
  $startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Office CCTV.lnk'
  $menuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'Office CCTV.lnk'

  function New-Link($path, $script, $desc) {
    $l = $shell.CreateShortcut($path)
    $l.TargetPath = $PS
    $l.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    $l.WorkingDirectory = $InstallDir
    if (Test-Path $icon) { $l.IconLocation = "$icon,0" } elseif ($browser) { $l.IconLocation = "$browser,0" }
    $l.Description = $desc
    $l.Save()
  }

  # Mode: TV = full screen on the second display, opens by itself. Window = normal window with a desktop icon.
  if ($Tv) { $mode = 'tv' }
  elseif ($Window -or $NoAutoStart) { $mode = 'window' }
  elseif ($AutoStart) { $mode = 'tv' }
  else {
    Write-Host '   [1] In a window on this PC (desktop icon, you open it when you want)'
    Write-Host '   [2] Full screen on the second display / TV, opens by itself when the PC starts'
    $pick = Read-Host '   Choose 1 or 2 [1]'
    $mode = if ($pick.Trim() -eq '2') { 'tv' } else { 'window' }
  }

  if (-not $NoShortcut) {
    New-Link (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Office CCTV.lnk') $launchPs 'Open the Office CCTV cameras in a window'
    New-Link $menuLnk $launchPs 'Open the Office CCTV cameras in a window'
    Write-Ok "Desktop and Start menu icon created: Office CCTV"
  }

  if ($mode -eq 'tv') {
    New-Link $startupLnk $watchPs 'Office CCTV: show the cameras on the second display'
    Write-Ok 'TV mode: the cameras open full screen on the second display whenever one is connected'
  } else {
    if (Test-Path $startupLnk) { Remove-Item $startupLnk -Force }
    Write-Ok 'Window mode: nothing opens by itself; use the Office CCTV icon'
  }

  Write-Host ''
  Write-Host '  Installed.' -ForegroundColor Green
  if ($mode -eq 'tv') {
    Write-Host '  - The cameras open by themselves full screen on the second display after you sign in.'
    Write-Host '  - Close the TV wall: Alt+F4 (it reopens). Stop it completely: run stop.ps1 in the install folder.'
    Write-Host '  - After a restart or power cut with nobody at the PC: set Windows to sign in automatically'
    Write-Host '    (Win+R, netplwiz, untick "Users must enter a user name and password").'
    Write-Host '  - Display mode must be Extend (Win+P), not Duplicate.'
    Start-Process -FilePath $PS -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchPs`""
  } else {
    Write-Host "  - Open the cameras with the 'Office CCTV' icon on the desktop or in the Start menu."
    Write-Host '  - To switch this PC to TV mode later: install.bat -Tv'
    Start-Process -FilePath $PS -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launchPs`""
  }
}
catch {
  Write-Host ''
  Write-Host "  Setup stopped: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host '  Fix the problem above and run install.bat again.'
  exit 1
}
