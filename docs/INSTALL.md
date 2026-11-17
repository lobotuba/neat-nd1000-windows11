# Installing the Neat ND-1000 on a client machine

Applies to Windows 10 (2004+) and Windows 11, **64-bit**. Needs administrator rights once.

## 0. Before you start

- Scanner powered on, USB cable plugged **directly into the PC** (no hub or dock). It may show as an unknown
  device or "Neat ADF Scanner" with a yellow warning – that's expected before the driver is installed.
- Internet access to `s3.amazonaws.com` (Neat's driver file) and, for the optional app,
  `scissors-autoupdater.s3.amazonaws.com`. Behind a proxy or firewall? See [Offline / locked-down installs](#offline--locked-down-installs).
- Close Neat Scan Utility if it's running.

## 1. Automatic install (recommended)

1. Download this repo (**Code → Download ZIP**), right-click the ZIP → **Extract All…**
2. Double-click **`Install.cmd`**.
   - SmartScreen "Windows protected your PC" → **More info → Run anyway**.
   - Windows permission prompt (UAC) → **Yes**.
3. Answer **Y** when asked about Neat Scan Utility (skip with `N` if you'll use another TWAIN app).
4. The last screen shows a self-test table. All rows should say **PASS**.

Command-line equivalents:

```powershell
.\Install.ps1                 # interactive
.\Install.ps1 -Yes            # no questions, installs the scanning app too
.\Install.ps1 -NoScanUtility  # driver only
```

Logs: `%TEMP%\NeatND1000-install.log` (driver), `%TEMP%\NeatND1000-msi.log` (Neat's MSI).

## 2. Manual install (what the script does)

Run these in order. Steps 3–4 need an **administrator** PowerShell (Start → type *PowerShell* → *Run as administrator*).

1. **Download** Neat's 64-bit driver: <https://s3.amazonaws.com/scanner-drivers/Windows/NeatDesk/x64/Scanner.Install64.Neat.ADF.MSI.msi>
   (linked from [Neat's driver page](https://support.neat.com/downloads/download-neat-scanner-drivers-for-windows-or-mac)).
2. **Verify** it (tested hash):
   ```powershell
   (Get-FileHash .\Scanner.Install64.Neat.ADF.MSI.msi -Algorithm SHA256).Hash
   # E5BF0BA736298BD41C3DF0283732EC539E8311C80098B677CC50C62453888843
   ```
3. **Run the MSI** (silent): `msiexec /i .\Scanner.Install64.Neat.ADF.MSI.msi /qn /norestart`
   It copies the files to `C:\Program Files\Common Files\The Neat Company\Drivers\Neat ADF Scanner\`.
4. **Install the driver package into Windows** – the step the MSI doesn't reliably do:
   ```powershell
   pnputil /add-driver "C:\Program Files\Common Files\The Neat Company\Drivers\Neat ADF Scanner\NeatADFScanner.inf" /install
   ```
   Expect `Driver package added successfully` and `Driver package installed on device: USB\VID_1F44&PID_0050\…`.
   (Scanner not plugged in yet? Plug it in now; Windows binds it automatically.)
5. **Check** in Device Manager: the scanner appears under **Imaging devices** as *Neat ADF Scanner*, no warning icon.
   Or run `scripts\Test-NeatND1000.ps1`.
6. **Install a scanning app** (next section).

No reboot is normally required.

## 3. Scanning apps

| App | Status |
|---|---|
| **Neat Scan Utility 1.5.10** – `scripts\Install-ScanUtility.ps1` (run as a *normal* user, not admin) | ✅ tested, scans work |
| NAPS2 (use the **TWAIN** driver, **32-bit** mode) | untested here |
| Windows built-in **Scan** app | ❌ does not work with this scanner (see [DIAGNOSIS](DIAGNOSIS.md)) |

Neat Scan Utility is a **per-user** install (it goes into `%LOCALAPPDATA%\Programs`). Install it while logged in as
the person who will scan, not from an administrator window of a different account. It may auto-update itself to a
newer version; the driver does not depend on the app version.

## 4. Verify

```powershell
.\scripts\Test-NeatND1000.ps1
```

All PASS ⇒ the scanner is installed correctly. Then load a page and scan from Neat Scan Utility.

## 5. Uninstall

```powershell
.\scripts\Uninstall-NeatND1000.ps1      # removes the driver package and Neat's MSI
```

Remove Neat Scan Utility from *Settings → Apps*.

## Silent / IT deployment

Run elevated (e.g. from your deployment tool as SYSTEM), after staging the MSI locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Install-NeatND1000.ps1 -MsiPath C:\staging\Scanner.Install64.Neat.ADF.MSI.msi
```

Exit code 0 = driver installed and (if the scanner is present) bound correctly. Driver install is per machine;
Neat Scan Utility is per user and must be deployed in the user context.

## Offline / locked-down installs

- **No direct internet:** download the MSI on another PC (step 1 above), verify the hash (step 2), copy it over and run
  `scripts\Install-NeatND1000.ps1 -MsiPath <path-to-msi>`.
- **A newer/different MSI:** the script refuses a hash it hasn't tested; add `-Force` to install it anyway.
- **Application control / EDR** blocking `msiexec` or `pnputil`: whitelist them for this install or use your
  organisation's driver-deployment process; the driver catalog is signed by Microsoft's Hardware Compatibility
  Publisher.

## Facts worth knowing

- Neat's scanner software is **end-of-life**; the download links are Neat's and could disappear. The MSI's SHA-256 is
  recorded above so a copy you saved can still be verified.
- If Neat Scan Utility **won't open at all** (window never appears) and you start it from a terminal/IDE, a stray
  `ELECTRON_RUN_AS_NODE` environment variable can make it exit silently. Start it from the Start menu.
