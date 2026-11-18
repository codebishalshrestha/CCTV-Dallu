<#
  Office CCTV Viewer - uninstaller.
  Stops the viewer, removes the shortcuts and deletes the install folder (including your saved camera settings).
#>
[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'OfficeCCTV')
)
$ErrorActionPreference = 'Continue'

Write-Host ''
Write-Host '  Office CCTV Viewer - uninstall' -ForegroundColor White
$answer = Read-Host "  This removes $InstallDir and the shortcuts. Continue? [y/N]"
if (-not $answer.Trim().ToLower().StartsWith('y')) { Write-Host '  Cancelled.'; exit 0 }

$stop = Join-Path $InstallDir 'stop.ps1'
if (Test-Path $stop) { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $stop 2>$null | Out-Null }
Get-Process -Name go2rtc -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Programs'))) {
  $lnk = Join-Path $folder 'Office CCTV.lnk'
  if (Test-Path $lnk) { Remove-Item $lnk -Force }
}
Start-Sleep -Milliseconds 500
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
Write-Host '  Removed.' -ForegroundColor Green
