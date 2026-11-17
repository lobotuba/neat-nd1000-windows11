# How the ND-1000 was diagnosed

Condensed investigation notes (Windows 11 build 26300 x64, one ND-1000). Useful if you are chasing the same
symptom on another orphaned USB scanner.

## Symptom

- Device Manager: *Neat ADF Scanner*, `CM_PROB_FAILED_INSTALL` (**Code 28**, no driver bound).
- Neat Scan Utility 1.5.10 installed and running: **"no scanner connected"**.
- The 2023 log of the Scan Utility's TWAIN helper (`~\Neat-Logs\NeatDSULog-*.log`) already showed
  *"Unable to load the capture source driver. Make sure the driver is properly installed."*

## The device (read with no driver at all)

`tools/Get-UsbDescriptors.ps1` asks the parent hub for the descriptors, so it works on a device with no driver.

| Field | Value |
|---|---|
| USB ID | `VID_1F44` / `PID_0050`, bcdDevice `06A6` |
| Strings | manufacturer "The Neat Company", product "Neat ADF Scanner" |
| Speed / config | USB 2.0 high-speed, 1 configuration, 1 interface |
| Class / subclass / protocol | `FF / FF / FF` (vendor specific) |
| Endpoints | `0x81` bulk IN 512 B · `0x02` bulk OUT 512 B · `0x83` interrupt IN 1 B (interval 8) |

Vendor-specific class ⇒ no inbox class driver can ever bind; a vendor driver package is required.

## What turned out to be wrong

1. **Nothing was bound** – no INF for `VID_1F44&PID_0050` in the driver store.
2. **Neat Scan Utility has no driver.** Its installer is an Electron app plus a .NET TWAIN wrapper
   (`NeatTwainWrapper.exe`, Atalasoft DotTwain). It talks to the scanner **through the TWAIN data source** that
   Neat's original *driver* package installs.
3. **Only two stubs of the original driver survived**: `NeatADFScanner32.ds` / `NeatADFScanner64.ds` in
   `C:\Windows\twain_32` / `twain_64`, plus the registry entries. The supporting DLLs and the WIA driver
   (`NeatADFScanner64.dll`, `NeatADFScannerWIA64.dll`, …) were gone. A TWAIN host test
   (`tools/Test-TwainSource.ps1`, 32-bit) showed the source is *enumerated* but `DG_CONTROL/DAT_IDENTITY/MSG_OPENDS`
   returns `TWRC_FAILURE`, and an ETW file/registry trace showed it never even tried to open the USB device.
4. **Neat still publishes the original package** (linked from their driver page): an MSI containing the INF,
   a catalog signed by *Microsoft Windows Hardware Compatibility Publisher*, x86/x64 TWAIN sources and WIA DLLs. Its
   catalog verifies as valid on Windows 11 (WHQL signatures stay valid after the signing certificate expires), so no
   test-signing or self-signing is needed.
5. **The MSI alone doesn't finish the job.** Its driver step uses DIFxApp (deprecated). In the MSI log it installs the
   INF into the driver store, binds it to the scanner, and then runs a "remove the previous driver of this component"
   step that **uninstalls the package it just installed**. The scanner ends with no driver again (class empty,
   no INF). Installing the same INF with `pnputil /add-driver … /install` works and sticks.

After that: device class *Image*, WIA lists it, `OPENDS` returns SUCCESS, and **Neat Scan Utility scans**.

## Why the Windows Scan app fails

Neat's WIA minidriver is from 2013. The WIA service trace (`C:\Windows\Debug\WIA\wiatrace.log`) shows it rejects
writes with `E_INVALIDARG (0x80070057)` for `Pages`, `Document Handling Select` and `Media Type`, and reports
"property not found" for `STI Driver Version` / `PnP ID`. Modern WIA clients set those, so the scan aborts
("Problem scanning"). The TWAIN path doesn't use those WIA properties. Fixing this would require replacing Neat's
WIA driver (a reimplementation of the scanner protocol); not attempted here.

## Dead end worth recording: libusb

The Neat TWAIN source imports no USB DLLs, and a Microsoft-signed `libusb0.sys` happened to be on the machine, which
suggested the original stack used libusb-win32. That was **wrong**. Binding libusb0 to the scanner (a self-signed
package) worked at the USB level – pyusb/libusb0 could open it, read strings and claim the interface – but the Neat
source still couldn't open because its own support files were missing. The real stack is the standard
STI/WIA class stack (`Class = Image`, `Include = sti.inf`).

Also tried: forcing a driver by writing the device node's `Service`/`ClassGUID` registry values (no INF, no
certificate). Windows accepted the values but kept the device in Code 28 – PnP needs a real matched driver package.

## Method, in short, for similar orphaned scanners

1. `Get-PnpDevice`, device properties (problem code, hardware IDs), and `setupapi`/Kernel-PnP event log.
2. Dump the USB descriptors with no driver (`tools/Get-UsbDescriptors.ps1`).
3. Find what the vendor app expects: registry under `HKLM\SOFTWARE\WOW6432Node\<vendor>` and the TWAIN/WIA locations
   gave the original install paths and file names.
4. Test each layer separately: USB (libusb), TWAIN (`tools/Test-TwainSource.ps1`), WIA (`WIA.DeviceManager`,
   `wiatrace.log`).
5. Look for the vendor's own driver package before writing anything.
6. Read the vendor installer's verbose log (`msiexec /l*v`) – that's where the self-undoing DIFxApp step was visible.
