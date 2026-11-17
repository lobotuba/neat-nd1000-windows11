<#
.SYNOPSIS
    Removes the Neat ND-1000 driver package and Neat's driver MSI (undoes Install-NeatND1000.ps1).
    Does not touch Neat Scan Utility (uninstall that from Windows Settings > Apps).
    Needs administrator rights; re-launches itself elevated if necessary. Log: %TEMP%\NeatND1000-uninstall.log
#>
[CmdletBinding()]
param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
$ProductCode = '{A55F1206-BFA7-4027-92B8-CE4EFDBC3CF2}'   # "Neat ADF Scanner Driver" MSI (from the MSI log)
$LogPath = Join-Path $env:TEMP 'NeatND1000-uninstall.log'
function Log($m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -Path $LogPath -Value $l }
# Run a native tool, capture stdout+stderr as text, never throw on stderr output (Windows PowerShell 5.1 quirk).
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $text = & $Exe @Arguments 2>&1 | Out-String } finally { $ErrorActionPreference = $old }
    return $text.Trim()
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated') -Verb RunAs -Wait
    Write-Host "Finished. Log: $LogPath"
    exit 0
}

try {
    Log '=== Neat ND-1000 driver uninstall'
    # 1. driver package(s) in the driver store whose original INF name is NeatADFScanner.inf
    $text = Invoke-Native pnputil.exe @('/enum-drivers')
    $found = $false
    foreach ($m in [regex]::Matches($text, '(?im)Published Name:\s+(oem\d+\.inf)\s+Original Name:\s+neatadfscanner\.inf')) {
        $found = $true
        Log "Removing driver package $($m.Groups[1].Value)"
        Log (Invoke-Native pnputil.exe @('/delete-driver', $m.Groups[1].Value, '/uninstall', '/force'))
    }
    if (-not $found) { Log 'No Neat driver package found in the driver store.' }

    # 2. the MSI (files, TWAIN data sources, WIA DLLs)
    $p = Start-Process -FilePath msiexec.exe -ArgumentList @('/x', $ProductCode, '/qn', '/norestart') -Wait -PassThru
    Log "msiexec /x exit code $($p.ExitCode) (0 = removed, 1605 = was not installed, 3010 = removed, reboot pending)"
    Log 'Done.'
}
catch { Log "ERROR: $($_.Exception.Message)" }
finally { if ($Elevated) { Read-Host 'Press Enter to close this window' | Out-Null } }

