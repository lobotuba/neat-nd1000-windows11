<#
  One-line install (paste into PowerShell on the PC the scanner is attached to):

      irm https://raw.githubusercontent.com/lobotuba/neat-nd1000-windows11/main/bootstrap.ps1 | iex

  Downloads this repository as a ZIP from GitHub to %TEMP%, unpacks it and runs Install.ps1.
  Prefer to read the code first? Use "Code > Download ZIP" on GitHub instead and double-click Install.cmd.
#>
param([switch]$DownloadOnly)

$ErrorActionPreference = 'Stop'
$zipUrl = 'https://github.com/lobotuba/neat-nd1000-windows11/archive/refs/heads/main.zip'
$work   = Join-Path $env:TEMP 'neat-nd1000-windows11'
$zip    = "$work.zip"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
Write-Host "Downloading $zipUrl"
Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $work -Force
Remove-Item $zip -Force
$root = (Get-ChildItem $work -Directory | Select-Object -First 1).FullName
if (-not (Test-Path (Join-Path $root 'Install.ps1'))) { throw 'Downloaded archive does not contain Install.ps1' }
Write-Host "Unpacked to $root"
if ($DownloadOnly) { return }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Install.ps1')
