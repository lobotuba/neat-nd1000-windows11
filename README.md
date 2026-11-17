# Neat ND-1000 scanner on Windows 11

Get a **Neat ND-1000** sheet-fed scanner (also the NC-1000 / NM-1000, which share the driver) working again on
Windows 10/11 64-bit, in about two minutes.

Neat's product line is end-of-life and Windows can show the scanner as an unknown device (Device Manager error
code 28), or Neat Scan Utility says **"no scanner connected"** even after installing Neat's own software.
This repo is a tested, one-click installer for the fix, plus the notes explaining what was actually wrong.

> **It is not a new driver.** It installs **Neat's own official, Microsoft-signed driver**, downloaded from Neat's
> server and checked against a pinned hash, and does the one extra step that Neat's installer fails to do on
> current Windows. Nothing from Neat is redistributed here.

## Quick install

1. Plug the scanner into the PC (directly, not through a hub) and power it on.
2. Get this repo: **Code → Download ZIP**, then right-click the ZIP → **Extract All**.
3. Double-click **`Install.cmd`**. Click **Yes** on the Windows permission prompt. Answer **Y** to install the
   scanning app.
   *(If Windows says "Windows protected your PC": **More info → Run anyway**.)*
4. Put a page in the feeder, open **Neat Scan Utility** from the Start menu, pick the scanner, **Scan**.

Prefer one line? In PowerShell: `irm https://raw.githubusercontent.com/lobotuba/neat-nd1000-windows11/main/bootstrap.ps1 | iex`

Manual steps, silent/IT deployment, uninstall: **[docs/INSTALL.md](docs/INSTALL.md)**.
Something wrong? **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** · run `scripts\Test-NeatND1000.ps1` for a self-check.

## What works / what doesn't

| | |
|---|---|
| Scanning with **Neat Scan Utility 1.5.10** (TWAIN) | ✅ verified with a real scan |
| Device bound to the driver, shows under *Imaging devices*, WIA lists it, TWAIN source opens | ✅ verified (`Test-NeatND1000.ps1`) |
| Windows 11 built-in **Scan** app (WIA) | ❌ lists the scanner but fails with "Problem scanning" – Neat's 2013 WIA driver rejects settings modern Windows sends. Use Neat Scan Utility or another TWAIN app. |
| Other TWAIN apps (e.g. NAPS2 in 32-bit TWAIN mode) | not tested here; should work through the same TWAIN source |
| NC-1000 / NM-1000 | not tested (same driver package per Neat) |

Tested on: Windows 11 x64 (build 26300) with an ND-1000. If you try it on other Windows versions or models,
please open an issue with the result of `scripts\Test-NeatND1000.ps1`.

## What the installer does

1. Downloads `Scanner.Install64.Neat.ADF.MSI.msi` from Neat's [driver page](https://support.neat.com/downloads/download-neat-scanner-drivers-for-windows-or-mac)
   and verifies its SHA-256.
2. Runs the MSI (copies Neat's TWAIN/WIA driver files).
3. **Installs the driver package into Windows with `pnputil`.** This is the step missing from Neat's installer: its
   legacy DIFxApp step installs the driver and then immediately uninstalls it again, leaving the scanner unbound.
4. Restarts the device and verifies it came up as class *Image* with no errors.
5. Optionally installs Neat Scan Utility 1.5.10 (hash-pinned, per user).
6. Runs a self-test.

How this was diagnosed (including the dead ends) is in **[docs/DIAGNOSIS.md](docs/DIAGNOSIS.md)**.

## Repo layout

```text
Install.cmd / Install.ps1     one-click installer (start here)
bootstrap.ps1                 one-line installer
scripts/                      Install-NeatND1000, Uninstall-NeatND1000, Test-NeatND1000, Install-ScanUtility
tools/                        USB descriptor dump, minimal 32-bit TWAIN test host
docs/                         INSTALL, TROUBLESHOOTING, DIAGNOSIS
```

## Disclaimer

Unofficial and unaffiliated with The Neat Company. "Neat" and "NeatDesk" are their trademarks. The scripts only
automate installing Neat's own published driver. Provided as-is under the [MIT license](LICENSE); it installs a
kernel-level device driver and changes system configuration, so read the scripts first if that matters in your
environment.

