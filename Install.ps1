<#
.SYNOPSIS
    One-stop installer for the Neat ND-1000 scanner on Windows 10/11 x64.

.DESCRIPTION
    1. Installs Neat's official, Microsoft-signed driver (asks for administrator permission once).
    2. Optionally installs Neat Scan Utility (per-user, so it runs as you, not as administrator).
    3. Runs a self-test and tells you what to do next.

    Safe to re-run. Use scripts\Uninstall-NeatND1000.ps1 to remove.

.PARAMETER NoScanUtility
    Skip the Neat Scan Utility step (e.g. you will use NAPS2 or another TWAIN app).
.PARAMETER Yes
    Do not ask questions; install Neat Scan Utility too.
#>
[CmdletBinding()]
param([switch]$NoScanUtility, [switch]$Yes)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Step($n, $t) { Write-Host ''; Write-Host "[$n] $t" -ForegroundColor Cyan }

Say '=============================================' 'Cyan'
Say '  Neat ND-1000 installer for Windows 10/11'    'Cyan'
Say '=============================================' 'Cyan'

# Downloaded ZIPs carry a "from the internet" mark that can trigger prompts; clear it.
Get-ChildItem -Path $root -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# --- preflight --------------------------------------------------------------------------
if (-not [Environment]::Is64BitOperatingSystem) { Say 'This installer supports 64-bit Windows only.' 'Red'; exit 1 }
$dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID_1F44&PID_0050*' } | Select-Object -First 1
if ($dev) { Say "Scanner detected: $($dev.FriendlyName)" 'Green' }
else      { Say 'No ND-1000 detected right now. That is OK - the driver will be installed and the scanner will work as soon as you plug it in (USB, directly into the PC, powered on).' 'Yellow' }

# --- step 1: driver ---------------------------------------------------------------------
Step '1/3' 'Installing the scanner driver (a Windows permission prompt will appear - click Yes)'
$ps = (Get-Process -Id $PID).Path
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Install-NeatND1000.ps1')
$code = $LASTEXITCODE
if ($code -ne 0) {
    Say ''
    Say "Driver installation did not complete (exit code $code)." 'Red'
    Say 'Details: %TEMP%\NeatND1000-install.log   Help: docs\TROUBLESHOOTING.md' 'Red'
    exit $code
}
Say 'Driver installed.' 'Green'

# --- step 2: scanning app ---------------------------------------------------------------
Step '2/3' 'Scanning application'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($NoScanUtility) {
    Say 'Skipped (-NoScanUtility). Use any TWAIN app, see docs\INSTALL.md.'
} elseif ($isAdmin) {
    Say 'You started this as administrator, so Neat Scan Utility is skipped (it installs per user).' 'Yellow'
    Say 'Run scripts\Install-ScanUtility.ps1 from a normal (non-admin) window to add it.' 'Yellow'
} else {
    $go = $true
    if (-not $Yes) {
        $a = Read-Host 'Install Neat Scan Utility (the app that was tested with this scanner)? [Y/n]'
        $go = ($a -eq '' -or $a -match '^[Yy]')
    }
    if ($go) {
        try { & (Join-Path $root 'scripts\Install-ScanUtility.ps1') }
        catch { Say "Scan Utility install failed: $($_.Exception.Message)" 'Yellow'; Say 'The driver is fine; you can use another TWAIN app (docs\INSTALL.md).' 'Yellow' }
    } else { Say 'Skipped. Use any TWAIN app, see docs\INSTALL.md.' }
}

# --- step 3: self-test ------------------------------------------------------------------
Step '3/3' 'Self-test'
& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\Test-NeatND1000.ps1')
$testCode = $LASTEXITCODE

Write-Host ''
if ($testCode -eq 0) {
    Say 'ALL DONE.' 'Green'
    Say 'Put a page in the feeder, open "Neat Scan Utility" from the Start menu, choose the scanner and click Scan.' 'Green'
    Say 'Note: the built-in Windows "Scan" app does NOT work with this scanner (old WIA driver) - use Neat Scan Utility or NAPS2.' 'Yellow'
} else {
    Say 'The driver was installed, but the self-test reported a problem (see above).' 'Yellow'
    Say 'Most common fix: unplug the scanner, wait 10 seconds, plug it directly into the PC, then run scripts\Test-NeatND1000.ps1 again. More: docs\TROUBLESHOOTING.md' 'Yellow'
}
exit $testCode
