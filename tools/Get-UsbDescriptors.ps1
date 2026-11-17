<#
.SYNOPSIS
    Dumps the raw USB device/configuration/string descriptors of a device by
    VID/PID, using the parent hub's IOCTLs. Needs NO driver on the device
    itself (works while it shows as "Error / problem 28" in Device Manager).

.EXAMPLE
    ./tools/Get-UsbDescriptors.ps1                                # Neat ND-1000 defaults, prints to console
    ./tools/Get-UsbDescriptors.ps1 -OutFile descriptors.txt       # also save to a file
    ./tools/Get-UsbDescriptors.ps1 -Vid 040A -ProductId 1234      # any other device
#>
[CmdletBinding()]
param(
    [string]$Vid = '1F44',
    [string]$ProductId = '0050',
    [string]$OutFile = ''
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class UsbDesc
{
    [StructLayout(LayoutKind.Sequential)] struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid Guid; public int Flags; public IntPtr Reserved; }
    [DllImport("setupapi.dll", SetLastError=true)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int flags);
    [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA data);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA d, IntPtr detail, int size, out int req, IntPtr info);
    [DllImport("setupapi.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP_DEVICE_INTERFACE_DATA d, byte[] detail, int size, out int req, IntPtr info);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern SafeFileHandle CreateFile(string n, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, int inLen, byte[] outb, int outLen, out int ret, IntPtr ov);

    const uint IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION = 0x00220410;

    public static List<string> HubPaths()
    {
        var res = new List<string>();
        Guid hub = new Guid("F18A0E88-C30C-11D0-8815-00A0C906BED8");
        IntPtr set = SetupDiGetClassDevs(ref hub, IntPtr.Zero, IntPtr.Zero, 0x12); // PRESENT | DEVICEINTERFACE
        for (int i = 0; ; i++)
        {
            var d = new SP_DEVICE_INTERFACE_DATA(); d.cbSize = Marshal.SizeOf(d);
            if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hub, i, ref d)) break;
            int req; SetupDiGetDeviceInterfaceDetail(set, ref d, IntPtr.Zero, 0, out req, IntPtr.Zero);
            var buf = new byte[req];
            Marshal.WriteInt32(Marshal.UnsafeAddrOfPinnedArrayElement(buf, 0), IntPtr.Size == 8 ? 8 : 6);
            if (SetupDiGetDeviceInterfaceDetail(set, ref d, buf, req, out req, IntPtr.Zero))
                res.Add(Encoding.Unicode.GetString(buf, 4, req - 4).TrimEnd('\0'));
        }
        SetupDiDestroyDeviceInfoList(set);
        return res;
    }

    public static byte[] GetDescriptor(string hubPath, int port, byte type, byte index, ushort langId, ushort length)
    {
        using (var h = CreateFile(hubPath, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) return null;
            int hdr = 12;
            var b = new byte[hdr + length];
            BitConverter.GetBytes(port).CopyTo(b, 0);
            b[4] = 0x80; b[5] = 0x06;                                  // GET_DESCRIPTOR, device-to-host
            BitConverter.GetBytes((ushort)((type << 8) | index)).CopyTo(b, 6);
            BitConverter.GetBytes(langId).CopyTo(b, 8);
            BitConverter.GetBytes(length).CopyTo(b, 10);
            int ret;
            if (!DeviceIoControl(h, IOCTL_USB_GET_DESCRIPTOR_FROM_NODE_CONNECTION, b, b.Length, b, b.Length, out ret, IntPtr.Zero)) return null;
            var o = new byte[Math.Max(0, ret - hdr)];
            Array.Copy(b, hdr, o, 0, o.Length);
            return o;
        }
    }
}
'@

function Hex($b) { ($b | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' }

$dev = Get-PnpDevice -PresentOnly | Where-Object InstanceId -like "USB\VID_${Vid}&PID_${ProductId}\*" | Select-Object -First 1
if (-not $dev) { Write-Error "No present device with VID_$Vid&PID_$ProductId"; exit 1 }
$parent = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_Parent).Data
$port   = [int](Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_Address).Data
$want   = $parent.Replace('\', '#').ToLower()
$hubPath = [UsbDesc]::HubPaths() | Where-Object { $_.ToLower().Contains($want) } | Select-Object -First 1
if (-not $hubPath) { Write-Error "Could not find hub interface for parent $parent"; exit 1 }

$out = New-Object System.Collections.Generic.List[string]
$out.Add("USB descriptor dump $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$out.Add("Device : $($dev.InstanceId)  ($($dev.FriendlyName))")
$out.Add("Parent : $parent  port $port")
$out.Add(('=' * 70))

$dd = [UsbDesc]::GetDescriptor($hubPath, $port, 1, 0, 0, 18)
if (-not $dd) { Write-Error 'Device descriptor request failed'; exit 1 }
$out.Add("DEVICE  : $(Hex $dd)")
$bcdUsb = '{0:X4}' -f ([int]$dd[3] -shl 8 -bor $dd[2])
$out.Add(("  bcdUSB={0} class={1:X2}/{2:X2}/{3:X2} maxPkt0={4} VID={5:X4} PID={6:X4} bcdDev={7:X4} iMfr={8} iProd={9} iSer={10} nConfigs={11}" -f `
    $bcdUsb, $dd[4], $dd[5], $dd[6], $dd[7], ([int]$dd[9] -shl 8 -bor $dd[8]), ([int]$dd[11] -shl 8 -bor $dd[10]), ([int]$dd[13] -shl 8 -bor $dd[12]), $dd[14], $dd[15], $dd[16], $dd[17]))

$c9 = [UsbDesc]::GetDescriptor($hubPath, $port, 2, 0, 0, 9)
$total = [int]$c9[3] -shl 8 -bor $c9[2]
$cfg = [UsbDesc]::GetDescriptor($hubPath, $port, 2, 0, 0, [uint16]$total)
$out.Add("CONFIG  ($total bytes): $(Hex $cfg)")

# Walk the descriptors
$i = 0
while ($i -lt $cfg.Length) {
    $len = $cfg[$i]; $typ = $cfg[$i + 1]
    if ($len -lt 2) { break }
    $seg = $cfg[$i..($i + $len - 1)]
    switch ($typ) {
        2 { $out.Add("  Configuration: nInterfaces=$($seg[4]) bConfigValue=$($seg[5]) attrs=0x$('{0:X2}' -f $seg[7]) maxPower=$($seg[8]*2)mA") }
        4 { $out.Add(("  Interface {0} alt {1}: nEndpoints={2} class={3:X2}/{4:X2}/{5:X2}" -f $seg[2], $seg[3], $seg[4], $seg[5], $seg[6], $seg[7])) }
        5 {
            $dir = if ($seg[2] -band 0x80) { 'IN ' } else { 'OUT' }
            $tt  = @('Control','Isochronous','Bulk','Interrupt')[$seg[3] -band 3]
            $out.Add(("    Endpoint 0x{0:X2} {1} {2} maxPacket={3} interval={4}" -f $seg[2], $dir, $tt, ([int]$seg[5] -shl 8 -bor $seg[4]), $seg[6]))
        }
        default { $out.Add("  (type 0x$('{0:X2}' -f $typ)) $(Hex $seg)") }
    }
    $i += $len
}

foreach ($pair in @(@('Manufacturer', $dd[14]), @('Product', $dd[15]), @('Serial', $dd[16]))) {
    if ($pair[1]) {
        $s = [UsbDesc]::GetDescriptor($hubPath, $port, 3, [byte]$pair[1], 0x0409, 255)
        if ($s -and $s.Length -gt 2) { $out.Add("STRING  $($pair[0]): '$([Text.Encoding]::Unicode.GetString($s, 2, $s.Length - 2))'") }
        else { $out.Add("STRING  $($pair[0]): <unreadable>") }
    }
}

$out | ForEach-Object { Write-Host $_ }
if ($OutFile) {
    $out | Set-Content -Path $OutFile -Encoding UTF8
    Write-Host "`nSaved to $OutFile" -ForegroundColor Green
}

