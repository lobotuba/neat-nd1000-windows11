<#
.SYNOPSIS
    Installs Neat Scan Utility 1.5.10 (the version this project was tested with) for the CURRENT user.
    Run this as the normal user, NOT as administrator: the installer is per-user and would
    otherwise install into the administrator account's profile.

    Downloads from Neat's own update server and verifies a pinned SHA-256.
    Optional: any other TWAIN app (e.g. NAPS2 in 32-bit TWAIN mode) works too.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$Url    = 'https://scissors-autoupdater.s3.amazonaws.com/1.5.10/ia32/NeatScanUtility.exe'
$Sha256 = 'F837470F94C0FB2FE4EBA8FD4EEA0E274632230B783ED2F8970BEC2DF08282C1'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin -and -not $Force) { throw 'Run this from a NON-elevated PowerShell (the installer is per-user). Use -Force to override.' }

$dir = Join-Path $env:TEMP 'NeatScanUtility'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$exe = Join-Path $dir 'NeatScanUtility-1.5.10.exe'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Write-Host "Downloading $Url"
Invoke-WebRequest -Uri $Url -OutFile $exe -UseBasicParsing
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
if ($hash -ne $Sha256) { throw "SHA-256 mismatch: got $hash, expected $Sha256" }
Write-Host 'Hash OK. Installing silently...'
$p = Start-Process -FilePath $exe -ArgumentList '/S' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Installer exited with code $($p.ExitCode)" }

$app = Join-Path $env:LOCALAPPDATA ('Programs\@theneatcompanyscissors\Neat' + [char]0x00AE + ' Scan Utility.exe')   # char 0xAE = registered-trademark sign; kept ASCII-safe for PowerShell 5.1
if (Test-Path $app) { Write-Host "Installed: $app`nStart it from the Start menu: 'Neat Scan Utility'." -ForegroundColor Green }
else { Write-Warning 'Installer finished but the app was not found at the expected path.' }
Write-Host 'Note: the app may auto-update itself (to 1.6.1+); the scanner driver is independent of the app version.'
