# Troubleshooting

First, run the self-test and see which row fails:

```powershell
.\scripts\Test-NeatND1000.ps1
```

| Failing row | Likely cause / fix |
|---|---|
| *Scanner connected* – FAIL | Windows doesn't see the scanner. Power on, change USB port/cable, no hub or dock, USB 2.0/3.0 port both fine. Device Manager should show *something* appear when you plug it in. |
| *Driver bound* – FAIL | Driver not installed or not bound. Re-run `Install.cmd`. Or: unplug, `pnputil /add-driver "C:\Program Files\Common Files\The Neat Company\Drivers\Neat ADF Scanner\NeatADFScanner.inf" /install` (admin), plug in. |
| *File present …* – FAIL | The Neat MSI didn't install. See `%TEMP%\NeatND1000-msi.log`; re-run the installer. |
| *WIA lists the scanner* – FAIL | The *Windows Image Acquisition* service is stopped or the driver isn't bound. `Get-Service stisvc` should be *Running*; start it, or reboot. |
| *TWAIN data source opens* – FAIL | The 32-bit TWAIN source can't open: driver files incomplete or device not bound. Reinstall (`Install.cmd`). |

## Common problems

**Device Manager shows "Neat ADF Scanner" with a yellow ! – "Drivers for this device are not installed (Code 28)".**
No driver is bound. Run `Install.cmd` (or do manual step 4 in [INSTALL.md](INSTALL.md)).

**Neat Scan Utility says "no scanner connected".**
1. Run `Test-NeatND1000.ps1`; fix any FAIL first.
2. Installing Neat's MSI alone is **not enough** on current Windows (its driver step undoes itself) – the
   `pnputil` step must have run. `Install.cmd` does both.
3. Task Manager → end every `NeatTwainWrapper` process and `Neat Scan Utility` process, then start the app again.
4. Unplug the scanner, wait 10 s, plug it in, wait for the Windows "connected" sound, start the app.
   (Neat's own article for this symptom: [Scanner Not Detected in Windows 11](https://support.neat.com/desktop/scanner-not-detected-in-windows-11).)

**Windows "Scan" app: "Problem scanning – Something went wrong."**
Expected. The scanner is listed but Neat's 2013 WIA driver can't handle the settings the modern app sends. Use
Neat Scan Utility or a TWAIN app. (Details in [DIAGNOSIS.md](DIAGNOSIS.md).)

**Neat Scan Utility doesn't open (nothing appears).**
Start it from the **Start menu**. If you launch it from a terminal or an IDE-integrated shell, an inherited
`ELECTRON_RUN_AS_NODE=1` environment variable makes Electron apps exit immediately. Check with
`$env:ELECTRON_RUN_AS_NODE`; remove it (`Remove-Item Env:ELECTRON_RUN_AS_NODE`) or delete it from *System Properties →
Environment Variables*.

**Blank (white) pages from Neat Scan Utility on Windows 11.**
Neat lists this as a known issue with Windows 11 + Neat scanners ([Neat status page](https://support.neat.com/private-articles/neat-status)).
Not seen in testing here; try another TWAIN app and open an issue with details.

**"Administrator permission was declined".**
The driver can't be installed without the Windows permission prompt. Re-run and click **Yes**, or run from an
administrator PowerShell.

**"MSI hash differs from the tested value".**
Neat changed or re-published the file, or the download was corrupted/intercepted. Re-download; if you trust the new
file, run `scripts\Install-NeatND1000.ps1 -Force`.

**"Could not download the Neat driver".**
Proxy or firewall. Download the MSI elsewhere (link in [INSTALL.md](INSTALL.md)) and use `-MsiPath`.

**SmartScreen / antivirus warns about `Install.cmd`.**
It's a small script from the internet; read it (it only starts `Install.ps1`). **More info → Run anyway**, or run
`.\Install.ps1` from PowerShell instead.

**Install worked but scanner stopped working after a Windows feature update.**
If a Windows feature update ever leaves the scanner unbound (Code 28 again), re-run `Install.cmd`; it's safe to repeat.

## Collecting information for a bug report

```powershell
.\scripts\Test-NeatND1000.ps1
Get-Content $env:TEMP\NeatND1000-install.log
.\tools\Get-UsbDescriptors.ps1          # USB descriptors (no driver needed)
```

Please remove your scanner's serial number before posting logs publicly.

## Uninstall / start over

```powershell
.\scripts\Uninstall-NeatND1000.ps1
```

then run `Install.cmd` again.

