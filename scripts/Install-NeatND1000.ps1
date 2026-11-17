<#
.SYNOPSIS
    Installs Neat's official 64-bit scanner driver for the Neat ND-1000 (also NC-1000 / NM-1000)
    on Windows 10/11 x64 and makes sure it is actually bound to the scanner.

.DESCRIPTION
    Why two steps (see docs/DIAGNOSIS.md):
      1. Run Neat's MSI. It copies the driver files to
         "C:\Program Files\Common Files\The Neat Company\Drivers\Neat ADF Scanner\".
         On current Windows its DIFxApp step installs the driver INF and then immediately
         uninstalls it again, leaving the scanner without a driver.
      2. Install the Microsoft-signed INF directly with pnputil and restart the device.

    The MSI is downloaded from Neat's own server and verified against a pinned SHA-256.
    Nothing from Neat is redistributed by this repository.

    Needs administrator rights; re-launches itself elevated (UAC prompt) if necessary.
    Log: %TEMP%\NeatND1000-install.log

.PARAMETER MsiPath
    Use an already-downloaded MSI instead of downloading it.
.PARAMETER Force
    Continue even if the MSI's SHA-256 differs from the pinned (tested) value.

.EXAMPLE
    .\Install-NeatND1000.ps1
#>
[CmdletBinding()]
param(
    [string]$MsiPath,
    [switch]$Force,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

$MsiUrl     = 'https://s3.amazonaws.com/scanner-drivers/Windows/NeatDesk/x64/Scanner.Install64.Neat.ADF.MSI.msi'
$MsiSha256  = 'E5BF0BA736298BD41C3DF0283732EC539E8311C80098B677CC50C62453888843'
$HardwareId = 'USB\VID_1F44&PID_0050'
$DriverDir  = Join-Path $env:CommonProgramW6432 'The Neat Company\Drivers\Neat ADF Scanner'
$InfPath    = Join-Path $DriverDir 'NeatADFScanner.inf'
$CatPath    = Join-Path $DriverDir 'neatadfscanner.cat'
$LogPath    = Join-Path $env:TEMP 'NeatND1000-install.log'

function Log($m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -Path $LogPath -Value $l }
# Run a native tool, capture stdout+stderr as text, never throw on stderr output (Windows PowerShell 5.1 quirk).
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $text = & $Exe @Arguments 2>&1 | Out-String } finally { $ErrorActionPreference = $old }
    return $text.Trim()
}

# --- elevate ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated')
    if ($MsiPath) { $a += @('-MsiPath', "`"$MsiPath`"") }
    if ($Force)   { $a += '-Force' }
    try {
        $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $a -Verb RunAs -Wait -PassThru
    } catch {
        Write-Host 'Administrator permission was declined (or could not be requested). The driver cannot be installed without it.' -ForegroundColor Red
        exit 2
    }
    Write-Host "Elevated installer finished with exit code $($child.ExitCode). Log: $LogPath"
    exit $child.ExitCode
}

$failed = $false
try {
    Log '=== Neat ND-1000 driver install'

    # --- preflight ---------------------------------------------------------------------
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'This driver package is 64-bit only; 32-bit Windows is not supported by this script.' }
    $build = [Environment]::OSVersion.Version.Build
    Log "Windows build $build"
    if ($build -lt 19041) { throw "Windows 10 2004 (build 19041) or newer required; found build $build." }

    # --- obtain + verify the MSI -------------------------------------------------------
    if (-not $MsiPath) {
        $dir = Join-Path $env:TEMP 'NeatND1000'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $MsiPath = Join-Path $dir 'Scanner.Install64.Neat.ADF.MSI.msi'
        Log "Downloading $MsiUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $ok = $false
        foreach ($try in 1..3) {
            try { Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath -UseBasicParsing -TimeoutSec 120; $ok = $true; break }
            catch { Log "Download attempt $try failed: $($_.Exception.Message)"; Start-Sleep -Seconds (3 * $try) }
        }
        if (-not $ok) { throw "Could not download the Neat driver. Check your internet connection / proxy, or download it manually from Neat's driver page and re-run with -MsiPath <file>. See docs/INSTALL.md." }
    }
    if (-not (Test-Path $MsiPath)) { throw "MSI not found: $MsiPath" }
    $hash = (Get-FileHash -Path $MsiPath -Algorithm SHA256).Hash
    Log "MSI SHA-256: $hash"
    if ($hash -ne $MsiSha256) {
        $msg = "MSI hash differs from the tested value ($MsiSha256)."
        if ($Force) { Log "WARNING: $msg Continuing because -Force was given." } else { throw "$msg Re-run with -Force to install it anyway." }
    }

    # --- step 1: Neat MSI (copies files; its own driver step is unreliable) -------------
    Log 'Step 1/2: running the Neat MSI...'
    $msiLog = Join-Path $env:TEMP 'NeatND1000-msi.log'
    $p = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', "`"$MsiPath`"", '/qn', '/norestart', '/l*v', "`"$msiLog`"") -Wait -PassThru
    Log "msiexec exit code $($p.ExitCode) (0 = ok, 3010 = ok, reboot pending). MSI log: $msiLog"
    if ($p.ExitCode -notin 0, 3010) { throw "msiexec failed with exit code $($p.ExitCode)." }
    if (-not (Test-Path $InfPath)) { throw "Driver files missing after MSI: $InfPath" }

    # --- step 2: install the Microsoft-signed INF directly ------------------------------
    Log 'Step 2/2: installing the driver package with pnputil...'
    $sig = Get-AuthenticodeSignature -FilePath $CatPath
    Log "Driver catalog signature: $($sig.Status) ($($sig.SignerCertificate.Subject))"
    if ($sig.Status -ne 'Valid') { throw "Driver catalog signature is not valid: $($sig.Status)" }
    $out = Invoke-Native pnputil.exe @('/add-driver', $InfPath, '/install')
    Log $out
    if ($LASTEXITCODE -notin 0, 3010) { throw "pnputil /add-driver failed with exit code $LASTEXITCODE." }

    # --- restart + verify ---------------------------------------------------------------
    $dev = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "$HardwareId*" } | Select-Object -First 1
    if (-not $dev) {
        Log 'NOTE: no ND-1000 is currently connected. The driver is installed; plug the scanner in and it will bind automatically.'
    } else {
        Log "Restarting device $($dev.InstanceId)"
        Log (Invoke-Native pnputil.exe @('/restart-device', $dev.InstanceId))
        Start-Sleep -Seconds 5
        $dev  = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "$HardwareId*" } | Select-Object -First 1
        $prob = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_ProblemCode).Data
        Log "Device: '$($dev.FriendlyName)'  class=$($dev.Class)  status=$($dev.Status)  problemCode=$prob"
        if ($dev.Class -ne 'Image' -or $prob -ne 0) { throw 'Driver installed but the scanner is not bound correctly (expected class Image, problem code 0). See docs/TROUBLESHOOTING.md.' }
    }
    Log 'SUCCESS. Next: install a TWAIN scanning app (docs/INSTALL.md, step 3) and run scripts\Test-NeatND1000.ps1.'
}
catch {
    $failed = $true
    Log "ERROR: $($_.Exception.Message)"
    Log "Full log: $LogPath"
}
finally {
    if ($Elevated) { Read-Host 'Press Enter to close this window' | Out-Null }
}
if ($failed) { exit 1 }

