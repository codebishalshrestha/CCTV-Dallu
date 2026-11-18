<#
  Opens the camera wall in a normal window on this computer (the "Office CCTV" desktop icon).
  Starts go2rtc first if it is not running.
#>
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ver = try { (Get-Item (Join-Path $dir 'www\index.html')).LastWriteTime.Ticks } catch { 0 }
$url = "http://localhost:1984/index.html?v=$ver"

function Test-Port($port) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $t = $c.ConnectAsync('127.0.0.1', $port); return ($t.Wait(500) -and $c.Connected) } catch { return $false } finally { $c.Close() }
}

if (-not (Test-Port 1984)) {
  Start-Process -FilePath (Join-Path $dir 'go2rtc.exe') -ArgumentList '-config', 'go2rtc.yaml' -WorkingDirectory $dir -WindowStyle Hidden
  for ($i = 0; $i -lt 20; $i++) { if (Test-Port 1984) { break }; Start-Sleep -Milliseconds 500 }
}

$browser = $null
foreach ($c in @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
  if ($c -and (Test-Path $c)) { $browser = $c; break }
}
$profileDir = Join-Path $dir 'window-profile'
if ($browser) {
  Start-Process -FilePath $browser -ArgumentList @(
    "--app=$url", "--user-data-dir=`"$profileDir`"", '--no-first-run', '--no-default-browser-check',
    '--window-size=1280,760', '--autoplay-policy=no-user-gesture-required', '--disable-features=CalculateNativeWinOcclusion')
} else { Start-Process $url }
