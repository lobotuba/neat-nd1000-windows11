<#
.SYNOPSIS
    Minimal 32-bit TWAIN host: opens the DSM, lists data sources, opens the one
    matching -Match (default "Neat"), reports result/condition codes, closes it.
    MUST run in 32-bit PowerShell (the Neat data source is 32-bit):
      & "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -File tools\Test-TwainSource.ps1
#>
param([string]$Match = 'Neat')
if ([IntPtr]::Size -ne 4) { Write-Error 'Run in 32-bit PowerShell (SysWOW64).'; exit 1 }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, Pack = 2, CharSet = CharSet.Ansi)]
public struct TW_IDENTITY {
    public uint Id; public ushort Major, Minor, Language, Country;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 34)] public string Info;
    public ushort ProtoMajor, ProtoMinor; public uint Groups;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 34)] public string Manufacturer;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 34)] public string Family;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 34)] public string Product;
}
[StructLayout(LayoutKind.Sequential, Pack = 2)] public struct TW_STATUS { public ushort ConditionCode; public ushort Data; }
public static class Twain {
    [DllImport("twain_32.dll", EntryPoint = "DSM_Entry")] public static extern ushort Dsm(ref TW_IDENTITY o, IntPtr d, uint dg, ushort dat, ushort msg, IntPtr data);
    [DllImport("twain_32.dll", EntryPoint = "DSM_Entry")] public static extern ushort DsmId(ref TW_IDENTITY o, IntPtr d, uint dg, ushort dat, ushort msg, ref TW_IDENTITY data);
    [DllImport("twain_32.dll", EntryPoint = "DSM_Entry")] public static extern ushort DsmIdDs(ref TW_IDENTITY o, ref TW_IDENTITY d, uint dg, ushort dat, ushort msg, ref TW_STATUS data);
    [DllImport("twain_32.dll", EntryPoint = "DSM_Entry")] public static extern ushort DsmSt(ref TW_IDENTITY o, IntPtr d, uint dg, ushort dat, ushort msg, ref TW_STATUS data);
    [DllImport("twain_32.dll", EntryPoint = "DSM_Entry")] public static extern ushort DsmDs(ref TW_IDENTITY o, ref TW_IDENTITY d, uint dg, ushort dat, ushort msg, ref TW_IDENTITY data);
}
'@

$rcName = @{0 = 'SUCCESS'; 1 = 'FAILURE'; 2 = 'CHECKSTATUS'; 3 = 'CANCEL'; 4 = 'DSEVENT'; 5 = 'NOTDSEVENT'; 6 = 'XFERDONE'; 7 = 'ENDOFLIST'; 8 = 'INFONOTSUPPORTED'; 9 = 'DATANOTAVAILABLE'}
$ccName = @{0 = 'SUCCESS'; 1 = 'BUMMER'; 2 = 'LOWMEMORY'; 3 = 'NODS'; 4 = 'MAXCONNECTIONS'; 5 = 'OPERATIONERROR'; 6 = 'BADCAP'; 7 = 'BADPROTOCOL'; 8 = 'BADVALUE'; 9 = 'SEQERROR'; 10 = 'BADDEST'; 11 = 'CAPUNSUPPORTED'; 12 = 'CAPBADOPERATION'; 13 = 'CAPSEQERROR'}

$DG_CONTROL = 1
$app = New-Object TW_IDENTITY
$app.Major = 1; $app.Minor = 0; $app.Language = 13; $app.Country = 1; $app.Info = '1.0'
$app.ProtoMajor = 2; $app.ProtoMinor = 1; $app.Groups = 3
$app.Manufacturer = 'ND1000-dev'; $app.Family = 'Test'; $app.Product = 'Test-TwainSource'

$form = New-Object Windows.Forms.Form; $null = $form.Handle
$pHwnd = [Runtime.InteropServices.Marshal]::AllocHGlobal(4)
[Runtime.InteropServices.Marshal]::WriteInt32($pHwnd, $form.Handle.ToInt32())

function Status { $st = New-Object TW_STATUS; $null = [Twain]::DsmSt([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0008, 1, [ref]$st); $c = $st.ConditionCode; "cc=$c ($($ccName[[int]$c]))" }

$rc = [Twain]::Dsm([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0004, 0x0301, $pHwnd)   # PARENT / OPENDSM
"OPENDSM -> $($rcName[[int]$rc])"
if ($rc -ne 0) { Status; exit 1 }

$found = @()
$ds = New-Object TW_IDENTITY
$rc = [Twain]::DsmId([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0003, 0x0004, [ref]$ds)  # GETFIRST
while ($rc -eq 0) {
    "  source: '$($ds.Product)'  mfr='$($ds.Manufacturer)'  id=$($ds.Id)  proto=$($ds.ProtoMajor).$($ds.ProtoMinor)"
    $found += $ds
    $ds = New-Object TW_IDENTITY
    $rc = [Twain]::DsmId([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0003, 0x0005, [ref]$ds)  # GETNEXT
}
"enumeration ended: $($rcName[[int]$rc])"

$target = $found | Where-Object { $_.Product -match $Match -or $_.Manufacturer -match $Match } | Select-Object -First 1
if ($target) {
    $t = $target
    $rc = [Twain]::DsmId([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0003, 0x0401, [ref]$t)  # IDENTITY / OPENDS
    "OPENDS('$($t.Product)') -> $($rcName[[int]$rc])   $(Status)"
    if ($rc -eq 0) {
        "Data source opened OK (state 4). Closing."
        $null = [Twain]::DsmId([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0003, 0x0402, [ref]$t)   # CLOSEDS
    }
} else { "No source matching '$Match'." }

$null = [Twain]::Dsm([ref]$app, [IntPtr]::Zero, $DG_CONTROL, 0x0004, 0x0302, $pHwnd)  # CLOSEDSM
