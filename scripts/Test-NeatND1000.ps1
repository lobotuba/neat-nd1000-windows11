<#
.SYNOPSIS
    Checks that the Neat ND-1000 is correctly installed. Does NOT need admin and does not scan.
    Checks: device + driver binding, installed driver files, WIA enumeration, and that the
    32-bit TWAIN data source (what Neat Scan Utility uses) can actually be opened.

.EXAMPLE
    .\Test-NeatND1000.ps1
#>
$ErrorActionPreference = 'Continue'
$results = New-Object System.Collections.Generic.List[object]
function Check($name, [bool]$ok, $detail) { $results.Add([pscustomobject]@{ Check = $name; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $detail }) }

# 1. device + binding
$dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USB\VID_1F44&PID_0050*' } | Select-Object -First 1
if (-not $dev) {
    Check 'Scanner connected (USB VID_1F44 PID_0050)' $false 'not found - plug it in directly (no hub), check power and cable'
} else {
    $prob = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_ProblemCode).Data
    Check 'Scanner connected (USB VID_1F44 PID_0050)' $true $dev.InstanceId
    Check 'Driver bound (class Image, no problem code)' ($dev.Class -eq 'Image' -and $prob -eq 0) "class=[$($dev.Class)] status=$($dev.Status) problemCode=$prob"
}

# 2. files
$files = @(
    (Join-Path $env:CommonProgramW6432 'The Neat Company\Drivers\Neat ADF Scanner\NeatADFScanner.inf'),
    "$env:windir\twain_32\Neat ADF Scanner\NeatADFScanner32.ds",
    "$env:windir\twain_64\Neat ADF Scanner\NeatADFScanner64.ds",
    "$env:windir\System32\NeatADFScannerWIA64.dll")
foreach ($f in $files) { Check "File present: $(Split-Path $f -Leaf)" (Test-Path $f) $f }

# 3. WIA
try {
    $dm = New-Object -ComObject WIA.DeviceManager
    $names = @(foreach ($i in $dm.DeviceInfos) { ($i.Properties | Where-Object Name -eq 'Name').Value })
    Check 'WIA lists the scanner' ($names -contains 'Neat ADF Scanner') ("WIA devices: " + ($names -join ', '))
} catch { Check 'WIA lists the scanner' $false $_.Exception.Message }

# 4. TWAIN (32-bit host, like Neat Scan Utility)
$ps32 = "$env:windir\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
$twainTest = Join-Path $PSScriptRoot '..\tools\Test-TwainSource.ps1'
if ((Test-Path $ps32) -and (Test-Path $twainTest)) {
    $o = & $ps32 -NoProfile -ExecutionPolicy Bypass -File $twainTest 2>&1 | Out-String
    Check 'TWAIN data source opens (32-bit)' ($o -match "OPENDS\('Neat ADF Scanner'\) -> SUCCESS") (($o -split "`r?`n" | Where-Object { $_ -match 'OPENDS|source:' }) -join ' | ')
} else { Check 'TWAIN data source opens (32-bit)' $false 'tools\Test-TwainSource.ps1 or 32-bit PowerShell not found' }

$results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
if ($results.Result -contains 'FAIL') { Write-Host 'Some checks FAILED - see docs/TROUBLESHOOTING.md' -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed. Scan with a TWAIN app (Neat Scan Utility, NAPS2 in 32-bit TWAIN mode).' -ForegroundColor Green
